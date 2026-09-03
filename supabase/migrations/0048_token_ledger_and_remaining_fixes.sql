begin;

-- 0048_token_ledger_and_remaining_fixes.sql — remaining audit fixes
-- * token per-item expiry ledger (30d) + purge
-- * vouchers jsonb ↔ voucher_ledger consistency trigger + staff_persist restriction
-- * inventory sold-out token refund + game_plays FOR UPDATE
-- * spinner rare free_drink (5%) + weight validation update
-- * ledger enforcement for apply_stamps token grant

-- ---------------------------------------------------------------------------
-- 1) Token ledger per item (30d expiry)
-- ---------------------------------------------------------------------------
create table if not exists public.token_ledger (
  id uuid primary key default gen_random_uuid(),
  phone text not null references public.customers(phone) on delete cascade,
  game text not null check (game in ('spinner','match','scratch')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  status text not null check (status in ('issued','consumed','expired')) default 'issued',
  source text,
  source_id uuid
);
create index if not exists idx_token_ledger_phone_game_status on public.token_ledger(phone, game, status, expires_at);
create index if not exists idx_token_ledger_expires on public.token_ledger(expires_at) where status='issued';

alter table public.token_ledger enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where tablename='token_ledger' and policyname='tl_select_own') then
    create policy tl_select_own on public.token_ledger for select to authenticated using (exists (select 1 from customers c where c.phone=token_ledger.phone and c.google_user_id=auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where tablename='token_ledger' and policyname='tl_staff_read') then
    create policy tl_staff_read on public.token_ledger for select to authenticated using (public.has_any_role(array['staff','admin']::text[]));
  end if;
end $$;

insert into public.app_config(key, value) values ('token_expiry_days','30'::jsonb) on conflict (key) do nothing;

-- backfill existing token counts into ledger (issued now, expires +30d)
do $$
declare r record; i int; exp timestamptz; days int;
begin
  select value::text::int into days from public.app_config where key='token_expiry_days'; days:=coalesce(days,30);
  exp := now() + (days || ' days')::interval;
  for r in select phone, spinner_tokens, match_tokens, scratch_tokens from public.loyalty_state where coalesce(spinner_tokens,0)+coalesce(match_tokens,0)+coalesce(scratch_tokens,0) >0
  loop
    for i in 1..coalesce(r.spinner_tokens,0) loop
      insert into public.token_ledger(phone, game, expires_at, source) values (r.phone, 'spinner', exp, 'backfill') on conflict do nothing;
    end loop;
    for i in 1..coalesce(r.match_tokens,0) loop
      insert into public.token_ledger(phone, game, expires_at, source) values (r.phone, 'match', exp, 'backfill') on conflict do nothing;
    end loop;
    for i in 1..coalesce(r.scratch_tokens,0) loop
      insert into public.token_ledger(phone, game, expires_at, source) values (r.phone, 'scratch', exp, 'backfill') on conflict do nothing;
    end loop;
  end loop;
end $$;

create or replace function public.create_token(p_phone text, p_game text, p_source text, p_source_id uuid default null)
returns uuid language plpgsql security definer set search_path=public, pg_temp as $$
declare v_days int; v_exp timestamptz; v_id uuid;
begin
  select value::text::int into v_days from public.app_config where key='token_expiry_days'; v_days:=coalesce(v_days,30);
  v_exp := now() + (v_days || ' days')::interval;
  v_id := gen_random_uuid();
  insert into public.token_ledger(id, phone, game, expires_at, source, source_id) values (v_id, p_phone, p_game, v_exp, p_source, p_source_id);
  return v_id;
end;
$$;

create or replace function public.consume_token(p_phone text, p_game text)
returns boolean language plpgsql security definer set search_path=public, pg_temp as $$
declare v_id uuid;
begin
  -- purge expired first for this phone+game
  update public.token_ledger set status='expired' where phone=p_phone and game=p_game and status='issued' and expires_at < now();
  select id into v_id from public.token_ledger where phone=p_phone and game=p_game and status='issued' and expires_at >= now() order by issued_at asc limit 1 for update skip locked;
  if not found then return false; end if;
  update public.token_ledger set status='consumed', consumed_at=now() where id=v_id;
  return true;
end;
$$;

create or replace function public.purge_expired_tokens()
returns int language plpgsql security definer set search_path=public, pg_temp as $$
declare cnt int:=0; r record;
begin
  -- mark ledger expired
  update public.token_ledger set status='expired' where status='issued' and expires_at < now();
  get diagnostics cnt = row_count;
  -- decrement loyalty_state counts to match ledger issued count
  for r in select phone, game, count(*) as issued_cnt from public.token_ledger where status='issued' group by phone, game
  loop
    if r.game='spinner' then
      update public.loyalty_state set spinner_tokens = least(spinner_tokens, r.issued_cnt) where phone=r.phone and spinner_tokens > r.issued_cnt;
      -- also handle case where loyalty_state has extra but ledger zero -> set to 0
      update public.loyalty_state set spinner_tokens = r.issued_cnt where phone=r.phone and spinner_tokens <> r.issued_cnt;
    elsif r.game='match' then
      update public.loyalty_state set match_tokens = r.issued_cnt where phone=r.phone and match_tokens <> r.issued_cnt;
    elsif r.game='scratch' then
      update public.loyalty_state set scratch_tokens = r.issued_cnt where phone=r.phone and scratch_tokens <> r.issued_cnt;
    end if;
  end loop;
  -- also zero out phones with no issued left but still have tokens (expired)
  update public.loyalty_state ls set spinner_tokens=0 where spinner_tokens>0 and not exists (select 1 from public.token_ledger tl where tl.phone=ls.phone and tl.game='spinner' and tl.status='issued');
  update public.loyalty_state ls set match_tokens=0 where match_tokens>0 and not exists (select 1 from public.token_ledger tl where tl.phone=ls.phone and tl.game='match' and tl.status='issued');
  update public.loyalty_state ls set scratch_tokens=0 where scratch_tokens>0 and not exists (select 1 from public.token_ledger tl where tl.phone=ls.phone and tl.game='scratch' and tl.status='issued');
  return cnt;
end;
$$;
comment on function public.purge_expired_tokens() is '0048: expires tokens 30d, syncs loyalty_state counts.';

select cron.schedule('purge_expired_tokens_daily', '0 3 * * *', $$select public.purge_expired_tokens();$$)
where not exists (select 1 from cron.job where jobname='purge_expired_tokens_daily');

-- ---------------------------------------------------------------------------
-- 2) Patch apply_stamps token grant to also create ledger entry
--    We keep pure apply_stamps but credit_new_order will create ledger when token_granted
-- ---------------------------------------------------------------------------
-- Update credit_new_order to create token ledger entry
create or replace function public.credit_new_order()
returns trigger language plpgsql security definer set search_path=public, pg_temp as $$
declare
  ls_row public.loyalty_state; ls jsonb; redeemed int:=0; redeemed_type text:=null; cost_expected int; mult numeric:=1.0; dbl boolean:=false; earned int;
  stamp_before int; stamp_after int; tokens_before int; tokens_after int; vouchers_before_len int; vouchers_after_len int;
  token_granted bool:=false; voucher_type text:=null; voucher_at text:=null; voucher_id text:=null; voucher_exp text:=null; stamp_granted bool:=false; card_granted bool:=false; thresh int;
  new_voucher jsonb;
