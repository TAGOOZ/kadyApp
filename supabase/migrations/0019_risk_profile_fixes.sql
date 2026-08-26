-- 0019_risk_profile_fixes.sql — RISK-02 review fixes
-- Addresses audit findings on 0018:
-- • UTC vs local, deterministic clock, copyWith sentinel handled in Dart (no DDL)
-- • Redundant idx_risk_profiles_phone (PK already covers phone)
-- • sync_risk_profile dedup per (order_id,event_type) allowed double total_orders on ping-pong
--   → dedup per order_id any type (one terminal outcome per order) with guard BEFORE counters
-- • Missing REVOKE commentary — actually revoke table writes from client roles
-- • set_updated_at() missing search_path (hijackable)

begin;

-- ---------------------------------------------------------------------------
-- 1. Redundant index: PK on customer_risk_profiles(phone) already indexes phone.
--    Drop the extra index if it exists (spec parity comment retained in 0018).
-- ---------------------------------------------------------------------------
drop index if exists public.idx_risk_profiles_phone;

-- ---------------------------------------------------------------------------
-- 2. Harden set_updated_at() with search_path (hijack prevention).
--    Used by customer_risk_profiles and other tables.
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_customer_risk_profiles_updated_at on public.customer_risk_profiles;
create trigger trg_customer_risk_profiles_updated_at
  before update on public.customer_risk_profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Fix sync_risk_profile() dedup: prevent double total_orders increment
--    when an order ping-pongs between terminal statuses (e.g. done→cancelled).
--    Previously UPDATE happened before dedup check, so second event type still
--    incremented counters. Now we determine event type, check exists, then
--    mutate counters and insert — at most one terminal outcome per order_id.
-- ---------------------------------------------------------------------------
create or replace function public.sync_risk_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone      text := new.phone;
  v_event_type text := null;
  v_total      int  := coalesce(new.total, 0);
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if v_phone is null then
    return new;
  end if;

  insert into public.customer_risk_profiles (phone)
  values (v_phone)
  on conflict (phone) do nothing;

  -- Determine event type first (no side-effects) — keeps Dart/SQL parity
  -- and allows idempotency guard before any counter mutation.
  if new.status = 'done' then
    v_event_type := 'SUCCESSFUL_ORDER';
  elsif new.status = 'cancelled' then
    if new.reject_reason is not null
       and new.reject_reason ~* 'refused|rejected' then
      v_event_type := 'REJECTED_ORDER';
    elsif new.reject_reason is not null
          and new.reject_reason ~* 'failed.*delivery|delivery.*failed|failed_delivery' then
      v_event_type := 'FAILED_DELIVERY';
    elsif new.reject_reason is not null
          and new.reject_reason ilike '%cancel%' then
      v_event_type := 'CANCELLED_ORDER';
    else
      v_event_type := 'CANCELLED_ORDER';
    end if;
  else
    return new;
  end if;

  if v_event_type is null then
    return new;
  end if;

  -- Idempotent per order_id: at most one terminal outcome per order.
  if exists (select 1 from public.risk_events where order_id = new.id) then
    return new;
  end if;

  -- Now mutate counters (only if no prior terminal event)
  if v_event_type = 'SUCCESSFUL_ORDER' then
    update public.customer_risk_profiles
       set total_orders      = total_orders + 1,
           successful_orders = successful_orders + 1,
           total_spent       = total_spent + v_total,
           last_order_at     = now(),
           updated_at        = now()
     where phone = v_phone;
  elsif v_event_type = 'CANCELLED_ORDER' then
    update public.customer_risk_profiles
       set total_orders     = total_orders + 1,
           cancelled_orders = cancelled_orders + 1,
           last_order_at    = now(),
           updated_at       = now()
     where phone = v_phone;
  elsif v_event_type = 'REJECTED_ORDER' then
    update public.customer_risk_profiles
       set total_orders    = total_orders + 1,
           rejected_orders = rejected_orders + 1,
           last_order_at   = now(),
           updated_at      = now()
     where phone = v_phone;
  elsif v_event_type = 'FAILED_DELIVERY' then
    update public.customer_risk_profiles
       set total_orders     = total_orders + 1,
           failed_deliveries = failed_deliveries + 1,
           last_order_at    = now(),
           updated_at       = now()
     where phone = v_phone;
  end if;

  insert into public.risk_events (phone, order_id, event_type, metadata)
  values (
    v_phone,
    new.id,
    v_event_type,
    jsonb_build_object(
      'old_status', old.status,
      'new_status', new.status,
      'reject_reason', new.reject_reason,
      'total', v_total
    )
  );

  return new;
end;
$$;

comment on function public.sync_risk_profile() is
  'Centralised post-order outcome sync (RISK-02, 0019 fix): dedup per order_id before counters prevents double total_orders on status ping-pong; cancelled vs rejected vs failed_delivery distinguished via reject_reason. SECURITY DEFINER so counters are server-authoritative.';

drop trigger if exists trg_sync_risk_profile on public.orders;
create trigger trg_sync_risk_profile
  after update of status on public.orders
  for each row execute function public.sync_risk_profile();

-- ---------------------------------------------------------------------------
-- 4. Enforce server-authoritative writes: revoke direct table writes from
--    client roles (defense in depth). RLS with no INSERT/UPDATE policy already
--    blocks, but table grants also need revoking (Supabase default gives
--    authenticated table privileges). Follows pattern of 0015_revoke_loyalty_writes
--    (revoke all on function ... from public).
-- ---------------------------------------------------------------------------
revoke all on table public.customer_risk_profiles from public, anon, authenticated;
revoke all on table public.risk_events from public, anon, authenticated;

grant select on table public.customer_risk_profiles to authenticated;
grant select on table public.risk_events to authenticated;

-- Service roles keep full access for triggers and admin tooling.
grant all on table public.customer_risk_profiles to service_role;
grant all on table public.risk_events to service_role;
grant all on sequence public.risk_events_id_seq to service_role, authenticated;

comment on table public.customer_risk_profiles is
  'Derived risk identity per Customer (phone FK). Counters are server-authoritative — mutated only via trigger sync_risk_profile() and handle_new_customer_risk_profile(). Revoked from client roles; select via RLS only. risk_score/level cached from calculateRisk (RISK-04).';
comment on table public.risk_events is
  'Append-only fraud audit ledger. Insert only via SECURITY DEFINER trigger sync_risk_profile() (dedup per order_id). Revoked from client roles; select via RLS only — unauthenticated insert fails 42501.';

commit;
