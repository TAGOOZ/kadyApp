-- 0035_game_server_authority.sql — SECURITY-02 mirror 0004 pattern for games
-- Fixes client-optimistic gap: spinner/match/scratch were local-only (no server persist)
-- so thief could chrome-devtools_evaluate_script loyaltyController memory 0→999
-- and bypass flt-semantics disabled via DOM, getting free prizes without 3 stamps.
-- Also fixes persist_loyalty_state arbitrary write (attacker could POST rpc with points 9999).
--
-- Mirrors 0004_loyalty_server.sql: token consumption is SECURITY DEFINER,
-- CHECK spinner_tokens>0 + INSERT vouchers server side, RLS deny client PATCH.
-- After this, loyalty_state is only writable via triggers or these RPCs.
-- Client is read-only projection via watchState/refreshFor.

begin;

-- ---------------------------------------------------------------------------
-- 1. Revoke arbitrary loyalty_state writes (persist_loyalty_state/grant_points)
-- ---------------------------------------------------------------------------
-- Customers must not be able to set arbitrary points/vouchers/tokens.
-- Keep a staff-only variant for manual rewards (customer_lookup).
do $$
begin
  -- revoke old grants if they exist
  begin
    revoke all on function public.persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) from public, authenticated, anon;
  exception when others then null;
  end;
  begin
    revoke all on function public.grant_loyalty_points(text,int) from public, authenticated, anon;
  exception when others then null;
  end;
end $$;

-- Drop old arbitrary functions (replaced by staff-only)
drop function if exists public.persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb);
drop function if exists public.grant_loyalty_points(text,int);

-- Staff-only persist for manual rewards (mirrors old persist but requires staff/admin role)
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

comment on function public.staff_persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) is 'SECURITY-02 staff-only persist — replaces arbitrary customer persist_loyalty_state. Game tokens now via play_* RPCs.';

revoke all on function public.staff_persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) from public;
grant execute on function public.staff_persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) to authenticated;

-- Ensure no direct UPDATE policy remains for customers (already revoked in 0015). Re-assert.
drop policy if exists loyalty_update_own on public.loyalty_state;
-- Staff/Admin need direct UPDATE for manual rewards (customer_lookup) — restore limited policy
do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='loyalty_state'
       and policyname='loyalty_staff_admin_update'
  ) then
    create policy loyalty_staff_admin_update on public.loyalty_state
      for update to authenticated
      using (public.has_any_role(array['staff','admin']::text[]))
      with check (public.has_any_role(array['staff','admin']::text[]));
  end if;
end $$;
-- No UPDATE policy for customers; loyalty_state is only writable via
-- SECURITY DEFINER play_* RPCs (customers) or staff policy (staff/admin).
-- Select policies remain (loyalty_select_own, loyalty_staff_admin_read).

-- ---------------------------------------------------------------------------
-- 2. Helper: resolve phone for current auth user
-- ---------------------------------------------------------------------------
create or replace function public.current_customer_phone()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select phone from public.customers where google_user_id = auth.uid() limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 3. Game RPCs — SECURITY DEFINER, ownership via auth.uid(), token check >0
-- ---------------------------------------------------------------------------

-- 3a. play_spinner — consumes 1 spinner_token, rolls weighted prize server side
create or replace function public.play_spinner()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  r double precision;
  prize text;
  new_tokens int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then
    raise exception 'play_spinner: no customer row' using errcode = '42501';
  end if;

  select * into ls_row from public.loyalty_state where phone = v_phone for update;
  if not found then
    raise exception 'loyalty_state not found' using errcode = 'P0001';
  end if;
  if coalesce(ls_row.spinner_tokens,0) <= 0 then
    raise exception 'no spinner tokens' using errcode = 'P0001', hint = 'no_tokens';
  end if;

  new_tokens := ls_row.spinner_tokens - 1;

  -- Weighted roll: points5 30 | points10 25 | toppingVoucher 20 | doubleNext 10 | nothing 15
  r := random()*100;
  if r < 30 then prize := 'points5';
  elsif r < 55 then prize := 'points10';
  elsif r < 75 then prize := 'toppingVoucher';
  elsif r < 85 then prize := 'doubleNext';
  else prize := 'nothing';
  end if;

  if prize = 'points5' then
    update public.loyalty_state set spinner_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize = 'points10' then
    update public.loyalty_state set spinner_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize = 'toppingVoucher' then
    update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('type','free_topping','at', public.now_utc_iso())), updated_at=now() where phone=v_phone;
  elsif prize = 'doubleNext' then
    update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, updated_at=now() where phone=v_phone;
  else
    update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone;
  end if;

  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'play_spinner', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens));

  return jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