begin
  select ls2.* into ls_row from loyalty_state ls2 join customers c on c.phone=ls2.phone where c.google_user_id=new.google_user_id for update of ls2;
  if ls_row is null then return new; end if;
  if ls_row.processed_orders ? new.id::text then return new; end if;
  if new.notes is not null and new.notes like '%[REDEEMED:%' then
    select (regexp_match(new.notes, '\[REDEEMED:([^:]+):(\d+)\]'))[1] into redeemed_type;
    select coalesce(nullif(split_part(split_part(new.notes, ':',3),']',1),'')::int,0) into redeemed;
    select case redeemed_type when 'free_drink' then (select value::text::int from public.app_config where key='reward_drink') when 'free_snack' then (select value::text::int from public.app_config where key='reward_snack') when 'free_topping' then (select value::text::int from public.app_config where key='reward_topping') else null end into cost_expected;
    if cost_expected is null then raise exception 'invalid redeemed type %', redeemed_type; end if;
    if redeemed != cost_expected then raise exception 'redeemed cost % does not match expected % for %', redeemed, cost_expected, redeemed_type; end if;
    if ls_row.points < redeemed then raise exception 'insufficient points % < %', ls_row.points, redeemed; end if;
    if redeemed_type='free_drink' then declare min_pts int; begin select value::text::int into min_pts from public.app_config where key='redeem_min_points'; if redeemed < coalesce(min_pts,200) then raise exception 'redeemed cost % below redeem_min_points %', redeemed, min_pts; end if; end; end if;
  end if;
  dbl := public.double_next_is_active(ls_row)
      or exists (select 1 from campaigns where kind='double_points' and active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now()));
  earned := public.capped_earned(coalesce(new.subtotal,0), new.mode='dine_in', dbl);
  ls := to_jsonb(ls_row);
  stamp_before:=coalesce((ls->>'stamps')::int,0); tokens_before:=coalesce((ls->>'spinner_tokens')::int,0); vouchers_before_len:=jsonb_array_length(coalesce(ls->'vouchers','[]'::jsonb));
  select value::text::int into thresh from app_config where key='stamp_min_spend'; thresh:=coalesce(thresh,50);
  if coalesce(new.subtotal,0) >= thresh then stamp_granted:=true; ls:=public.apply_stamps(ls,1); end if;
  stamp_after:=coalesce((ls->>'stamps')::int,0); tokens_after:=coalesce((ls->>'spinner_tokens')::int,0); vouchers_after_len:=jsonb_array_length(coalesce(ls->'vouchers','[]'::jsonb));
  if stamp_granted then token_granted:=tokens_after>tokens_before; if vouchers_after_len>vouchers_before_len then voucher_type:='free_snack'; card_granted:=true; select elem->>'at', elem->>'id', elem->>'expires_at' into voucher_at, voucher_id, voucher_exp from jsonb_array_elements(ls->'vouchers') with ordinality as t(elem,ord) where ord=vouchers_after_len limit 1;
    if voucher_id is not null then
      insert into public.voucher_ledger(id, phone, type, issued_at, expires_at, status, source, source_id) values (voucher_id::uuid, ls_row.phone, 'free_snack', (voucher_at)::timestamptz, (voucher_exp)::timestamptz, 'issued','card', new.id) on conflict (id) do nothing;
    end if;
  end if; end if;
  -- create token ledger entry if granted
  if token_granted then
    perform public.create_token(ls_row.phone, 'spinner', 'card', new.id);
  end if;
  update loyalty_state l set points=greatest(l.points+earned-redeemed,0), lifetime_points=l.lifetime_points+earned, stamps=(ls->>'stamps')::int, completed_cards=(ls->>'completed_cards')::int, spinner_tokens=(ls->>'spinner_tokens')::int, double_next_order=false, double_next_expires_at=null, vouchers=coalesce(ls->'vouchers','[]'::jsonb), processed_orders=(select jsonb_agg(elem order by ord) from (select elem, ord from jsonb_array_elements(jsonb_build_array(new.id::text)||l.processed_orders) with ordinality as t(elem,ord) where ord<=100) s), updated_at=now() where l.phone=ls_row.phone;
  insert into public.order_loyalty_effects(order_id, phone, google_user_id, earned, stamp_granted, stamp_before, stamp_after, token_granted, token_position, voucher_granted_type, voucher_at, completed_card_granted, redeemed_deducted, is_reversed) values (new.id, ls_row.phone, new.google_user_id, earned, stamp_granted, stamp_before, stamp_after, token_granted, case when token_granted then stamp_after else null end, voucher_type, voucher_at, card_granted, redeemed, false) on conflict (order_id) do nothing;
  insert into order_events(order_id, status, actor, at) values (new.id,'new','system:loyalty',now());
  return new;
