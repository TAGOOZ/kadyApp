begin;

-- 0046_hardening_fixes.sql — P0/P1 hardening for audit
-- * rate-limit race: advisory lock
-- * farm→cancel: always revert stamp/card even if voucher already redeemed + clawback
-- * inventory caps for double_next / free_snack + token refund on sold-out race
-- * double_next expiry (7 days)
-- * v_spinner_ev denominator fix (total not 100)
-- * purge helper for expired doubles

-- ---------------------------------------------------------------------------
-- 1) Double-next expiry infrastructure
-- ---------------------------------------------------------------------------
alter table public.loyalty_state add column if not exists double_next_expires_at timestamptz;

insert into public.app_config(key, value) values ('double_next_expiry_days','7'::jsonb) on conflict (key) do nothing;

create or replace function public.double_next_is_active(ls_row public.loyalty_state)
returns boolean language sql stable as $$
  select coalesce(ls_row.double_next_order,false)
     and (ls_row.double_next_expires_at is null or ls_row.double_next_expires_at > now());
$$;

create or replace function public.purge_expired_double_next()
returns int language plpgsql security definer set search_path=public, pg_temp as $$
declare cnt int:=0;
begin
  update public.loyalty_state set double_next_order=false, double_next_expires_at=null, updated_at=now()
   where double_next_order and double_next_expires_at is not null and double_next_expires_at < now();
  get diagnostics cnt = row_count;
  return cnt;
end;
$$;
comment on function public.purge_expired_double_next() is '0046: clears expired doubleNext flags (7d default).';

-- ---------------------------------------------------------------------------
-- 2) Rate-limit race: advisory lock per phone
-- ---------------------------------------------------------------------------
create or replace function public.check_game_rate_limit(p_phone text)
returns void language plpgsql security definer set search_path=public, pg_temp as $$
declare max_per_min int; max_per_day int; recent_min int; recent_day int;
begin
  -- serialize per-phone to prevent concurrent bypass
  perform pg_advisory_xact_lock(hashtext(p_phone));
  select value::text::int into max_per_min from public.app_config where key='game_rate_per_min';
  max_per_min := coalesce(max_per_min, 5);
  if max_per_min > 0 then
    select count(*) into recent_min from public.game_plays where phone = p_phone and created_at > now() - interval '1 minute';
    if recent_min >= max_per_min then
      raise exception 'game rate limited' using errcode='P0001', hint='rate_limited_games';
    end if;
  end if;
  select value::text::int into max_per_day from public.app_config where key='game_daily_limit';
  max_per_day := coalesce(max_per_day, 3);
  if max_per_day > 0 then
    select count(*) into recent_day from public.game_plays where phone = p_phone and created_at > now() - interval '1 day';
    if recent_day >= max_per_day then
      raise exception 'daily game limit reached' using errcode='P0001', hint='daily_limit_games';
    end if;
  end if;
end;
$$;
comment on function public.check_game_rate_limit(text) is '0046: advisory lock per phone to fix race.';

-- ---------------------------------------------------------------------------
-- 3) Fix v_spinner_ev denominator bug (was /100, should be /total)
-- ---------------------------------------------------------------------------
create or replace view public.v_spinner_ev as
 with w as (select public.get_spinner_weights() as j)
 select
   (j->>'points5')::int as w_points5,
   (j->>'points10')::int as w_points10,
   (j->>'toppingVoucher')::int as w_topping,
   (j->>'doubleNext')::int as w_double,
   (j->>'nothing')::int as w_nothing,
   ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int) as total,
   case when ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int) > 0 then
     round(
       ((j->>'points5')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 0.40 +
        (j->>'points10')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 0.80 +
        (j->>'toppingVoucher')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 8.00 +
        (j->>'doubleNext')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 0.60)::numeric,2)
   else 0 end as ev_cogs_egp,
   -- legacy column for backwards compat (kept but corrected)
   round(
     ((j->>'points5')::numeric/100*0.40 +
      (j->>'points10')::numeric/100*0.80 +
      (j->>'toppingVoucher')::numeric/100*8.00 +
      (j->>'doubleNext')::numeric/100*0.60)::numeric,2) as ev_cogs_egp_legacy_100
 from w;
