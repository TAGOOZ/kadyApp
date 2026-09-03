-- 0040_game_voucher_ledger_patch.sql — Slice 040 follow-up: game vouchers use ledger with expiry
-- Patches play_spinner/scratch/match (from 0038) to create vouchers via public.create_voucher()
-- so game prizes also get id/expires_at and ledger row, matching card path from 0039.
-- Idempotent: create or replace, safe to re-apply.

begin;

-- Ensure helper exists (from 0039)
create or replace function public.create_voucher(p_phone text, p_type text, p_source text, p_source_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare vid uuid := gen_random_uuid(); exp timestamptz := public.voucher_expires_at(p_type); issued timestamptz := now();
begin
  insert into public.voucher_ledger(id, phone, type, issued_at, expires_at, status, source, source_id)
  values (vid, p_phone, p_type, issued, exp, 'issued', p_source, p_source_id);
  return jsonb_build_object('type', p_type, 'at', to_char(issued at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'id', vid::text, 'expires_at', to_char(exp at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'source', p_source);
end;
$$;

-- Patch play_spinner to use ledger
create or replace function public.play_spinner(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_points5 int; w_points10 int; w_topping int; w_double int; w_nothing int; rem_topping int; total int; cum int; new_voucher jsonb;
begin
  v_phone := public.current_customer_phone(); if v_phone is null then raise exception 'play_spinner: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='spinner' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update;
  w := public.get_spinner_weights(); w_points5:=coalesce((w->>'points5')::int,30); w_points10:=coalesce((w->>'points10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_double:=coalesce((w->>'doubleNext')::int,10); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if;
  total:=w_points5+w_points10+w_topping+w_double+w_nothing;
  if total<=0 then prize:='nothing'; else r:=random()*total; cum:=w_points5; if r<cum then prize:='points5'; else cum:=cum+w_points10; if r<cum then prize:='points10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_double; if r<cum then prize:='doubleNext'; else prize:='nothing'; end if; end if; end if; end if; end if;
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
create or replace function public.play_spinner() returns jsonb language plpgsql security definer set search_path=public as $$ begin return public.play_spinner(null); end; $$; revoke all on function public.play_spinner() from public; grant execute on function public.play_spinner() to authenticated;

create or replace function public.play_scratch(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_pts5 int; w_pts10 int; w_topping int; w_drink int; w_nothing int; rem_topping int; rem_drink int; total int; cum int; new_voucher jsonb;
begin
  v_phone:=public.current_customer_phone(); if v_phone is null then raise exception 'play_scratch: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='scratch' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update; select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='scratch_weights'; if w is null then w:='{"pts5":30,"pts10":25,"toppingVoucher":20,"drinkVoucher":10,"nothing":15}'::jsonb; end if;
  w_pts5:=coalesce((w->>'pts5')::int,30); w_pts10:=coalesce((w->>'pts10')::int,25); w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_drink:=coalesce((w->>'drinkVoucher')::int,10); w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if; if rem_drink=0 then w_drink:=0; end if;
  total:=w_pts5+w_pts10+w_topping+w_drink+w_nothing;
  if total<=0 then prize:='nothing'; else r:=random()*total; cum:=w_pts5; if r<cum then prize:='pts5'; else cum:=cum+w_pts10; if r<cum then prize:='pts10'; else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher'; else cum:=cum+w_drink; if r<cum then prize:='drinkVoucher'; else prize:='nothing'; end if; end if; end if; end if; end if;
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
create or replace function public.play_scratch() returns jsonb language plpgsql security definer set search_path=public as $$ begin return public.play_scratch(null); end; $$; revoke all on function public.play_scratch() from public; grant execute on function public.play_scratch() to authenticated;

create or replace function public.play_match(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_phone text; ls_row public.loyalty_state; r double precision; outcome text; prize text; new_tokens int; existing record; result jsonb; w jsonb; w_two int; w_three int; w_none int; rem_drink int; total int; cum int; new_voucher jsonb;
begin
  v_phone:=public.current_customer_phone(); if v_phone is null then raise exception 'play_match: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then select * into existing from public.game_plays where phone=v_phone and game='match' and idempotency_key=p_idem limit 1; if found then return existing.detail; end if; perform public.check_game_rate_limit(v_phone); else perform public.check_game_rate_limit(v_phone); end if;
  select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='match_weights'; if w is null then w:='{"twoMatch":60,"threeMatch":10,"none":30}'::jsonb; end if;
  w_two:=coalesce((w->>'twoMatch')::int,60); w_three:=coalesce((w->>'threeMatch')::int,10); w_none:=coalesce((w->>'none')::int,30);
  if rem_drink=0 then w_three:=0; end if;
  total:=w_two+w_three+w_none;
  if total<=0 then outcome:='none'; prize:='nothing'; else r:=random()*total; cum:=w_two; if r<cum then outcome:='twoMatch'; prize:='pts5'; else cum:=cum+w_three; if r<cum then outcome:='threeMatch'; prize:='drinkVoucher'; else outcome:='none'; prize:='nothing'; end if; end if; end if;
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
create or replace function public.play_match() returns jsonb language plpgsql security definer set search_path=public as $$ begin return public.play_match(null); end; $$; revoke all on function public.play_match() from public; grant execute on function public.play_match() to authenticated;

commit;