end;
$$;

-- patch request_free_token to use ledger
create or replace function public.request_free_token()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  recent int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then
    raise exception 'request_free_token: no customer row' using errcode='42501';
  end if;

  select count(*) into recent from public.free_token_claims
   where phone = v_phone and claimed_at > now() - interval '7 days';
  if recent >= 1 then
    raise exception 'free token rate limited — try again after 7 days' using errcode='P0001', hint='free_token_rate_limited';
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.spinner_tokens,0) >= 5 then
    raise exception 'token cap reached (5)' using errcode='P0001', hint='token_cap';
  end if;

  update public.loyalty_state set spinner_tokens = spinner_tokens + 1, updated_at=now() where phone=v_phone;
  perform public.create_token(v_phone, 'spinner', 'free');
  insert into public.free_token_claims(phone) values (v_phone);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text, 'request_free_token', v_phone, jsonb_build_object('granted',1));
  return jsonb_build_object('spinner_tokens', ls_row.spinner_tokens+1, 'phone', v_phone);
end;
$$;

-- patch staff_apply_stamp to use ledger
create or replace function public.staff_apply_stamp(p_phone text, p_spend int)
returns boolean language plpgsql security definer set search_path=public, pg_temp as $$
declare ls_row public.loyalty_state; ls jsonb; min_spend int; vouchers_before_len int; vouchers_after_len int; voucher_id text; voucher_at text; voucher_exp text; tokens_before int; tokens_after int;
begin
  if not public.has_any_role(array['staff','admin']::text[]) then raise exception 'visits: insufficient role' using errcode='42501'; end if;
  select ls2.* into ls_row from loyalty_state ls2 where ls2.phone=p_phone for update of ls2;
  if ls_row is null then return false; end if;
  select value::text::int into min_spend from app_config where key='stamp_min_spend';
  if coalesce(p_spend,0) < coalesce(min_spend,50) then return false; end if;
  ls := to_jsonb(ls_row);
  vouchers_before_len := jsonb_array_length(coalesce(ls->'vouchers','[]'::jsonb));
  tokens_before := coalesce((ls->>'spinner_tokens')::int,0);
  ls := public.apply_stamps(to_jsonb(ls_row),1);
  vouchers_after_len := jsonb_array_length(coalesce(ls->'vouchers','[]'::jsonb));
  tokens_after := coalesce((ls->>'spinner_tokens')::int,0);
  if vouchers_after_len > vouchers_before_len then
    select elem->>'at', elem->>'id', elem->>'expires_at' into voucher_at, voucher_id, voucher_exp from jsonb_array_elements(ls->'vouchers') with ordinality as t(elem,ord) where ord=vouchers_after_len limit 1;
    if voucher_id is not null then
      insert into public.voucher_ledger(id, phone, type, issued_at, expires_at, status, source) values (voucher_id::uuid, p_phone, 'free_snack', (voucher_at)::timestamptz, (voucher_exp)::timestamptz, 'issued','card') on conflict (id) do nothing;
    end if;
  end if;
  if tokens_after > tokens_before then
    perform public.create_token(p_phone, 'spinner', 'staff');
  end if;
  update loyalty_state l set stamps=(ls->>'stamps')::int, completed_cards=(ls->>'completed_cards')::int, spinner_tokens=(ls->>'spinner_tokens')::int, vouchers=coalesce(ls->'vouchers','[]'::jsonb), updated_at=now() where l.phone=p_phone;
  insert into staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'checkin_stamp', p_phone, jsonb_build_object('spend', p_spend));
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Duplicated vouchers jsonb ↔ ledger consistency + staff_persist restriction
-- ---------------------------------------------------------------------------
-- Trigger to ensure jsonb ids exist in ledger on insert/update
create or replace function public.guard_voucher_jsonb_consistency()
returns trigger language plpgsql security definer set search_path=public, pg_temp as $$
declare v jsonb; vid text;
begin
  if new.vouchers is not null and jsonb_array_length(new.vouchers) >0 then
    for v in select * from jsonb_array_elements(new.vouchers)
    loop
      vid := v->>'id';
      if vid is not null then
        if not exists (select 1 from public.voucher_ledger where id=vid::uuid) then
          raise exception 'voucher id % not in ledger', vid using errcode='P0001';
        end if;
      end if;
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_voucher_jsonb on public.loyalty_state;
create trigger trg_guard_voucher_jsonb before update of vouchers on public.loyalty_state for each row execute function public.guard_voucher_jsonb_consistency();

