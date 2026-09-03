-- 0038_prize_inventory.sql — Slice 039: hard caps + admin-editable weights
-- Implements:
--   * prize_inventory hard caps for voucher prizes (free_topping, free_drink)
--     with remaining decremented atomically FOR UPDATE, checked before roll.
--   * app_config prize weights: spinner_weights, scratch_weights, match_weights
--     admin-editable JSON without deploy; play_* reads with fallback to 30/25/20/10/15.
--   * When a voucher cap reaches 0, its weight is zeroed and remaining pool
--     renormalized (preserves configured ratios for available prizes).
--   * Atomic decrement only if prize selected and cap exists; unlimited if no row.
--   * Audit via staff_log + prize_inventory remaining.

begin;

-- ---------------------------------------------------------------------------
-- 1. Inventory table
-- ---------------------------------------------------------------------------
create table if not exists public.prize_inventory (
  prize_type text primary key check (prize_type in ('free_topping','free_drink','free_snack','double_next')),
  max_units int not null check (max_units >= 0),
  remaining int not null check (remaining >= 0),
  check (remaining <= max_units),
  updated_at timestamptz not null default now()
);

comment on table public.prize_inventory is '039 hard caps for game voucher prizes; no row => unlimited; remaining decremented FOR UPDATE.';

create index if not exists idx_prize_inventory_remaining on public.prize_inventory(remaining);

alter table public.prize_inventory enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='prize_inventory' and policyname='pi_select_own') then
    create policy pi_select_own on public.prize_inventory for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='prize_inventory' and policyname='pi_admin_write') then
    create policy pi_admin_write on public.prize_inventory for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
end $$;

-- trigger for updated_at
create or replace function public.set_prize_inventory_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;
drop trigger if exists trg_prize_inventory_updated_at on public.prize_inventory;
create trigger trg_prize_inventory_updated_at before update on public.prize_inventory
  for each row execute function public.set_prize_inventory_updated_at();

-- seed unlimited by default (no rows) — optionally seed with high caps for visibility
-- Uncomment if you want explicit rows:
-- insert into public.prize_inventory(prize_type, max_units, remaining) values
--   ('free_topping', 100, 100), ('free_drink', 100, 100)
-- on conflict (prize_type) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Weight config defaults (admin-editable)
-- ---------------------------------------------------------------------------
insert into public.app_config(key, value) values
  ('spinner_weights', '{"points5":30,"points10":25,"toppingVoucher":20,"doubleNext":10,"nothing":15}'::jsonb),
  ('scratch_weights', '{"pts5":30,"pts10":25,"toppingVoucher":20,"drinkVoucher":10,"nothing":15}'::jsonb),
  ('match_weights', '{"twoMatch":60,"threeMatch":10,"none":30}'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Helper: read weight with fallback
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

-- ---------------------------------------------------------------------------
-- 4. Patch play_spinner to respect caps + weights
-- ---------------------------------------------------------------------------
create or replace function public.play_spinner(p_idem text default null)
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
  existing record;
  result jsonb;
  -- weights
  w jsonb;
  w_points5 int; w_points10 int; w_topping int; w_double int; w_nothing int;
  rem_topping int;
  total int;
  cum int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_spinner: no customer row' using errcode='42501'; end if;

  if p_idem is not null and p_idem <> '' then
    select * into existing from public.game_plays where phone=v_phone and game='spinner' and idempotency_key=p_idem limit 1;
    if found then return existing.detail; end if;
    perform public.check_game_rate_limit(v_phone);
  else
    perform public.check_game_rate_limit(v_phone);
  end if;

  -- lock inventory before roll so weight zeroing is consistent
  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update;
  -- no row => unlimited (null stays)

  -- load weights
  w := public.get_spinner_weights();
  w_points5 := coalesce((w->>'points5')::int, 30);
  w_points10 := coalesce((w->>'points10')::int, 25);
  w_topping := coalesce((w->>'toppingVoucher')::int, 20);
  w_double := coalesce((w->>'doubleNext')::int, 10);
  w_nothing := coalesce((w->>'nothing')::int, 15);
  if rem_topping = 0 then w_topping := 0; end if;

  total := w_points5 + w_points10 + w_topping + w_double + w_nothing;
  if total <= 0 then
    -- all caps exhausted, fallback to nothing
    prize := 'nothing';
  else
    r := random()*total;
    cum := w_points5;
    if r < cum then prize := 'points5';
    else cum := cum + w_points10; if r < cum then prize := 'points10';
    else cum := cum + w_topping; if r < cum then prize := 'toppingVoucher';
    else cum := cum + w_double; if r < cum then prize := 'doubleNext';
    else prize := 'nothing';
    end if;
    end if;
    end if;
    end if;
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.spinner_tokens,0) <=0 then raise exception 'no spinner tokens' using errcode='P0001', hint='no_tokens'; end if;
  new_tokens := ls_row.spinner_tokens -1;

  if prize='points5' then
    update public.loyalty_state set spinner_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='points10' then
    update public.loyalty_state set spinner_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then
    -- atomic decrement cap (already locked, but double-check remaining >0)
    if rem_topping is not null then
      update public.prize_inventory set remaining = remaining -1, updated_at=now() where prize_type='free_topping' and remaining >0;
      if not found then
        -- raced to 0 between lock and update? fallback to nothing (refund token? For now grant nothing)
        -- Since we locked, this should not happen; but if it does, treat as nothing
        prize := 'nothing';
        update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone;
      else
        update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('type','free_topping','at', public.now_utc_iso())), updated_at=now() where phone=v_phone;
      end if;
    else
      update public.loyalty_state set spinner_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('type','free_topping','at', public.now_utc_iso())), updated_at=now() where phone=v_phone;
    end if;
  elsif prize='doubleNext' then
    update public.loyalty_state set spinner_tokens=new_tokens, double_next_order=true, updated_at=now() where phone=v_phone;
  else
    update public.loyalty_state set spinner_tokens=new_tokens, updated_at=now() where phone=v_phone;
  end if;

  result := jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'spinner', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_spinner', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem, 'cap_remaining_topping', rem_topping));
  return result;