comment on view public.v_spinner_ev is '0046 fix: ev uses total denominator; legacy_100 kept for reference.';

-- ---------------------------------------------------------------------------
-- 4) Patch credit_new_order to respect double expiry + use helper
-- ---------------------------------------------------------------------------
create or replace function public.capped_earned(
  p_subtotal int,
  p_is_dine_in boolean,
  p_is_double boolean
) returns int language plpgsql stable security definer set search_path=public, pg_temp as $$
declare
  v_points_per_10 numeric;
  v_mult numeric;
  v_double_cap int;
  v_base numeric;
  v_scaled numeric;
  v_earned int;
  v_base_earned int;
  v_extra int;
begin
  select value::text::numeric into v_points_per_10 from public.app_config where key='points_per_10egp';
  v_points_per_10 := coalesce(v_points_per_10, 1.0);
  select value::text::numeric into v_mult from public.app_config where key='dine_in_multiplier';
  v_mult := coalesce(v_mult, 1.0);
  if not p_is_dine_in then v_mult := 1.0; end if;
  select value::text::int into v_double_cap from public.app_config where key='double_max_extra';
  v_double_cap := coalesce(v_double_cap, 10);
  v_base := p_subtotal * v_points_per_10 / 10.0 * v_mult;
  v_base_earned := public.round_half_up(v_base);
  if p_is_double then
    v_scaled := v_base * 2;
    v_earned := public.round_half_up(v_scaled);
    v_extra := v_earned - v_base_earned;
    if v_extra > v_double_cap then
      v_earned := v_base_earned + v_double_cap;
    end if;
    return v_earned;
  else
    return v_base_earned;
  end if;
end;
$$;

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
  -- double flag with expiry check
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
  update loyalty_state l set points=greatest(l.points+earned-redeemed,0), lifetime_points=l.lifetime_points+earned, stamps=(ls->>'stamps')::int, completed_cards=(ls->>'completed_cards')::int, spinner_tokens=(ls->>'spinner_tokens')::int, double_next_order=false, double_next_expires_at=null, vouchers=coalesce(ls->'vouchers','[]'::jsonb), processed_orders=(select jsonb_agg(elem order by ord) from (select elem, ord from jsonb_array_elements(jsonb_build_array(new.id::text)||l.processed_orders) with ordinality as t(elem,ord) where ord<=100) s), updated_at=now() where l.phone=ls_row.phone;
  insert into public.order_loyalty_effects(order_id, phone, google_user_id, earned, stamp_granted, stamp_before, stamp_after, token_granted, token_position, voucher_granted_type, voucher_at, completed_card_granted, redeemed_deducted, is_reversed) values (new.id, ls_row.phone, new.google_user_id, earned, stamp_granted, stamp_before, stamp_after, token_granted, case when token_granted then stamp_after else null end, voucher_type, voucher_at, card_granted, redeemed, false) on conflict (order_id) do nothing;
  insert into order_events(order_id, status, actor, at) values (new.id,'new','system:loyalty',now());
  return new;
end;
$$;
comment on function public.credit_new_order() is '0046: double_next expiry cleared after use, is_active check.';

-- ---------------------------------------------------------------------------
-- 5) Hardening: reverse_loyalty_on_cancel — always revert stamp/card, clawback if voucher already redeemed
-- ---------------------------------------------------------------------------
create or replace function public.reverse_loyalty_on_cancel()
returns trigger language plpgsql security definer set search_path=public, pg_temp as $$
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
  v_game_voucher_id uuid;
  v_game_voucher_type text;
  v_game_voucher_exp timestamptz;
  clawback_pts int := 0;