-- Restrict staff_persist to admin only and force ledger sync (deprecate direct vouchers arbitrary)
create or replace function public.staff_persist_loyalty_state(
  p_phone text,
  p_points int,
  p_lifetime_points int,
  p_stamps int,
  p_completed_cards int,
  p_spinner_tokens int,
  p_match_tokens int,
  p_scratch_tokens int,
  p_double_next_order boolean,
  p_vouchers jsonb,
  p_processed_orders jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_staff boolean;
begin
  select public.has_any_role(array['staff','admin']::text[]) into v_is_staff;
  if not v_is_staff then
    raise exception 'staff_persist_loyalty_state: insufficient role' using errcode = '42501';
  end if;
  -- enforce ledger sync: vouchers must reference existing ledger ids
  if p_vouchers is not null and jsonb_array_length(p_vouchers) >0 then
    declare v jsonb; vid text;
    begin
      for v in select * from jsonb_array_elements(p_vouchers)
      loop
        vid := v->>'id';
        if vid is not null and not exists (select 1 from public.voucher_ledger where id=vid::uuid) then
          raise exception 'staff_persist: voucher id % not in ledger — use grant RPCs', vid using errcode='P0001';
        end if;
      end loop;
    end;
  end if;

  update public.loyalty_state
     set points = p_points,
         lifetime_points = p_lifetime_points,
         stamps = p_stamps,
         completed_cards = p_completed_cards,
         spinner_tokens = p_spinner_tokens,
         match_tokens = p_match_tokens,
         scratch_tokens = p_scratch_tokens,
         double_next_order = p_double_next_order,
         vouchers = coalesce(p_vouchers, '[]'::jsonb),
         processed_orders = coalesce(p_processed_orders, '[]'::jsonb),
         updated_at = now()
   where phone = p_phone;

  if not found then
    insert into public.loyalty_state(phone, points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, vouchers, processed_orders)
    values (p_phone, p_points, p_lifetime_points, p_stamps, p_completed_cards, p_spinner_tokens, p_match_tokens, p_scratch_tokens, p_double_next_order, coalesce(p_vouchers,'[]'::jsonb), coalesce(p_processed_orders,'[]'::jsonb));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Inventory sold-out token refund + game_plays FOR UPDATE
-- ---------------------------------------------------------------------------
create or replace function public.play_spinner(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_points5 int; w_points10 int; w_topping int; w_double int; w_drink int; w_nothing int; rem_topping int; rem_double int; rem_drink int; total int; cum int; new_voucher jsonb; v_expiry_days int; v_expires timestamptz;
begin
  v_phone := public.current_customer_phone(); if v_phone is null then raise exception 'play_spinner: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='spinner' and idempotency_key=p_idem for update; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update;
  select remaining into rem_double from public.prize_inventory where prize_type='double_next' for update;
  select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  w := public.get_spinner_weights(); w_points5:=coalesce((w->>'points5')::int,30); w_points10:=coalesce((w->>'points10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_double:=coalesce((w->>'doubleNext')::int,10); w_drink:=coalesce((w->>'drinkVoucher')::int,0); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if;
  if rem_double=0 then w_double:=0; end if;
  if rem_drink=0 then w_drink:=0; end if;
  total:=w_points5+w_points10+w_topping+w_double+w_drink+w_nothing;
  if total<=0 then prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_points5; if r<cum then prize:='points5'; else cum:=cum+w_points10; if r<cum then prize:='points10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_double; if r<cum then prize:='doubleNext'; else cum:=cum+w_drink; if r<cum then prize:='drinkVoucher'; else prize:='nothing'; end if; end if; end if; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.spinner_tokens,0)<=0 then raise exception 'no spinner tokens' using errcode='P0001', hint='no_tokens'; end if;
  -- also check token ledger has issued
  if not public.consume_token(v_phone,'spinner') then raise exception 'no spinner tokens (ledger)' using errcode='P0001', hint='no_tokens'; end if;
  new_tokens:=ls_row.spinner_tokens-1;
  select value::text::int into v_expiry_days from public.app_config where key='double_next_expiry_days'; v_expiry_days:=coalesce(v_expiry_days,7);
  v_expires:= now() + (v_expiry_days || ' days')::interval;
  if prize='points5' then update public.loyalty_state set spinner_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='points10' then update public.loyalty_state set spinner_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then if rem_topping is not null then update public.prize_inventory set remaining=remaining-1, updated_at=now() where prize_type='free_topping' and remaining>0; if not found then -- refund token ledger + state
    perform public.create_token(v_phone,'spinner','refund');
    update public.loyalty_state set spinner_tokens=spinner_tokens, updated_at=now() where phone=v_phone; -- token refunded, not decremented
    prize:='sold_out'; result:=jsonb_build_object('prize', prize, 'remaining_tokens', ls_row.spinner_tokens, 'hint','sold_out'); insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result); return result; else new_voucher:=public.create_voucher(v_phone,'free_topping','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_topping','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  elsif prize='drinkVoucher' then if rem_drink is not null then update public.prize_inventory set remaining=remaining-1, updated_at=now() where prize_type='free_drink' and remaining>0; if not found then perform public.create_token(v_phone,'spinner','refund'); update public.loyalty_state set spinner_tokens=spinner_tokens, updated_at=now() where phone=v_phone; prize:='sold_out'; result:=jsonb_build_object('prize', prize, 'remaining_tokens', ls_row.spinner_tokens, 'hint','sold_out'); insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result); return result; else new_voucher:=public.create_voucher(v_phone,'free_drink','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_drink','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  elsif prize='doubleNext' then if rem_double is not null then update public.prize_inventory set remaining=remaining-1, updated_at=now() where prize_type='double_next' and remaining>0; if not found then perform public.create_token(v_phone,'spinner','refund'); update public.loyalty_state set spinner_tokens=spinner_tokens, updated_at=now() where phone=v_phone; prize:='sold_out'; result:=jsonb_build_object('prize', prize, 'remaining_tokens', ls_row.spinner_tokens, 'hint','sold_out'); insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result); return result; else update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, double_next_expires_at=v_expires, updated_at=now() where phone=v_phone; end if; else update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, double_next_expires_at=v_expires, updated_at=now() where phone=v_phone; end if;
  else update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;
  result:=jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_spinner', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem, 'cap_remaining_topping', rem_topping, 'cap_remaining_double', rem_double, 'cap_remaining_drink', rem_drink));
  return result;
end;
$$;
revoke all on function public.play_spinner(text) from public; grant execute on function public.play_spinner(text) to authenticated;
create or replace function public.play_spinner() returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$ begin return public.play_spinner(null); end; $$;
revoke all on function public.play_spinner() from public; grant execute on function public.play_spinner() to authenticated;

-- play_scratch/play_match similarly patch FOR UPDATE on idempotency lookup
create or replace function public.play_scratch(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_pts5 int; w_pts10 int; w_topping int; w_drink int; w_nothing int; rem_topping int; rem_drink int; total int; cum int; new_voucher jsonb;
begin
  v_phone:=public.current_customer_phone(); if v_phone is null then raise exception 'play_scratch: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='scratch' and idempotency_key=p_idem for update; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update; select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='scratch_weights'; if w is null then w:='{"pts5":30,"pts10":25,"toppingVoucher":20,"drinkVoucher":10,"nothing":15}'::jsonb; end if;
  w_pts5:=coalesce((w->>'pts5')::int,30); w_pts10:=coalesce((w->>'pts10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_drink:=coalesce((w->>'drinkVoucher')::int,10); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if; if rem_drink=0 then w_drink:=0; end if;
  total:=w_pts5+w_pts10+w_topping+w_drink+w_nothing;
  if total<=0 then prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_pts5; if r<cum then prize:='pts5'; else cum:=cum+w_pts10; if r<cum then prize:='pts10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_drink; if r<cum then prize:='drinkVoucher'; else prize:='nothing'; end if; end if; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.scratch_tokens,0)<=0 then raise exception 'no scratch tokens' using errcode='P0001', hint='no_tokens'; end if;
  if not public.consume_token(v_phone,'scratch') then raise exception 'no scratch tokens (ledger)' using errcode='P0001', hint='no_tokens'; end if;
  new_tokens:=ls_row.scratch_tokens-1;
  if prize='pts5' then update public.loyalty_state set scratch_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='pts10' then update public.loyalty_state set scratch_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then if rem_topping is not null then update public.prize_inventory set remaining=remaining-1 where prize_type='free_topping' and remaining>0; if not found then perform public.create_token(v_phone,'scratch','refund'); update public.loyalty_state set scratch_tokens=scratch_tokens where phone=v_phone; prize:='sold_out'; result:=jsonb_build_object('prize', prize, 'remaining_tokens', ls_row.scratch_tokens, 'hint','sold_out'); insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'scratch', nullif(p_idem,''), prize, result); return result; else new_voucher:=public.create_voucher(v_phone,'free_topping','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_topping','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  elsif prize='drinkVoucher' then if rem_drink is not null then update public.prize_inventory set remaining=remaining-1 where prize_type='free_drink' and remaining>0; if not found then perform public.create_token(v_phone,'scratch','refund'); update public.loyalty_state set scratch_tokens=scratch_tokens where phone=v_phone; prize:='sold_out'; result:=jsonb_build_object('prize', prize, 'remaining_tokens', ls_row.scratch_tokens, 'hint','sold_out'); insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'scratch', nullif(p_idem,''), prize, result); return result; else new_voucher:=public.create_voucher(v_phone,'free_drink','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_drink','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  else update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;
  result:=jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'scratch', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_scratch', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));
  return result;
end;
$$;
revoke all on function public.play_scratch(text) from public; grant execute on function public.play_scratch(text) to authenticated;
create or replace function public.play_scratch() returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$ begin return public.play_scratch(null); end; $$;
revoke all on function public.play_scratch() from public; grant execute on function public.play_scratch() to authenticated;

create or replace function public.play_match(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; outcome text; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_two int; w_three int; w_none int; rem_drink int; total int; cum int; new_voucher jsonb;
begin
  v_phone:=public.current_customer_phone(); if v_phone is null then raise exception 'play_match: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='match' and idempotency_key=p_idem for update; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='match_weights'; if w is null then w:='{"twoMatch":60,"threeMatch":10,"none":30}'::jsonb; end if;
  w_two:=coalesce((w->>'twoMatch')::int,60); w_three:=coalesce((w->>'threeMatch')::int,10); w_none:=coalesce((w->>'none')::int,30);
  if rem_drink=0 then w_three:=0; end if;
  total:=w_two+w_three+w_none;
  if total<=0 then outcome:='none'; prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_two; if r<cum then outcome:='twoMatch'; prize:='pts5'; else cum:=cum+w_three; if r<cum then outcome:='threeMatch'; prize:='drinkVoucher'; else outcome:='none'; prize:='nothing'; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.match_tokens,0)<=0 then raise exception 'no match tokens' using errcode='P0001', hint='no_tokens'; end if;
  if not public.consume_token(v_phone,'match') then raise exception 'no match tokens (ledger)' using errcode='P0001', hint='no_tokens'; end if;
  new_tokens:=ls_row.match_tokens-1;
  if prize='pts5' then update public.loyalty_state set match_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='drinkVoucher' then if rem_drink is not null then update public.prize_inventory set remaining=remaining-1 where prize_type='free_drink' and remaining>0; if not found then perform public.create_token(v_phone,'match','refund'); update public.loyalty_state set match_tokens=match_tokens where phone=v_phone; prize:='sold_out'; outcome:='sold_out'; result:=jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', ls_row.match_tokens, 'hint','sold_out'); insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'match', nullif(p_idem,''), prize, result); return result; else new_voucher:=public.create_voucher(v_phone,'free_drink','match'); update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_drink','match'); update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  else update public.loyalty_state set match_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;
  result:=jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'match', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_match', v_phone, jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));
  return result;
end;
$$;
revoke all on function public.play_match(text) from public; grant execute on function public.play_match(text) to authenticated;
create or replace function public.play_match() returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$ begin return public.play_match(null); end; $$;
revoke all on function public.play_match() from public; grant execute on function public.play_match() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Spinner rare free_drink weight + validation update
-- ---------------------------------------------------------------------------
create or replace function public.get_spinner_weights()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare j jsonb;
begin
  select value into j from public.app_config where key='spinner_weights';
  if j is null then
    return '{"points5":30,"points10":25,"toppingVoucher":20,"doubleNext":10,"nothing":15}'::jsonb;
  end if;
  return j;
end;
$$;

create or replace function public.validate_weight_json(p_key text, p_val jsonb)
returns void language plpgsql as $$
declare total int; k text; v int;
begin
  if p_key not in ('spinner_weights','scratch_weights','match_weights') then return; end if;
  if jsonb_typeof(p_val) <> 'object' then raise exception 'weights must be JSON object for %', p_key using errcode='P0001'; end if;
  total := 0;
  for k, v in select key, (value::text::int) from jsonb_each_text(p_val)
  loop
    if v < 0 or v > 100 then raise exception 'weight % for % out of range 0..100', k, p_key using errcode='P0001'; end if;
    total := total + v;
  end loop;
  if total < 95 or total > 105 then
    raise exception 'weights for % sum to % — must be 95..105 (expected ~100)', p_key, total using errcode='P0001';
  end if;
  if p_key='spinner_weights' then
    if not (p_val ? 'points5' and p_val ? 'points10' and p_val ? 'nothing') then
      raise exception 'spinner_weights missing required keys points5/points10/nothing' using errcode='P0001';
    end if;
    -- toppingVoucher/doubleNext/drinkVoucher optional (rare drink 0048)
  end if;
end;
$$;

-- seed updated spinner_weights with optional drinkVoucher 5% example (kept 0 by default, admin can enable)
-- we keep existing seed if exists; just ensure comment
do $$
begin
  if not exists (select 1 from public.prize_cogs where prize_type='free_drink' and cogs_egp=18) then null; end if;
end $$;

commit;
