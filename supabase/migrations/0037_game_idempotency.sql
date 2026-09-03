-- 0037_game_idempotency.sql — Slice 038: idempotent game plays + velocity cap
-- Fixes timeout-loss (critical): play_* now takes p_idem text (client Uuid.v4 per tap)
-- and is idempotent via game_plays unique(phone, game, idempotency_key).
-- Also fixes spam: app_config game_rate_per_min (default 5/min) enforced inside RPC.
-- If same p_idem replayed, returns previous prize without consuming new token.
-- If new p_idem but rate exceeded, raises P0001 hint=rate_limited_games.
-- Backwards compat: p_idem default null → non-idempotent (old clients still work).

begin;

-- ---------------------------------------------------------------------------
-- 1. Idempotency ledger
-- ---------------------------------------------------------------------------
create table if not exists public.game_plays (
  id               uuid primary key default gen_random_uuid(),
  phone            text not null references public.customers(phone) on delete cascade,
  game             text not null check (game in ('spinner','match','scratch')),
  idempotency_key  text,
  prize            text not null,
  detail           jsonb not null default '{}'::jsonb, -- full returned payload
  created_at       timestamptz not null default now()
);

-- Unique only when key is not null (partial unique index)
create unique index if not exists uq_game_plays_idem on public.game_plays(phone, game, idempotency_key) where idempotency_key is not null;
create index if not exists idx_game_plays_phone_created on public.game_plays(phone, created_at desc);
create index if not exists idx_game_plays_phone_game_created on public.game_plays(phone, game, created_at desc);

comment on table public.game_plays is '038 idempotency ledger for play_*; same p_idem returns same prize without new token.';

alter table public.game_plays enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='game_plays' and policyname='gp_select_own') then
    create policy gp_select_own on public.game_plays for select to authenticated
      using (exists (select 1 from public.customers c where c.phone = game_plays.phone and c.google_user_id = auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='game_plays' and policyname='gp_staff_read') then
    create policy gp_staff_read on public.game_plays for select to authenticated
      using (public.has_any_role(array['staff','admin']::text[]));
  end if;
end $$;

-- config for velocity cap
insert into public.app_config(key, value) values ('game_rate_per_min','5'::jsonb) on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Helper: check velocity cap
-- ---------------------------------------------------------------------------
create or replace function public.check_game_rate_limit(p_phone text)
returns void language plpgsql security definer set search_path=public as $$
declare max_per_min int; recent int;
begin
  select value::text::int into max_per_min from public.app_config where key='game_rate_per_min';
  max_per_min := coalesce(max_per_min, 5);
  if max_per_min <= 0 then return; end if;
  select count(*) into recent from public.game_plays
   where phone = p_phone and created_at > now() - interval '1 minute';
  if recent >= max_per_min then
    raise exception 'game rate limited' using errcode='P0001', hint='rate_limited_games';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. play_spinner with p_idem
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
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then
    raise exception 'play_spinner: no customer row' using errcode = '42501';
  end if;

  -- Idempotency: if same p_idem already played, return previous result without new token
  if p_idem is not null and p_idem <> '' then
    select * into existing from public.game_plays
     where phone = v_phone and game='spinner' and idempotency_key = p_idem
     limit 1;
    if found then
      return existing.detail;
    end if;
    -- also check velocity before consuming token (replays bypass cap)
    perform public.check_game_rate_limit(v_phone);
  else
    perform public.check_game_rate_limit(v_phone);
  end if;

  select * into ls_row from public.loyalty_state where phone = v_phone for update;
  if not found then
    raise exception 'loyalty_state not found' using errcode = 'P0001';
  end if;
  if coalesce(ls_row.spinner_tokens,0) <= 0 then
    raise exception 'no spinner tokens' using errcode = 'P0001', hint = 'no_tokens';
  end if;

  new_tokens := ls_row.spinner_tokens - 1;

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

  result := jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);

  -- ledger
  insert into public.game_plays(phone, game, idempotency_key, prize, detail)
  values (v_phone, 'spinner', nullif(p_idem,''), prize, result);

  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'play_spinner', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));

  return result;
end;
$$;

comment on function public.play_spinner(text) is '038: idempotent with p_idem, velocity cap game_rate_per_min.';
revoke all on function public.play_spinner(text) from public;
grant execute on function public.play_spinner(text) to authenticated;
-- keep zero-arg compat shim
create or replace function public.play_spinner()
returns jsonb language plpgsql security definer set search_path=public as $$
begin return public.play_spinner(null); end;
$$;
revoke all on function public.play_spinner() from public;
grant execute on function public.play_spinner() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. play_match with p_idem
-- ---------------------------------------------------------------------------
create or replace function public.play_match(p_idem text default null)
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
  existing record;
  result jsonb;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_match: no customer row' using errcode='42501'; end if;

  if p_idem is not null and p_idem <> '' then
    select * into existing from public.game_plays where phone=v_phone and game='match' and idempotency_key=p_idem limit 1;
    if found then return existing.detail; end if;
    perform public.check_game_rate_limit(v_phone);
  else
    perform public.check_game_rate_limit(v_phone);
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.match_tokens,0) <=0 then raise exception 'no match tokens' using errcode='P0001', hint='no_tokens'; end if;

  new_tokens := ls_row.match_tokens -1;

  r := random()*100;
  if r < 60 then outcome := 'twoMatch';
  elsif r < 70 then outcome := 'threeMatch';
  else outcome := 'none';
  end if;

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

  result := jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail)
  values (v_phone, 'match', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'play_match', v_phone, jsonb_build_object('outcome', outcome, 'prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));
  return result;
end;
$$;

comment on function public.play_match(text) is '038: idempotent match';
revoke all on function public.play_match(text) from public;
grant execute on function public.play_match(text) to authenticated;
create or replace function public.play_match()
returns jsonb language plpgsql security definer set search_path=public as $$
begin return public.play_match(null); end;
$$;
revoke all on function public.play_match() from public;
grant execute on function public.play_match() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. play_scratch with p_idem
-- ---------------------------------------------------------------------------
create or replace function public.play_scratch(p_idem text default null)
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
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'play_scratch: no customer row' using errcode='42501'; end if;

  if p_idem is not null and p_idem <> '' then
    select * into existing from public.game_plays where phone=v_phone and game='scratch' and idempotency_key=p_idem limit 1;
    if found then return existing.detail; end if;
    perform public.check_game_rate_limit(v_phone);
  else
    perform public.check_game_rate_limit(v_phone);
  end if;

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

  result := jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens);
  insert into public.game_plays(phone, game, idempotency_key, prize, detail)
  values (v_phone, 'scratch', nullif(p_idem,''), prize, result);
  insert into public.staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'play_scratch', v_phone, jsonb_build_object('prize', prize, 'remaining_tokens', new_tokens, 'idem', p_idem));
  return result;
end;
$$;

comment on function public.play_scratch(text) is '038: idempotent scratch';
revoke all on function public.play_scratch(text) from public;
grant execute on function public.play_scratch(text) to authenticated;
create or replace function public.play_scratch()
returns jsonb language plpgsql security definer set search_path=public as $$
begin return public.play_scratch(null); end;
$$;
revoke all on function public.play_scratch() from public;
grant execute on function public.play_scratch() to authenticated;

commit;