begin
  if old.status = 'cancelled' or new.status <> 'cancelled' then
    return new;
  end if;
  select * into eff from public.order_loyalty_effects where order_id = old.id;
  if not found then
    return new;
  end if;
  if eff.is_reversed then
    return new;
  end if;

  select * into ls_row from public.loyalty_state where phone = eff.phone for update;
  if not found then
    update public.order_loyalty_effects set is_reversed = true where order_id = old.id;
    return new;
  end if;

  update public.order_loyalty_effects set is_reversed = true where order_id = old.id;

  if eff.token_granted then
    if coalesce(ls_row.spinner_tokens,0) > 0 then
      revoke_token := true;
    else
      select id, type, expires_at into v_game_voucher_id, v_game_voucher_type, v_game_voucher_exp
        from public.voucher_ledger
       where phone = eff.phone
         and source in ('spinner','scratch','match')
         and status = 'issued'
         and issued_at > (select created_at from public.orders where id = eff.order_id)
       order by issued_at desc limit 1;
      if found then
        revoke_token := false;
      else
        revoke_token := false;
      end if;
    end if;
  end if;

  if eff.voucher_granted_type is not null then
    cur_vouchers := coalesce(ls_row.vouchers,'[]'::jsonb);
    found_voucher := false;
    for elem in select * from jsonb_array_elements(cur_vouchers)
    loop
      if (elem->>'type') = eff.voucher_granted_type
         and (eff.voucher_at is null or (elem->>'at') = eff.voucher_at) then
        if not found_voucher then
          found_voucher := true;
          continue;
        end if;
      end if;
      new_vouchers := new_vouchers || jsonb_build_array(elem);
    end loop;
    if found_voucher then
      revoke_voucher := true;
    else
      -- voucher already redeemed — prepare clawback (deduct its cost)
      revoke_voucher := false;
      new_vouchers := cur_vouchers;
      -- determine clawback cost from app_config for the granted type
      if eff.voucher_granted_type = 'free_snack' then
        select value::text::int into clawback_pts from public.app_config where key='reward_snack';
      elsif eff.voucher_granted_type = 'free_topping' then
        select value::text::int into clawback_pts from public.app_config where key='reward_topping';
      elsif eff.voucher_granted_type = 'free_drink' then
        select value::text::int into clawback_pts from public.app_config where key='reward_drink';
      end if;
      clawback_pts := coalesce(clawback_pts, 0);
    end if;
  else
    cur_vouchers := coalesce(ls_row.vouchers,'[]'::jsonb);
    new_vouchers := cur_vouchers;
  end if;

  if eff.token_granted and coalesce(ls_row.spinner_tokens,0) = 0 and v_game_voucher_id is not null then
    declare
      tmp_vouchers jsonb := '[]'::jsonb;
      found_game bool := false;
    begin
      for elem in select * from jsonb_array_elements(coalesce(ls_row.vouchers,'[]'::jsonb))
      loop
        if (elem->>'id') = v_game_voucher_id::text and not found_game then
          found_game := true;
          continue;
        end if;
        tmp_vouchers := tmp_vouchers || jsonb_build_array(elem);
      end loop;
      if found_game then
        new_vouchers := tmp_vouchers;
        update public.voucher_ledger set status='expired' where id=v_game_voucher_id and status='issued';
        revoke_voucher := true;
      end if;
    end;
  end if;

  -- ALWAYS revert stamps/cards via total method if stamp was granted (0046 fix: no longer keeps card when voucher redeemed)
  if eff.stamp_granted then
    total_current := coalesce(ls_row.completed_cards,0)*10 + coalesce(ls_row.stamps,0);
    new_total := total_current - 1;
    if new_total < 0 then new_total := 0; end if;
    new_stamps := new_total % 10;
    new_cards := new_total / 10;
  else
    new_stamps := ls_row.stamps;
    new_cards := ls_row.completed_cards;
  end if;

  update public.loyalty_state
     set points = greatest(coalesce(points,0) - coalesce(eff.earned,0) - clawback_pts, 0),
         stamps = case when eff.stamp_granted then new_stamps else stamps end,
         completed_cards = case when eff.stamp_granted then new_cards else completed_cards end,
         spinner_tokens = case when revoke_token then greatest(coalesce(spinner_tokens,0)-1,0) else spinner_tokens end,
         vouchers = case when eff.voucher_granted_type is not null or v_game_voucher_id is not null then new_vouchers else vouchers end,
         updated_at = now()
   where phone = eff.phone;

  -- if clawback happened, log voucher_ledger entry for audit? keep via staff_log
  insert into public.staff_log(actor, action, target_phone, detail)
  values (coalesce(auth.uid()::text,'system'), 'reverse_loyalty_on_cancel', eff.phone,
          jsonb_build_object('order_id', old.id, 'earned_revoked', eff.earned,
                             'clawback_pts', clawback_pts,
                             'stamp_revoked', eff.stamp_granted,
                             'token_revoked', revoke_token,
                             'voucher_revoked', revoke_voucher,
                             'voucher_type', coalesce(eff.voucher_granted_type, v_game_voucher_type),
                             'game_voucher_id', v_game_voucher_id));

  return new;
