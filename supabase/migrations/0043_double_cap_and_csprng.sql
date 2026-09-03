begin;

-- 0043: Enforce double cap in loyalty credit + CSPRNG hardening for games

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
comment on function public.capped_earned(int, boolean, boolean) is 'FIX #2: capped double — extra points limited to double_max_extra (default 10)';

create or replace function public.secure_random_100()
returns double precision language plpgsql volatile security definer set search_path=public, pg_temp, extensions as $$
declare
  b bytea;
  v bigint;
begin
  begin
    b := extensions.gen_random_bytes(4);
    v := (get_byte(b,0)::bigint << 24) | (get_byte(b,1)::bigint << 16) | (get_byte(b,2)::bigint << 8) | get_byte(b,3)::bigint;
    return (v::double precision / 4294967296.0) * 100.0;
  exception when others then
    return random()*100;
  end;
end;
$$;
comment on function public.secure_random_100() is 'FIX #7: CSPRNG via gen_random_bytes fallback to random()';

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
  dbl := ls_row.double_next_order
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
  update loyalty_state l set points=greatest(l.points+earned-redeemed,0), lifetime_points=l.lifetime_points+earned, stamps=(ls->>'stamps')::int, completed_cards=(ls->>'completed_cards')::int, spinner_tokens=(ls->>'spinner_tokens')::int, double_next_order=false, vouchers=coalesce(ls->'vouchers','[]'::jsonb), processed_orders=(select jsonb_agg(elem order by ord) from (select elem, ord from jsonb_array_elements(jsonb_build_array(new.id::text)||l.processed_orders) with ordinality as t(elem,ord) where ord<=100) s), updated_at=now() where l.phone=ls_row.phone;
  insert into public.order_loyalty_effects(order_id, phone, google_user_id, earned, stamp_granted, stamp_before, stamp_after, token_granted, token_position, voucher_granted_type, voucher_at, completed_card_granted, redeemed_deducted, is_reversed) values (new.id, ls_row.phone, new.google_user_id, earned, stamp_granted, stamp_before, stamp_after, token_granted, case when token_granted then stamp_after else null end, voucher_type, voucher_at, card_granted, redeemed, false) on conflict (order_id) do nothing;
  insert into order_events(order_id, status, actor, at) values (new.id,'new','system:loyalty',now());
  return new;
end;
$$;

create or replace function public.play_spinner(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_points5 int; w_points10 int; w_topping int; w_double int; w_nothing int; rem_topping int; total int; cum int; new_voucher jsonb;
begin
  v_phone := public.current_customer_phone(); if v_phone is null then raise exception 'play_spinner: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='spinner' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update;
  w := public.get_spinner_weights(); w_points5:=coalesce((w->>'points5')::int,30); w_points10:=coalesce((w->>'points10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_double:=coalesce((w->>'doubleNext')::int,10); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if;
  total:=w_points5+w_points10+w_topping+w_double+w_nothing;
  if total<=0 then prize:='nothing'; else r:=public.secure_random_100()/100*total; cum:=w_points5; if r<cum then prize:='points5'; else cum:=cum+w_points10; if r<cum then prize:='points10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_double; if r<cum then prize:='doubleNext'; else prize:='nothing'; end if; end if; end if; end if; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update; if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if; if coalesce(ls_row.spinner_tokens,0)<=0 then raise exception 'no spinner tokens' using errcode='P0001', hint='no_tokens'; end if; new_tokens:=ls_row.spinner_tokens-1;
  if prize='points5' then update public.loyalty_state set spinner_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='points10' then update public.loyalty_state set spinner_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then if rem_topping is not null then update public.prize_inventory set remaining=remaining-1, updated_at=now() where prize_type='free_topping' and remaining>0; if not found then prize:='nothing'; update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone; else new_voucher:=public.create_voucher(v_phone,'free_topping','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if; else new_voucher:=public.create_voucher(v_phone,'free_topping','spinner'); update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(new_voucher), updated_at=now() where phone=v_phone; end if;
  elsif prize='doubleNext' then update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, updated_at=now() where phone=v_phone;
  else update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;
  result:=jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_spinner', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem, 'cap_remaining_topping', rem_topping));
  return result;
end;
$$;
revoke all on function public.play_spinner(text) from public; grant execute on function public.play_spinner(text) to authenticated;
create or replace function public.play_spinner() returns jsonb language plpgsql security definer set search_path=public, pg_temp, extensions as $$ begin return public.play_spinner(null); end; $$;
revoke all on function public.play_spinner() from public; grant execute on function public.play_spinner() to authenticated;

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

revoke all on function public.secure_random_100() from public;
grant execute on function public.secure_random_100() to authenticated;

commit;
