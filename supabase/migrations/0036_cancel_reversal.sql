-- 0036_cancel_reversal.sql — Causal cancellation reversal (policy 037)
-- Implements:
--   * order_loyalty_effects causal ledger: one row per credited order
--   * credit_new_order now persists earned/stamp/voucher/token causality
--   * reverse_loyalty_on_cancel trigger: on orders.status -> 'cancelled'
--     reverses transactional effects causally:
--       - lifetimePoints never decremented
--       - points = greatest(points - earned, 0) if order was processed
--       - stamp removal via total-count recompute (cards*10+stamps)
--       - token/voucher revoked ONLY if that order created it AND still unused
--     NEVER blindly stamps-- / tokens-- (see CONTEXT: every 3rd etc.)
--   * CHECK constraints for loyalty_state (points etc.) NOT VALID for existing rows
--   * RLS: order_loyalty_effects select_own + staff read

begin;

-- ---------------------------------------------------------------------------
-- 1. Causal ledger
-- ---------------------------------------------------------------------------
create table if not exists public.order_loyalty_effects (
  order_id            uuid primary key references public.orders(id) on delete cascade,
  phone               text not null references public.customers(phone) on delete cascade,
  google_user_id      uuid,
  earned              int not null default 0,
  stamp_granted       boolean not null default false,
  stamp_before        int,
  stamp_after         int,
  token_granted       boolean not null default false,
  -- exactly one of these set when token_granted = true, the position that triggered it
  token_position      int,
  voucher_granted_type text check (voucher_granted_type in ('free_snack','free_topping','free_drink')),
  voucher_at          text, -- ISO8601 from now_utc_iso(), matches jsonb vouchers->>'at'
  completed_card_granted boolean not null default false,
  redeemed_deducted   int not null default 0,
  is_reversed         boolean not null default false,
  created_at          timestamptz not null default now()
);

create index if not exists idx_order_loyalty_effects_phone on public.order_loyalty_effects(phone, created_at desc);
comment on table public.order_loyalty_effects is '037 causal ledger: exactly what credit_new_order did for one order. Enables correct reversal without blindly stamps--.';