end;
$$;

comment on function public.play_spinner() is 'SECURITY-02: consumes 1 spinner_token (CHECK >0) and grants weighted prize server side. Mirrors 0004 apply_stamps pattern.';

revoke all on function public.play_spinner() from public;
grant execute on function public.play_spinner() to authenticated;

-- 3b. play_match — consumes 1 match_token, rolls MatchOutcome 60/10/30
create or replace function public.play_match()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  r double precision;
  outcome text;
  prize text;
  new_tokens int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_match: no customer row' using errcode='42501'; end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.match_tokens,0) <=0 then raise exception 'no match tokens' using errcode='P0001', hint='no_tokens'; end if;

  new_tokens := ls_row.match_tokens -1;

  r := random()*100;
  if r < 60 then outcome := 'twoMatch';
  elsif r < 70 then outcome := 'threeMatch';
  else outcome := 'none';
  end if;

  -- Map outcome to GamePrize vocabulary
  if outcome='twoMatch' then prize := 'pts5';
  elsif outcome='threeMatch' then prize := 'drinkVoucher';
  else prize := 'nothing';
  end if;

  if prize='pts5' then
    update public.loyalty_state set match_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='drinkVoucher' then
    update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('type','free_drink','at', public.now_utc_iso())), updated_at=now() where phone=v_phone;
  else
    update public.loyalty_state set match_tokens=new_tokens, updated_at=now() where phone=v_phone;
  end if;

  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'play_match', v_phone, jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens));

  return jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens);
end;
$$;

comment on function public.play_match() is 'SECURITY-02: consumes 1 match_token (CHECK >0) and grants weighted prize server side (twoMatch 60%→5pts, threeMatch 10%→drink).';

revoke all on function public.play_match() from public;
grant execute on function public.play_match() to authenticated;

-- 3c. play_scratch — consumes 1 scratch_token, rolls GamePrize 30/25/20/10/15
create or replace function public.play_scratch()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  r double precision;
  prize text;
  new_tokens int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_scratch: no customer row' using errcode='42501'; end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.scratch_tokens,0) <=0 then raise exception 'no scratch tokens' using errcode='P0001', hint='no_tokens'; end if;

  new_tokens := ls_row.scratch_tokens -1;

  r := random()*100;
  if r < 30 then prize := 'pts5';
  elsif r < 55 then prize := 'pts10';
  elsif r < 75 then prize := 'toppingVoucher';
  elsif r < 85 then prize := 'drinkVoucher';
  else prize := 'nothing';
  end if;

  if prize='pts5' then
    update public.loyalty_state set scratch_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='pts10' then
    update public.loyalty_state set scratch_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then
    update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('type','free_topping','at', public.now_utc_iso())), updated_at=now() where phone=v_phone;
  elsif prize='drinkVoucher' then
    update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('type','free_drink','at', public.now_utc_iso())), updated_at=now() where phone=v_phone;
  else
    update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone;
  end if;

  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'play_scratch', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens));

  return jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
end;
$$;

comment on function public.play_scratch() is 'SECURITY-02: consumes 1 scratch_token (CHECK >0) and grants weighted prize server side.';

revoke all on function public.play_scratch() from public;
grant execute on function public.play_scratch() to authenticated;

