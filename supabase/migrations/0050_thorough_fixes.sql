begin;

-- 0050_thorough_fixes.sql — thorough (not painkiller) fixes for remaining audit gaps
-- * device farm gate for free token (per-device limit) + order rate limit advisory lock
-- * search_path hardening for pure helpers
-- * voucher jsonb INSERT guard
-- * quest token grant RPC (server-authoritative, not local)
-- * order rate limit lock

-- ---------------------------------------------------------------------------
-- 1) Hardened pure helpers — set search_path explicitly
-- ---------------------------------------------------------------------------
create or replace function public.round_half_up(n numeric)
returns int language sql immutable set search_path=public, pg_temp as $$
  select floor(n + 0.5)::int;
$$;

create or replace function public.now_utc_iso()
returns text language sql stable set search_path=public, pg_temp as $$
  select to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
$$;

-- ---------------------------------------------------------------------------
-- 2) Order rate limit — advisory lock per phone (prevents concurrent bypass)
-- ---------------------------------------------------------------------------
create or replace function public.enforce_order_rate_limit()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  max_n int;
  win_min int;
  recent int;
begin
  perform pg_advisory_xact_lock(hashtext(new.phone));
  select value::text::int into max_n   from app_config where key = 'rate_limit_max';
  select value::text::int into win_min from app_config where key = 'rate_limit_window_min';
  if coalesce(max_n, 5) > 0 then
    select count(*) into recent
      from orders o
     where o.phone = new.phone
       and o.created_at > now() - make_interval(mins => coalesce(win_min, 5));
    if recent >= coalesce(max_n, 5) then
      raise exception 'orders: rate limited'
        using errcode = 'P0001', hint = 'too_many_orders';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Device farm gate — per-device free token limit (3 phones per device per 30d)
-- ---------------------------------------------------------------------------
-- Add device_id to free_token_claims for per-device tracking (nullable for back-compat)
alter table public.free_token_claims add column if not exists device_id text;

create index if not exists idx_free_token_device on public.free_token_claims(device_id, claimed_at) where device_id is not null;

-- Harden request_free_token to take device_id and enforce per-device cap
create or replace function public.request_free_token(p_device_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  recent_phone int;
  recent_device int;
  device_phone_count int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then
    raise exception 'request_free_token: no customer row' using errcode='42501';
  end if;

  -- per-phone 7d limit (existing)
  select count(*) into recent_phone from public.free_token_claims
   where phone = v_phone and claimed_at > now() - interval '7 days';
  if recent_phone >= 1 then
    raise exception 'free token rate limited — try again after 7 days' using errcode='P0001', hint='free_token_rate_limited';
  end if;

  -- per-device 30d limit: max 3 distinct phones per device per 30 days (family sharing: 3 ok, farm >3 blocked)
  if p_device_id is not null and p_device_id <> '' then
    select count(*) into recent_device from public.free_token_claims
     where device_id = p_device_id and claimed_at > now() - interval '30 days';
    if recent_device >= 3 then
      raise exception 'free token per-device limit reached (3 per 30 days)' using errcode='P0001', hint='device_rate_limited';
    end if;
    -- also check customer_devices distinct phones per device (existing signal)
    select count(distinct phone) into device_phone_count from public.customer_devices where device_id = p_device_id;
    if device_phone_count >= 5 then
      -- soft signal: device already linked to 5+ phones -> likely farm, block free token
      raise exception 'device flagged for multiple accounts' using errcode='P0001', hint='device_flagged';
    end if;
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.spinner_tokens,0) >= 5 then
    raise exception 'token cap reached (5)' using errcode='P0001', hint='token_cap';
  end if;

  update public.loyalty_state set spinner_tokens = spinner_tokens + 1, updated_at=now() where phone=v_phone;
  perform public.create_token(v_phone, 'spinner', 'free');
  insert into public.free_token_claims(phone, device_id) values (v_phone, nullif(p_device_id,''));
  -- also upsert customer_devices for farm signal
  if p_device_id is not null and p_device_id <> '' then
    insert into public.customer_devices(phone, device_id) values (v_phone, p_device_id) on conflict (phone, device_id) do update set last_seen_at=now();
  end if;
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text, 'request_free_token', v_phone, jsonb_build_object('granted',1, 'device', p_device_id));
  return jsonb_build_object('spinner_tokens', ls_row.spinner_tokens+1, 'phone', v_phone);