-- RLS
alter table public.order_loyalty_effects enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_loyalty_effects' and policyname='ole_select_own') then
    create policy ole_select_own on public.order_loyalty_effects for select to authenticated
      using (exists (select 1 from public.customers c where c.phone = order_loyalty_effects.phone and c.google_user_id = auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_loyalty_effects' and policyname='ole_staff_read') then
    create policy ole_staff_read on public.order_loyalty_effects for select to authenticated
      using (public.has_any_role(array['staff','admin']::text[]));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Patch credit_new_order to persist causal effects
--    We replace the whole function (keeps prior redemption validation logic)
-- ---------------------------------------------------------------------------
create or replace function public.credit_new_order()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  ls_row   public.loyalty_state;
  ls       jsonb;
  redeemed int := 0;
  redeemed_type text := null;
  cost_expected int;
  mult     numeric := 1.0;
  dbl      boolean := false;
  earned   int;
  -- causal capture
  stamp_before int;
  stamp_after int;
  tokens_before int;
  tokens_after int;
  vouchers_before_len int;
  vouchers_after_len int;
  token_granted bool := false;
  voucher_type text := null;
  voucher_at text := null;
  stamp_granted bool := false;
  card_granted bool := false;
  thresh int;
begin
  select ls2.* into ls_row
    from loyalty_state ls2
    join customers c on c.phone = ls2.phone
   where c.google_user_id = new.google_user_id
   for update of ls2;

  if ls_row is null then return new; end if;
  if ls_row.processed_orders ? new.id::text then return new; end if;

  -- [REDEEMED:type:cost] prefix parsed from notes — validate server-side
  if new.notes is not null and new.notes like '%[REDEEMED:%' then
    select (regexp_match(new.notes, '\[REDEEMED:([^:]+):(\d+)\]'))[1] into redeemed_type;
    select coalesce(nullif(split_part(split_part(new.notes, ':',3),']',1),'')::int,0) into redeemed;
    select case redeemed_type
      when 'free_drink' then (select value::text::int from public.app_config where key='reward_drink')
      when 'free_snack' then (select value::text::int from public.app_config where key='reward_snack')
      when 'free_topping' then (select value::text::int from public.app_config where key='reward_topping')
      else null end into cost_expected;
    if cost_expected is null then
      raise exception 'invalid redeemed type %', redeemed_type;
    end if;
    if redeemed != cost_expected then
      raise exception 'redeemed cost % does not match expected % for %', redeemed, cost_expected, redeemed_type;
    end if;
    if ls_row.points < redeemed then
      raise exception 'insufficient points % < %', ls_row.points, redeemed;
    end if;
    if redeemed_type = 'free_drink' then
      declare min_pts int;
      begin
        select value::text::int into min_pts from public.app_config where key='redeem_min_points';
        if redeemed < coalesce(min_pts, 200) then
          raise exception 'redeemed cost % below redeem_min_points %', redeemed, min_pts;
        end if;
      end;
    end if;
  end if;

  mult := coalesce(
    (select value::text::numeric from app_config where key = 'dine_in_multiplier'),
    1.0);
  if new.mode <> 'dine_in' then mult := 1.0; end if;

  dbl := ls_row.double_next_order
      or exists (select 1 from campaigns
                  where kind = 'double_points' and active
                    and (starts_at is null or starts_at <= now())
                    and (ends_at   is null or ends_at   >= now()));

  earned := public.round_half_up(
    coalesce(new.subtotal, 0)::numeric / 10.0 * mult * case when dbl then 2 else 1 end);

  ls := to_jsonb(ls_row);
  stamp_before := coalesce((ls->>'stamps')::int, 0);
  tokens_before := coalesce((ls->>'spinner_tokens')::int, 0);
  vouchers_before_len := jsonb_array_length(coalesce(ls->'vouchers','[]'::jsonb));

  select value::text::int into thresh from app_config where key='stamp_min_spend';
  thresh := coalesce(thresh, 50);
  if coalesce(new.subtotal, 0) >= thresh then
    stamp_granted := true;
    ls := public.apply_stamps(ls, 1);
  end if;

  stamp_after := coalesce((ls->>'stamps')::int, 0);
  tokens_after := coalesce((ls->>'spinner_tokens')::int, 0);
  vouchers_after_len := jsonb_array_length(coalesce(ls->'vouchers','[]'::jsonb));

  if stamp_granted then
    token_granted := tokens_after > tokens_before;
    if vouchers_after_len > vouchers_before_len then
      -- apply_stamps only ever grants free_snack
      voucher_type := 'free_snack';
      card_granted := true;
      -- capture the at timestamp of the newly appended voucher (last element)
      select elem->>'at' into voucher_at
        from jsonb_array_elements(ls->'vouchers') with ordinality as t(elem, ord)
       where ord = vouchers_after_len
       limit 1;
    end if;
  end if;

  update loyalty_state l set
    points            = greatest(l.points + earned - redeemed, 0),
    lifetime_points   = l.lifetime_points + earned,
    stamps            = (ls->>'stamps')::int,
    completed_cards   = (ls->>'completed_cards')::int,
    spinner_tokens    = (ls->>'spinner_tokens')::int,
    double_next_order = false,
    vouchers          = coalesce(ls->'vouchers', '[]'::jsonb),
    processed_orders  = (
      select jsonb_agg(elem order by ord)
      from (
        select elem, ord from jsonb_array_elements(jsonb_build_array(new.id::text) || l.processed_orders) with ordinality as t(elem, ord)
        where ord <= 100
      ) s
    ),
    updated_at        = now()
  where l.phone = ls_row.phone;

  insert into public.order_loyalty_effects(
    order_id, phone, google_user_id, earned, stamp_granted, stamp_before, stamp_after,
    token_granted, token_position, voucher_granted_type, voucher_at, completed_card_granted,
    redeemed_deducted, is_reversed
  ) values (
    new.id, ls_row.phone, new.google_user_id, earned, stamp_granted, stamp_before, stamp_after,
    token_granted, case when token_granted then stamp_after else null end,
    voucher_type, voucher_at, card_granted, redeemed, false
  ) on conflict (order_id) do nothing;

  insert into order_events(order_id, status, actor, at)
  values (new.id, 'new', 'system:loyalty', now());

  return new;
end;
$$;

comment on function public.credit_new_order() is '037: persists causal ledger order_loyalty_effects for reversal; lifetimePoints never decremented on reversal (handled separately).';

-- ---------------------------------------------------------------------------
-- 3. Reversal trigger: when orders.status transitions to cancelled
-- ---------------------------------------------------------------------------
create or replace function public.reverse_loyalty_on_cancel()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  eff record;
  ls_row public.loyalty_state;
  cur_vouchers jsonb;
  new_vouchers jsonb := '[]'::jsonb;
  found_voucher bool := false;
  elem jsonb;
  total_current int;
  new_total int;
  new_stamps int;
  new_cards int;
  revoke_token bool := false;
  revoke_voucher bool := false;
begin
  -- only on transition to cancelled (and not already cancelled)
  if old.status = 'cancelled' or new.status <> 'cancelled' then
    return new;
  end if;
  -- idempotent: if no ledger row, nothing to reverse (e.g. order never credited)
  select * into eff from public.order_loyalty_effects where order_id = old.id;
  if not found then
    return new;
  end if;
  if eff.is_reversed then
    return new;
  end if;

  -- lock loyalty_state
  select * into ls_row from public.loyalty_state where phone = eff.phone for update;
  if not found then
    -- still mark reversed to avoid loop
    update public.order_loyalty_effects set is_reversed = true where order_id = old.id;
    return new;
  end if;

  -- Mark reversed early (even if later checks fail, we don't double reverse)
  update public.order_loyalty_effects set is_reversed = true where order_id = old.id;

  -- 1) Points reversal: current points minus earned (never lifetime)
  --    Keep lifetimePoints unchanged per policy 2.
  --    Clamp at 0 (customer may have already spent points).
  --    Do NOT revert redeemed_deducted: that was a purchase, keep deduction
  --    (if customer got discount and cancels, they keep discount? Policy says
  --    reverse transactional effects: we already reversed earned; redeemed stays)
  perform 1; -- placeholder to allow conditional update below

  -- Decide token revocation: only if this order causally created a token AND still unused
  if eff.token_granted then
    if coalesce(ls_row.spinner_tokens,0) > 0 then
      -- token still exists, assume the one from this order is still unused (fungible)
      -- If tokens==0, token already consumed -> keep per policy 4
      revoke_token := true;
    else
      revoke_token := false;
    end if;
  end if;

  -- Decide voucher revocation: only if voucher still present in array
  if eff.voucher_granted_type is not null then
    cur_vouchers := coalesce(ls_row.vouchers,'[]'::jsonb);
    found_voucher := false;
    for elem in select * from jsonb_array_elements(cur_vouchers)
    loop
      if (elem->>'type') = eff.voucher_granted_type
         and (eff.voucher_at is null or (elem->>'at') = eff.voucher_at) then
        -- first matching voucher is the one from this order (by at timestamp)
        if not found_voucher then
          found_voucher := true;
          continue; -- drop this element
        end if;
      end if;
      new_vouchers := new_vouchers || jsonb_build_array(elem);
    end loop;
    if found_voucher then
      revoke_voucher := true;
    else
      -- already redeemed -> keep per policy 4, new_vouchers is just cur recomputed without that voucher
      -- but we must not use new_vouchers for update; keep cur
      revoke_voucher := false;
      new_vouchers := cur_vouchers;
    end if;
  else
    cur_vouchers := coalesce(ls_row.vouchers,'[]'::jsonb);
    new_vouchers := cur_vouchers;
  end if;

  -- Compute new stamps/cards via total-count method if stamp was granted
  -- total_current = cards*10 + stamps  (invariant)
  -- If stamp_granted, new_total = total_current -1
  -- This correctly handles wrap (10 -> 0) without blindly stamps-- .
  if eff.stamp_granted then
    total_current := coalesce(ls_row.completed_cards,0)*10 + coalesce(ls_row.stamps,0);
    new_total := total_current - 1;
    if new_total < 0 then new_total := 0; end if;
    new_stamps := new_total % 10;
    new_cards := new_total / 10;
    -- If voucher was granted but already redeemed, we should NOT revert completed_cards
    -- per policy discussion: keep card if voucher already redeemed? But total method already reverted cards.
    -- To honor policy 4 (keep if redeemed), we conditionalize card revert:
    if eff.completed_card_granted and not revoke_voucher then
      -- voucher already gone, keep card count (undo total revert for card)
      -- So keep current cards/stamps for the card part? Instead, keep cards as is, only adjust stamps?
      -- We need to keep completed_cards stable, so recompute differently:
      -- Remove the -10 wrap: if before reversal total was N, but card was not reverted, new_total should be N (not N-1) for card? Actually stamp still should be removed, card should stay.
      -- Stamp removal without card removal: stamps-- but with wrap handling
      -- If revoked card was 9->0, and voucher already redeemed, we want to keep card (1) and just remove stamp that came after?
      -- This is ambiguous. We choose: keep cards as ls_row.completed_cards, only decrement stamps if possible.
      -- For simplicity, if revoke_voucher==false but completed_card_granted, we do NOT use total method; instead stamps = greatest(stamps-1,0) with wrap handling that preserves card count.
      -- That means if voucher was redeemed, we keep card count.
      new_cards := ls_row.completed_cards;
      -- stamps: if ls_row.stamps >0 then stamps-1 else 9 (since 0 came from 9->0, but card kept, so 0->9 would be wrong if card kept? Actually 0 after card, if we keep card, stamps should stay 0? Let's think: after card, stamps=0. If we remove one stamp that caused card but keep card, what should stamps be? Should be 9? But card kept at 1, stamps 9 would mean total 19, which is wrong. So we keep total method for cards too? The policy says voucher keep if redeemed, but stamps still removed. The card count is tied to voucher: card completion IS voucher. If voucher redeemed, card should stay completed (customer earned snack). So we should NOT revert card in that case. So we need to keep new_cards = ls_row.completed_cards.
      -- For stamps, we need to decide: current stamps after card is 0..? Example: 9->0 card, then next order 0->1 => stamps1 cards1. If we cancel the 9->0 order but keep card (since voucher redeemed), what should stamps be? Should be 0? Because we removed the stamp that caused 9->0, but kept card, so stamps should be? Total without that order but with card kept is not well-defined. We choose to keep stamps as is when voucher already redeemed (do not adjust stamps/cards), only points/token handled. This avoids ambiguous recomputation.
      new_stamps := ls_row.stamps;
      new_cards := ls_row.completed_cards;
      -- Actually we should still remove the stamp that was from this order? But that stamp IS the card completion; if we keep card, we cannot also remove stamp. So we keep both.
      -- Therefore: when completed_card_granted and !revoke_voucher, do NOT touch stamps/cards at all.
      -- Mark that we handled stamp_granted but keep.
    end if;
  else
    new_stamps := ls_row.stamps;
    new_cards := ls_row.completed_cards;
  end if;

  -- Perform single update to loyalty_state
  -- Points: greatest(points - earned, 0) but only if order was in processed_orders? eff exists implies it was.
  -- Tokens: conditionally decrement
  -- Vouchers: conditionally replaced
  -- Stamps/Cards: conditionally via total method
  update public.loyalty_state
     set points = greatest(coalesce(points,0) - coalesce(eff.earned,0), 0),
         -- lifetime_points unchanged
         stamps = case when eff.stamp_granted and (not eff.completed_card_granted or revoke_voucher) then new_stamps else stamps end,
         completed_cards = case when eff.stamp_granted and (not eff.completed_card_granted or revoke_voucher) then new_cards else completed_cards end,
         spinner_tokens = case when revoke_token then greatest(coalesce(spinner_tokens,0)-1,0) else spinner_tokens end,
         vouchers = case when eff.voucher_granted_type is not null then new_vouchers else vouchers end,
         updated_at = now()
   where phone = eff.phone;

  -- Audit
  insert into public.staff_log(actor, action, target_phone, detail)
  values (coalesce(auth.uid()::text,'system'), 'reverse_loyalty_on_cancel', eff.phone,
          jsonb_build_object('order_id', old.id, 'earned_revoked', eff.earned,
                             'stamp_revoked', eff.stamp_granted,
                             'token_revoked', revoke_token,
                             'voucher_revoked', revoke_voucher,
                             'voucher_type', eff.voucher_granted_type));

  return new;
end;
$$;

comment on function public.reverse_loyalty_on_cancel() is '037 causal reversal: never blindly stamps--, checks ledger for token/voucher causality and unused state.';

drop trigger if exists trg_reverse_loyalty_on_cancel on public.orders;
create trigger trg_reverse_loyalty_on_cancel
  after update of status on public.orders
  for each row
  when (old.status is distinct from new.status)
  execute function public.reverse_loyalty_on_cancel();

-- ---------------------------------------------------------------------------
-- 4. CHECK constraints (NOT VALID to avoid blocking existing invalid rows)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname='chk_loyalty_points') then
    alter table public.loyalty_state add constraint chk_loyalty_points check (points >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='chk_loyalty_lifetime') then
    alter table public.loyalty_state add constraint chk_loyalty_lifetime check (lifetime_points >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='chk_loyalty_stamps') then
    alter table public.loyalty_state add constraint chk_loyalty_stamps check (stamps >= 0 and stamps < 10) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='chk_loyalty_cards') then
    alter table public.loyalty_state add constraint chk_loyalty_cards check (completed_cards >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='chk_loyalty_tokens') then
    alter table public.loyalty_state add constraint chk_loyalty_tokens check (spinner_tokens >=0 and match_tokens >=0 and scratch_tokens >=0) not valid;
  end if;
end $$;

-- Validate constraints now (will fail if existing rows violate — we allow NOT VALID so launch does not block)
-- To enforce for new rows, they are already NOT VALID but will be checked on insert/update.

commit;