end;
$$;

comment on function public.play_spinner(text) is '039: caps + weights, idempotent, velocity cap.';
revoke all on function public.play_spinner(text) from public; grant execute on function public.play_spinner(text) to authenticated;
create or replace function public.play_spinner() returns jsonb language plpgsql security definer set search_path=public as $$ begin return public.play_spinner(null); end; $$;
revoke all on function public.play_spinner() from public; grant execute on function public.play_spinner() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Patch play_scratch similarly (topping + drink caps)
-- ---------------------------------------------------------------------------
create or replace function public.play_scratch(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_phone text; ls_row public.loyalty_state; r double precision; prize text; new_tokens int; existing record; result jsonb;
  w jsonb; w_pts5 int; w_pts10 int; w_topping int; w_drink int; w_nothing int;
  rem_topping int; rem_drink int; total int; cum int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_scratch: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then
    select * into existing from public.game_plays where phone=v_phone and game='scratch' and idempotency_key=p_idem limit 1;
    if found then return existing.detail; end if;
    perform public.check_game_rate_limit(v_phone);
  else perform public.check_game_rate_limit(v_phone); end if;

  select remaining into rem_topping from public.prize_inventory where prize_type='free_topping' for update;
  select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;

  select value into w from public.app_config where key='scratch_weights';
  if w is null then w := '{"pts5":30,"pts10":25,"toppingVoucher":20,"drinkVoucher":10,"nothing":15}'::jsonb; end if;
  w_pts5 := coalesce((w->>'pts5')::int,30); w_pts10:=coalesce((w->>'pts10')::int,25);
  w_topping:=coalesce((w->>'toppingVoucher')::int,20); w_drink:=coalesce((w->>'drinkVoucher')::int,10);
  w_nothing:=coalesce((w->>'nothing')::int,15);
  if rem_topping=0 then w_topping:=0; end if;
  if rem_drink=0 then w_drink:=0; end if;
  total:=w_pts5+w_pts10+w_topping+w_drink+w_nothing;
  if total<=0 then prize:='nothing';
  else r:=random()*total; cum:=w_pts5; if r<cum then prize:='pts5';
    else cum:=cum+w_pts10; if r<cum then prize:='pts10';
    else cum:=cum+w_topping; if r<cum then prize:='toppingVoucher';
    else cum:=cum+w_drink; if r<cum then prize:='drinkVoucher';
    else prize:='nothing'; end if; end if; end if; end if;
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.scratch_tokens,0)<=0 then raise exception 'no scratch tokens' using errcode='P0001', hint='no_tokens'; end if;
  new_tokens:=ls_row.scratch_tokens-1;

  if prize='pts5' then update public.loyalty_state set scratch_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='pts10' then update public.loyalty_state set scratch_tokens=new_tokens, points=points+10, lifetime_points=lifetime_points+10, updated_at=now() where phone=v_phone;
  elsif prize='toppingVoucher' then
    if rem_topping is not null then
      update public.prize_inventory set remaining=remaining-1 where prize_type='free_topping' and remaining>0;
      if not found then prize:='nothing'; update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone;
      else update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','free_topping','at',public.now_utc_iso())), updated_at=now() where phone=v_phone; end if;
    else update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','free_topping','at',public.now_utc_iso())), updated_at=now() where phone=v_phone; end if;
  elsif prize='drinkVoucher' then
    if rem_drink is not null then
      update public.prize_inventory set remaining=remaining-1 where prize_type='free_drink' and remaining>0;
      if not found then prize:='nothing'; update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone;
      else update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','free_drink','at',public.now_utc_iso())), updated_at=now() where phone=v_phone; end if;
    else update public.loyalty_state set scratch_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','free_drink','at',public.now_utc_iso())), updated_at=now() where phone=v_phone; end if;
  else update public.loyalty_state set scratch_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;

  result:=jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'scratch', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_scratch', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));
  return result;