-- 3d. Simple consume RPCs for legacy callers (now server-authoritative) — kept for backwards compat and direct tests
create or replace function public.consume_spinner_token()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_phone text; ls_row public.loyalty_state;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'no customer' using errcode='42501'; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then return false; end if;
  if coalesce(ls_row.spinner_tokens,0) <=0 then raise exception 'no spinner tokens' using errcode='P0001', hint='no_tokens'; end if;
  update public.loyalty_state set spinner_tokens=spinner_tokens-1, updated_at=now() where phone=v_phone;
  return true;
end;
$$;
revoke all on function public.consume_spinner_token() from public;
grant execute on function public.consume_spinner_token() to authenticated;

create or replace function public.consume_match_token()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_phone text; ls_row public.loyalty_state;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'no customer' using errcode='42501'; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then return false; end if;
  if coalesce(ls_row.match_tokens,0) <=0 then raise exception 'no match tokens' using errcode='P0001', hint='no_tokens'; end if;
  update public.loyalty_state set match_tokens=match_tokens-1, updated_at=now() where phone=v_phone;
  return true;
end;
$$;
revoke all on function public.consume_match_token() from public;
grant execute on function public.consume_match_token() to authenticated;

create or replace function public.consume_scratch_token()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_phone text; ls_row public.loyalty_state;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'no customer' using errcode='42501'; end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then return false; end if;
  if coalesce(ls_row.scratch_tokens,0) <=0 then raise exception 'no scratch tokens' using errcode='P0001', hint='no_tokens'; end if;
  update public.loyalty_state set scratch_tokens=scratch_tokens-1, updated_at=now() where phone=v_phone;
  return true;
end;
$$;
revoke all on function public.consume_scratch_token() from public;
grant execute on function public.consume_scratch_token() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Voucher single-use consumption (fixes replay)
-- ---------------------------------------------------------------------------
create or replace function public.consume_voucher(p_type text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  vouchers jsonb;
  new_vouchers jsonb := '[]'::jsonb;
  found bool := false;
  elem jsonb;
begin
  if p_type not in ('free_drink','free_topping','free_snack') then
    raise exception 'invalid voucher type %', p_type using errcode='P0001';
  end if;
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'no customer' using errcode='42501'; end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then return false; end if;
  vouchers := coalesce(ls_row.vouchers,'[]'::jsonb);

  -- Remove first matching voucher atomically
  for elem in select * from jsonb_array_elements(vouchers)
  loop
    if not found and (elem->>'type') = p_type then
      found := true;
      continue;
    end if;
    new_vouchers := new_vouchers || jsonb_build_array(elem);
  end loop;

  if not found then return false; end if;

  update public.loyalty_state set vouchers=new_vouchers, updated_at=now() where phone=v_phone;

  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'consume_voucher', v_phone, jsonb_build_object('type', p_type));

  return true;
end;
$$;

comment on function public.consume_voucher(text) is 'SECURITY-02: atomically consumes one voucher of given type (FOR UPDATE) — prevents replay.';

revoke all on function public.consume_voucher(text) from public;
grant execute on function public.consume_voucher(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Defensive trigger: block any non-security-definer direct UPDATE to loyalty_state
--    that tries to escalate points/vouchers without via play_* (in case RLS policy is re-added)
-- ---------------------------------------------------------------------------
create or replace function public.guard_loyalty_direct_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Allow updates from SECURITY DEFINER functions (they run as owner, not authenticated)
  -- current_user will be postgres/supabase_admin for definer, not 'authenticated'
  -- Staff/Admin are allowed via RLS policy above; only block authenticated customers.
  if (current_user = 'authenticated' or current_user = 'anon')
     and not public.has_any_role(array['staff','admin']::text[]) then
    raise exception 'loyalty_state: direct UPDATE blocked — use play_* RPCs' using errcode='42501';
  end if;
  return new;
end;
$$;

-- Only attach if not already? Use BEFORE UPDATE guard
drop trigger if exists trg_guard_loyalty_direct_update on public.loyalty_state;
create trigger trg_guard_loyalty_direct_update
  before update on public.loyalty_state
  for each row
  when (current_user in ('authenticated','anon'))
  execute function public.guard_loyalty_direct_update();

commit;