end;
$$;
comment on function public.request_free_token(text) is '0050 thorough: per-phone 7d + per-device 3/30d + device flagged 5+ phones.';
revoke all on function public.request_free_token(text) from public; grant execute on function public.request_free_token(text) to authenticated;
-- keep zero-arg compat shim
create or replace function public.request_free_token()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
begin return public.request_free_token(null); end;
$$;
revoke all on function public.request_free_token() from public; grant execute on function public.request_free_token() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Voucher consistency — also on INSERT
-- ---------------------------------------------------------------------------
drop trigger if exists trg_guard_voucher_jsonb_ins on public.loyalty_state;
create trigger trg_guard_voucher_jsonb_ins before insert on public.loyalty_state for each row execute function public.guard_voucher_jsonb_consistency();
-- guard already exists for UPDATE, keep it

-- ---------------------------------------------------------------------------
-- 5) Quest token grant RPC — server-authoritative (not local preview)
-- ---------------------------------------------------------------------------
create or replace function public.grant_quest_tokens(p_spinner int default 0, p_match int default 0, p_scratch int default 0, p_source text default 'quest')
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare v_phone text; ls_row public.loyalty_state; new_spinner int; new_match int; new_scratch int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'no customer row' using errcode='42501'; end if;
  if coalesce(p_spinner,0) <0 or coalesce(p_match,0) <0 or coalesce(p_scratch,0)<0 then raise exception 'negative grant' using errcode='P0001'; end if;
  if coalesce(p_spinner,0)=0 and coalesce(p_match,0)=0 and coalesce(p_scratch,0)=0 then return jsonb_build_object('granted',0); end if;
  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  new_spinner := least(coalesce(ls_row.spinner_tokens,0)+coalesce(p_spinner,0),5);
  new_match := least(coalesce(ls_row.match_tokens,0)+coalesce(p_match,0),5);
  new_scratch := least(coalesce(ls_row.scratch_tokens,0)+coalesce(p_scratch,0),5);
  -- create ledger entries for each token granted
  declare i int;
  begin
    for i in 1..(new_spinner - coalesce(ls_row.spinner_tokens,0)) loop perform public.create_token(v_phone,'spinner',p_source); end loop;
    for i in 1..(new_match - coalesce(ls_row.match_tokens,0)) loop perform public.create_token(v_phone,'match',p_source); end loop;
    for i in 1..(new_scratch - coalesce(ls_row.scratch_tokens,0)) loop perform public.create_token(v_phone,'scratch',p_source); end loop;
  end;
  update public.loyalty_state set spinner_tokens=new_spinner, match_tokens=new_match, scratch_tokens=new_scratch, updated_at=now() where phone=v_phone;
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text, 'grant_quest_tokens', v_phone, jsonb_build_object('spinner', p_spinner, 'match', p_match, 'scratch', p_scratch, 'source', p_source));
  return jsonb_build_object('spinner_tokens', new_spinner, 'match_tokens', new_match, 'scratch_tokens', new_scratch);
end;
$$;
comment on function public.grant_quest_tokens(int,int,int,text) is '0050 thorough: server-authoritative quest token grant with ledger + cap 5.';
revoke all on function public.grant_quest_tokens(int,int,int,text) from public; grant execute on function public.grant_quest_tokens(int,int,int,text) to authenticated;

-- also grant points server-authoritative for quests (to avoid local preview desync)
create or replace function public.grant_quest_points(p_points int)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare v_phone text;
begin
  if coalesce(p_points,0) <=0 then return jsonb_build_object('points',0); end if;
  v_phone := public.current_customer_phone();
  if v_phone is null then raise exception 'no customer row' using errcode='42501'; end if;
  update public.loyalty_state set points=points+p_points, lifetime_points=lifetime_points+p_points, updated_at=now() where phone=v_phone;
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text, 'grant_quest_points', v_phone, jsonb_build_object('points', p_points));
  return jsonb_build_object('points', p_points);
end;
$$;
revoke all on function public.grant_quest_points(int) from public; grant execute on function public.grant_quest_points(int) to authenticated;

commit;