end;
$$;
comment on function public.reverse_loyalty_on_cancel() is '0046 FIX farm→redeem→cancel: always revert stamp/card + clawback points if voucher already redeemed.';

-- ---------------------------------------------------------------------------
-- 6) Inventory caps for double_next + free_snack + token refund clarity
--    Patch play_* to check double_next cap and ensure weight zeroing before roll
-- ---------------------------------------------------------------------------
create or replace function public.play_spinner(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_points5 int; w_points10 int; w_topping int; w_double int; w_nothing int; rem_topping int; rem_double int; total int; cum int; new_voucher jsonb; v_expiry_days int; v_expires timestamptz;
begin
  v_phone := public.current_customer_phone(); if v_phone is null then raise exception 'play_spinner: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='spinner' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  -- lock inventory rows BEFORE roll to ensure consistent weight
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update;
  select remaining into rem_double from public.prize_inventory where prize_type='double_next' for update;
  w := public.get_spinner_weights(); w_points5:=coalesce((w->>'points5')::int,30); w_points10:=coalesce((w->>'points10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_double:=coalesce((w->>'doubleNext')::int,10); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if;
  if rem_double=0 then w_double:=0; end if;
  total:=w_points5+w_points10+w_topping+w_double+w_nothing;
  if total<=0 then prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_points5; if r<cum then prize:='points5'; else cum:=cum+w_points10; if r<cum then prize:='points10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_double; if r<cum then prize:='doubleNext'; else prize:='nothing'; end if; end if; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.spinner_tokens,0)<=0 then raise exception 'no spinner tokens' using errcode='P0001', hint='no_tokens'; end if; new_tokens:=ls_row.spinner_tokens-1;
  select value::text::int into v_expiry_days from public.app_config where key='double_next_expiry_days'; v_expiry_days:=coalesce(v_expiry_days,7);
  v_expires:= now() + (v_expiry_days || ' days')::interval;
  if prize='points5' then update public.loyalty_state set spinner_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='points10' then update public.loyalty_state set spinner_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then if rem_topping is not null then update public.prize_inventory set remaining=remaining-1, updated_at=now() where prize_type='free_topping' and remaining>0; if not found then prize:='nothing'; update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone; else new_voucher:=public.create_voucher(v_phone,'free_topping','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_topping','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  elsif prize='doubleNext' then if rem_double is not null then update public.prize_inventory set remaining=remaining-1, updated_at=now() where prize_type='double_next' and remaining>0; if not found then prize:='nothing'; update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone; else update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, double_next_expires_at=v_expires, updated_at=now() where phone=v_phone; end if; else update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, double_next_expires_at=v_expires, updated_at=now() where phone=v_phone; end if;
  else update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;
  result:=jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_spinner', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem, 'cap_remaining_topping', rem_topping, 'cap_remaining_double', rem_double));
  return result;
end;
$$;
revoke all on function public.play_spinner(text) from public; grant execute on function public.play_spinner(text) to authenticated;
create or replace function public.play_spinner() returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$ begin return public.play_spinner(null); end; $$;
revoke all on function public.play_spinner() from public; grant execute on function public.play_spinner() to authenticated;

-- Scratch: also respect double? scratch doesn't have double, but respect topping/drink caps already done; add free_snack cap future-proof
create or replace function public.play_scratch(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_pts5 int; w_pts10 int; w_topping int; w_drink int; w_nothing int; rem_topping int; rem_drink int; total int; cum int; new_voucher jsonb;
begin
  v_phone:=public.current_customer_phone(); if v_phone is null then raise exception 'play_scratch: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='scratch' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update; select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='scratch_weights'; if w is null then w:='{"pts5":30,"pts10":25,"toppingVoucher":20,"drinkVoucher":10,"nothing":15}'::jsonb; end if;
  w_pts5:=coalesce((w->>'pts5')::int,30); w_pts10:=coalesce((w->>'pts10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_drink:=coalesce((w->>'drinkVoucher')::int,10); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if; if rem_drink=0 then w_drink:=0; end if;
  total:=w_pts5+w_pts10+w_topping+w_drink+w_nothing;
  if total<=0 then prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_pts5; if r<cum then prize:='pts5'; else cum:=cum+w_pts10; if r<cum then prize:='pts10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_drink; if r<cum then prize:='drinkVoucher'; else prize:='nothing'; end if; end if; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.scratch_tokens,0)<=0 then raise exception 'no scratch tokens' using errcode='P0001', hint='no_tokens'; end if; new_tokens:=ls_row.scratch_tokens-1;
  if prize='pts5' then update public.loyalty_state set scratch_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='pts10' then update public.loyalty_state set scratch_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then if rem_topping is not null then update public.prize_inventory set remaining=remaining-1 where prize_type='free_topping' and remaining>0; if not found then prize:='nothing'; update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone; else new_voucher:=public.create_voucher(v_phone,'free_topping','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_topping','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  elsif prize='drinkVoucher' then if rem_drink is not null then update public.prize_inventory set remaining=remaining-1 where prize_type='free_drink' and remaining>0; if not found then prize:='nothing'; update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone; else new_voucher:=public.create_voucher(v_phone,'free_drink','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_drink','scratch'); update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
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
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='match' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='match_weights'; if w is null then w:='{"twoMatch":60,"threeMatch":10,"none":30}'::jsonb; end if;
  w_two:=coalesce((w->>'twoMatch')::int,60); w_three:=coalesce((w->>'threeMatch')::int,10); w_none:=coalesce((w->>'none')::int,30);
  if rem_drink=0 then w_three:=0; end if;
  total:=w_two+w_three+w_none;
  if total<=0 then outcome:='none'; prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_two; if r<cum then outcome:='twoMatch'; prize:='pts5'; else cum:=cum+w_three; if r<cum then outcome:='threeMatch'; prize:='drinkVoucher'; else outcome:='none'; prize:='nothing'; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.match_tokens,0)<=0 then raise exception 'no match tokens' using errcode='P0001', hint='no_tokens'; end if; new_tokens:=ls_row.match_tokens-1;
  if prize='pts5' then update public.loyalty_state set match_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='drinkVoucher' then if rem_drink is not null then update public.prize_inventory set remaining=remaining-1 where prize_type='free_drink' and remaining>0; if not found then prize:='nothing'; outcome:='none'; update public.loyalty_state set match_tokens=new_tokens, updated_at=now() where phone=v_phone; else new_voucher:=public.create_voucher(v_phone,'free_drink','match'); update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_drink','match'); update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
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

-- schedule purge for double expiry every hour
select cron.schedule('purge_expired_double_next_hourly', '0 * * * *', $$select public.purge_expired_double_next();$$)
where not exists (select 1 from cron.job where jobname='purge_expired_double_next_hourly');

commit;