end;
$$;

comment on function public.play_scratch(text) is '039: caps + weights';
revoke all on function public.play_scratch(text) from public; grant execute on function public.play_scratch(text) to authenticated;
create or replace function public.play_scratch() returns jsonb language plpgsql security definer set search_path=public as $$ begin return public.play_scratch(null); end; $$;
revoke all on function public.play_scratch() from public; grant execute on function public.play_scratch() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Patch play_match (drink cap only)
-- ---------------------------------------------------------------------------
create or replace function public.play_match(p_idem text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_phone text; ls_row public.loyalty_state; r double precision; outcome text; prize text; new_tokens int; existing record; result jsonb;
  w jsonb; w_two int; w_three int; w_none int; rem_drink int; total int; cum int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_match: no customer row' using errcode='42501'; end if;
  if p_idem is not null and p_idem <> '' then
    select * into existing from public.game_plays where phone=v_phone and game='match' and idempotency_key=p_idem limit 1;
    if found then return existing.detail; end if;
    perform public.check_game_rate_limit(v_phone);
  else perform public.check_game_rate_limit(v_phone); end if;

  select remaining into rem_drink from public.prize_inventory where prize_type='free_drink' for update;
  select value into w from public.app_config where key='match_weights';
  if w is null then w:='{"twoMatch":60,"threeMatch":10,"none":30}'::jsonb; end if;
  w_two:=coalesce((w->>'twoMatch')::int,60); w_three:=coalesce((w->>'threeMatch')::int,10); w_none:=coalesce((w->>'none')::int,30);
  if rem_drink=0 then w_three:=0; end if;
  total:=w_two+w_three+w_none;
  if total<=0 then outcome:='none'; prize:='nothing';
  else r:=random()*total; cum:=w_two; if r<cum then outcome:='twoMatch'; prize:='pts5';
    else cum:=cum+w_three; if r<cum then outcome:='threeMatch'; prize:='drinkVoucher';
    else outcome:='none'; prize:='nothing'; end if; end if;
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.match_tokens,0)<=0 then raise exception 'no match tokens' using errcode='P0001', hint='no_tokens'; end if;
  new_tokens:=ls_row.match_tokens-1;

  if prize='pts5' then update public.loyalty_state set match_tokens=new_tokens, points=points+5, lifetime_points=lifetime_points+5, updated_at=now() where phone=v_phone;
  elsif prize='drinkVoucher' then
    if rem_drink is not null then
      update public.prize_inventory set remaining=remaining-1 where prize_type='free_drink' and remaining>0;
      if not found then prize:='nothing'; outcome:='none'; update public.loyalty_state set match_tokens=new_tokens, updated_at=now() where phone=v_phone;
      else update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','free_drink','at',public.now_utc_iso())), updated_at=now() where phone=v_phone; end if;
    else update public.loyalty_state set match_tokens=new_tokens, vouchers=coalesce(vouchers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','free_drink','at',public.now_utc_iso())), updated_at=now() where phone=v_phone; end if;
  else update public.loyalty_state set match_tokens=new_tokens, updated_at=now() where phone=v_phone; end if;

  result:=jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail) values (v_phone,'match', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text,'play_match', v_phone, jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));
  return result;
end;
$$;

comment on function public.play_match(text) is '039: caps + weights';
revoke all on function public.play_match(text) from public; grant execute on function public.play_match(text) to authenticated;
create or replace function public.play_match() returns jsonb language plpgsql security definer set search_path=public as $$ begin return public.play_match(null); end; $$;
revoke all on function public.play_match() from public; grant execute on function public.play_match() to authenticated;

-- Helper for admin replenish (optional RPC) — but direct table update via RLS also works
create or replace function public.admin_replenish_prize(p_prize text, p_add int)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  if p_prize not in ('free_topping','free_drink','free_snack','double_next') then raise exception 'invalid prize %', p_prize using errcode='P0001'; end if;
  if p_add is null or p_add <=0 then raise exception 'p_add must be >0' using errcode='P0001'; end if;
  insert into public.prize_inventory(prize_type, max_units, remaining) values (p_prize, p_add, p_add)
    on conflict (prize_type) do update set max_units = prize_inventory.max_units + p_add, remaining = prize_inventory.remaining + p_add, updated_at=now();
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text, 'admin_replenish_prize', null, jsonb_build_object('prize', p_prize, 'add', p_add));
end;
$$;
revoke all on function public.admin_replenish_prize(text,int) from public; grant execute on function public.admin_replenish_prize(text,int) to authenticated;

commit;
