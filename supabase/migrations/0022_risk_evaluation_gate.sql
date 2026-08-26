-- 0022_risk_evaluation_gate.sql — RISK-04
-- Central risk gate that implements §11 flow: Validate order → collect
-- Customer/Device/Address context → evaluate risk (pure engine) → store
-- risk_score/level/action/reasons → create risk_events → determine action → gate dispatch.
-- Must not allow an order that needs_verification to progress to accepted/in_prep/ready
-- until verification completes.
--
-- Trigger ordering (BEFORE INSERT, alphabetical execution):
--   trg_a_validate_order_pricing  (0016) — recompute subtotal/total from menu_items§16
--   trg_b_evaluate_order_risk     (this) — collect context, run SQL mirror of Dart engine, set NEW.risk_*
--   trg_c_enforce_order_rate_limit(0004) — per-phone rate limit check
-- All three are dropped and recreated with a_ / b_ / c_ prefix to enforce order;
-- Postgres fires BEFORE INSERT triggers alphabetically by name.
--
-- Dart parity: lib/domain/risk_engine.dart calculateRisk — keep identical when
-- changing either. SQL mirror reads thresholds from app_config (risk.*) and rule
-- catalog from risk_rules (enabled + score), clamps 0..100, handles extrinsic-only
-- cap (shared device/address never auto-rejects alone), and writes orders.risk_*.
-- AFTER INSERT hook creates risk_events per reason in same transaction.
-- Dispatch gate patches orders_guard_update + transition_order to raise P0001 when
-- risk_action='needs_verification' without confirmed verification_requests row.
-- Loyalty credit (0004) gains WHEN guard so points/stamps not credited while held.

begin;

-- ---------------------------------------------------------------------------
-- 0. orders.idempotency_key — client dedup (uuid v4 per submit, 30s debounce)
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists idempotency_key text;

comment on column public.orders.idempotency_key is 'Client idempotency key (uuid v4 per submit, RISK-04). 30s debounce in checkout_screen.dart + server unique index on (phone, idempotency_key). Replay within window returns existing PlacedOrder.';

create unique index if not exists idx_orders_idempotency
  on public.orders (phone, idempotency_key)
  where idempotency_key is not null;

create index if not exists idx_orders_idempotency_key
  on public.orders (idempotency_key)
  where idempotency_key is not null;

-- ---------------------------------------------------------------------------
-- 0b. verification_requests — stub for dispatch gate (RISK-05 full table lands later)
-- RISK-04 gate checks for confirmed row before allowing accepted→done transitions.
-- If RISK-05 migration later creates this table with IF NOT EXISTS, this stub is
-- idempotent. RLS: insert via SECURITY DEFINER only, select own + staff/admin.
-- ---------------------------------------------------------------------------
create table if not exists public.verification_requests (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders (id) on delete cascade,
  phone       text references public.customers (phone) on delete cascade,
  device_id   text,
  status      text not null default 'pending'
              check (status in ('pending','confirmed','rejected','expired','cancelled')),
  provider    text not null default 'manual',
  code_hash   text,
  attempts    int  not null default 0,
  max_attempts int not null default 5,
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.verification_requests is 'Verification gate for RISK-04/RISK-05: order held when risk_action=needs_verification until confirmed row exists. Created in 0022 stub, enriched in RISK-05.';
comment on column public.verification_requests.status is 'pending → confirmed (staff) lifts gate; rejected/expired keep gate closed.';

create index if not exists idx_verification_order_id on public.verification_requests (order_id);
create index if not exists idx_verification_phone_status on public.verification_requests (phone, status);
create index if not exists idx_verification_expires_at on public.verification_requests (expires_at) where expires_at is not null;

drop trigger if exists trg_verification_requests_updated_at on public.verification_requests;
create trigger trg_verification_requests_updated_at
  before update on public.verification_requests
  for each row execute function public.set_updated_at();

alter table public.verification_requests enable row level security;

do $vr_rls$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='verification_requests'
       and policyname='verification_requests_select_own'
  ) then
    create policy verification_requests_select_own
      on public.verification_requests
      for select to authenticated
      using (
        exists (
          select 1 from public.customers c
           where c.phone = verification_requests.phone
             and c.google_user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='verification_requests'
       and policyname='verification_requests_staff_admin_read'
  ) then
    create policy verification_requests_staff_admin_read
      on public.verification_requests
      for select to authenticated
      using (public.has_any_role(array['staff','admin']::text[]));
  end if;

  -- No INSERT/UPDATE policy for clients — writes only via SECURITY DEFINER RPC
  -- (confirmByStaff / requestVerification). RLS without policy already blocks.
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='verification_requests'
       and policyname='verification_requests_staff_admin_update'
  ) then
    create policy verification_requests_staff_admin_update
      on public.verification_requests
      for update to authenticated
      using (public.has_any_role(array['staff','admin']::text[]))
      with check (public.has_any_role(array['staff','admin']::text[]));
  end if;
end;
$vr_rls$;

revoke all on table public.verification_requests from public, anon;
grant select on table public.verification_requests to authenticated;
grant all on table public.verification_requests to service_role;

-- ---------------------------------------------------------------------------
-- 1. BEFORE INSERT — evaluate risk and set NEW.risk_* (SQL mirror of Dart)
-- ---------------------------------------------------------------------------
create or replace function public.evaluate_order_risk_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Config fallbacks match lib/domain/risk_engine.dart constants + 0017 seeds
  v_low_max      int := 29;
  v_medium_max   int := 59;
  v_large_threshold int := 500;
  v_rapid_count  int := 3;
  v_rapid_window int := 30;
  v_val text;

  -- Profile context
  v_total_orders int := 0;
  v_successful   int := 0;
  v_cancelled    int := 0;
  v_failed       int := 0;
  v_rejected     int := 0;
  v_verified     bool := false;
  v_profile_found bool := false;

  -- Device / address extrinsic counts (effective after this order)
  v_is_new_device bool := false;
  v_device_distinct_before int := 0;
  v_device_customer_count int := 0;
  v_addr_distinct_before int := 0;
  v_addr_has_phone bool := false;
  v_address_customer_count int := 0;
  v_address_failed_count int := 0;

  -- Rapid window count
  v_recent_orders int := 0;
  v_is_rapid bool := false;

  -- Rule catalog — defaults match kDefaultRiskRules; overwritten from risk_rules if present
  v_score_NEW_CUSTOMER int := 20; v_en_NEW_CUSTOMER bool := true;
  v_score_NEW_DEVICE int := 10; v_en_NEW_DEVICE bool := true;
  v_score_PREV_FAILED int := 25; v_en_PREV_FAILED bool := true;
  v_score_PREV_REJECTED int := 30; v_en_PREV_REJECTED bool := true;
  v_score_THREE_PLUS_CANCEL int := 25; v_en_THREE_PLUS_CANCEL bool := true;
  v_score_LARGE_ORDER int := 15; v_en_LARGE_ORDER bool := true;
  v_score_RAPID_ORDERS int := 20; v_en_RAPID_ORDERS bool := true;
  v_score_THREE_PLUS_SUCCESS int := -20; v_en_THREE_PLUS_SUCCESS bool := true;
  v_score_FIVE_PLUS_SUCCESS int := -30; v_en_FIVE_PLUS_SUCCESS bool := true;
  v_score_VERIFIED_PHONE int := -15; v_en_VERIFIED_PHONE bool := true;
  v_score_MULTI_DEVICE int := 10; v_en_MULTI_DEVICE bool := true;
  v_score_MULTI_ADDRESS int := 10; v_en_MULTI_ADDRESS bool := false;
  v_score_ADDR_HIGH_FAIL int := 15; v_en_ADDR_HIGH_FAIL bool := false;

  -- Scoring
  v_score int := 0;
  v_reasons text[] := '{}';
  v_is_large bool := false;
  v_extrinsic_only bool := false;
  v_level text;
  v_action text;

  r record;
begin
  -- -----------------------------------------------------------------------
  -- Config: fetch from app_config, keep fallbacks on missing/parse failure
  -- -----------------------------------------------------------------------
  begin
    select value::text::int into v_low_max from public.app_config where key='risk.low_max_score';
  exception when others then null; end;
  v_low_max := coalesce(v_low_max, 29);

  begin
    select value::text::int into v_medium_max from public.app_config where key='risk.medium_max_score';
  exception when others then null; end;
  v_medium_max := coalesce(v_medium_max, 59);

  begin
    select value::text::int into v_large_threshold from public.app_config where key='risk.large_order_threshold';
  exception when others then null; end;
  v_large_threshold := coalesce(v_large_threshold, 500);

  begin
    select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count';
  exception when others then null; end;
  v_rapid_count := coalesce(v_rapid_count, 3);

  begin
    select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes';
  exception when others then null; end;
  v_rapid_window := coalesce(v_rapid_window, 30);

  -- Threshold sanity: match Dart RiskConfig.fromMap validation + fallback swap
  if v_low_max >= v_medium_max then
    -- Swap if misconfigured (release-safe), Dart does same in _normalizedThresholds
    declare tmp int := v_low_max; begin v_low_max := v_medium_max; v_medium_max := tmp; end;
  end if;
  if v_low_max < 0 then v_low_max := 0; end if;
  if v_medium_max > 100 then v_medium_max := 100; end if;

  -- -----------------------------------------------------------------------
  -- Rules: fetch enabled + score overrides from risk_rules (idempotent)
  -- -----------------------------------------------------------------------
  for r in select rule_code, score, enabled from public.risk_rules loop
    case r.rule_code
      when 'NEW_CUSTOMER' then v_score_NEW_CUSTOMER := r.score; v_en_NEW_CUSTOMER := r.enabled;
      when 'NEW_DEVICE' then v_score_NEW_DEVICE := r.score; v_en_NEW_DEVICE := r.enabled;
      when 'PREVIOUS_FAILED_DELIVERY' then v_score_PREV_FAILED := r.score; v_en_PREV_FAILED := r.enabled;
      when 'PREVIOUS_REJECTED_ORDER' then v_score_PREV_REJECTED := r.score; v_en_PREV_REJECTED := r.enabled;
      when 'THREE_PLUS_CANCELLATIONS' then v_score_THREE_PLUS_CANCEL := r.score; v_en_THREE_PLUS_CANCEL := r.enabled;
      when 'LARGE_ORDER' then v_score_LARGE_ORDER := r.score; v_en_LARGE_ORDER := r.enabled;
      when 'RAPID_ORDERS' then v_score_RAPID_ORDERS := r.score; v_en_RAPID_ORDERS := r.enabled;
      when 'THREE_PLUS_SUCCESSFUL' then v_score_THREE_PLUS_SUCCESS := r.score; v_en_THREE_PLUS_SUCCESS := r.enabled;
      when 'FIVE_PLUS_SUCCESSFUL' then v_score_FIVE_PLUS_SUCCESS := r.score; v_en_FIVE_PLUS_SUCCESS := r.enabled;
      when 'VERIFIED_PHONE' then v_score_VERIFIED_PHONE := r.score; v_en_VERIFIED_PHONE := r.enabled;
      when 'MULTIPLE_ACCOUNTS_DEVICE' then v_score_MULTI_DEVICE := r.score; v_en_MULTI_DEVICE := r.enabled;
      when 'MULTIPLE_ACCOUNTS_ADDRESS' then v_score_MULTI_ADDRESS := r.score; v_en_MULTI_ADDRESS := r.enabled;
      when 'ADDRESS_HIGH_FAILURE' then v_score_ADDR_HIGH_FAIL := r.score; v_en_ADDR_HIGH_FAIL := r.enabled;
      else null;
    end case;
  end loop;

  -- -----------------------------------------------------------------------
  -- Context: customer_risk_profiles
  -- -----------------------------------------------------------------------
  if new.phone is not null then
    select total_orders, successful_orders, cancelled_orders, failed_deliveries, rejected_orders, phone_verified
      into v_total_orders, v_successful, v_cancelled, v_failed, v_rejected, v_verified
      from public.customer_risk_profiles
     where phone = new.phone;
    if found then
      v_profile_found := true;
    else
      -- No profile yet (first order before handle_new_customer trigger): treat as new customer
      v_total_orders := 0; v_successful := 0; v_cancelled := 0; v_failed := 0; v_rejected := 0; v_verified := false;
      v_profile_found := false;
    end if;
  else
    v_total_orders := 0; v_successful := 0; v_cancelled := 0; v_failed := 0; v_rejected := 0; v_verified := false;
  end if;

  -- -----------------------------------------------------------------------
  -- Context: device tracking — isNewDevice + deviceCustomerCount (effective)
  -- -----------------------------------------------------------------------
  if new.device_id is not null and new.device_id <> '' then
    -- distinct phones already using this device_id (before this order)
    select count(distinct phone) into v_device_distinct_before
      from public.customer_devices
     where device_id = new.device_id;

    -- is this phone+device new?
    if new.phone is not null then
      select not exists (
        select 1 from public.customer_devices
         where phone = new.phone and device_id = new.device_id
      ) into v_is_new_device;
    else
      v_is_new_device := true;
    end if;

    -- effective count after this order would be inserted (track_device does upsert AFTER)
    if v_is_new_device then
      v_device_customer_count := v_device_distinct_before + 1;
    else
      v_device_customer_count := v_device_distinct_before;
    end if;
  else
    v_is_new_device := false;
    v_device_customer_count := 0;
    v_device_distinct_before := 0;
  end if;

  -- -----------------------------------------------------------------------
  -- Context: address history — addressCustomerCount + addressFailedCount (effective)
  -- -----------------------------------------------------------------------
  if new.address_id is not null then
    -- distinct phones that have ordered to this address before
    select count(distinct phone) into v_addr_distinct_before
      from public.orders
     where address_id = new.address_id;

    if new.phone is not null then
      select not exists (
        select 1 from public.orders
         where address_id = new.address_id and phone = new.phone
      ) into v_addr_has_phone;
      -- actually v_addr_has_phone is whether this phone already used this address; invert for effective
      select exists (
        select 1 from public.orders
         where address_id = new.address_id and phone = new.phone
      ) into v_addr_has_phone;
      if v_addr_has_phone then
        v_address_customer_count := v_addr_distinct_before;
      else
        v_address_customer_count := v_addr_distinct_before + 1;
      end if;
    else
      v_address_customer_count := v_addr_distinct_before;
    end if;

    -- failed/cancelled at this address (spec: ADDRESS_HIGH_FAILURE >=3)
    select count(*) into v_address_failed_count
      from public.orders
     where address_id = new.address_id
       and status = 'cancelled';
    -- Include this order's potential future failure? Not yet, so keep as is.
    -- For gate we want history, not including current.
  else
    v_address_customer_count := 0;
    v_address_failed_count := 0;
  end if;

  -- -----------------------------------------------------------------------
  -- Context: rapid orders window — count recent orders for this phone
  -- -----------------------------------------------------------------------
  if new.phone is not null and v_rapid_window > 0 and v_rapid_count > 0 then
    select count(*) into v_recent_orders
      from public.orders
     where phone = new.phone
       and created_at > now() - (v_rapid_window || ' minutes')::interval;
    -- current order will be +1, so isRapid if existing+1 >= threshold
    if (v_recent_orders + 1) >= v_rapid_count then
      v_is_rapid := true;
    else
      v_is_rapid := false;
    end if;
  else
    v_is_rapid := false;
  end if;

  -- -----------------------------------------------------------------------
  -- Scoring — mirrors lib/domain/risk_engine.dart calculateRisk exactly
  -- -----------------------------------------------------------------------
  v_score := 0;
  v_reasons := '{}';

  -- Helper: apply if condition and enabled
  -- NEW_CUSTOMER
  if new.phone is not null and v_total_orders = 0 and v_en_NEW_CUSTOMER then
    v_score := v_score + v_score_NEW_CUSTOMER;
    v_reasons := array_append(v_reasons, 'NEW_CUSTOMER');
  end if;

  -- NEW_DEVICE
  if v_is_new_device and v_en_NEW_DEVICE then
    v_score := v_score + v_score_NEW_DEVICE;
    v_reasons := array_append(v_reasons, 'NEW_DEVICE');
  end if;

  -- PREVIOUS_FAILED_DELIVERY
  if v_failed > 0 and v_en_PREV_FAILED then
    v_score := v_score + v_score_PREV_FAILED;
    v_reasons := array_append(v_reasons, 'PREVIOUS_FAILED_DELIVERY');
  end if;

  -- PREVIOUS_REJECTED_ORDER
  if v_rejected > 0 and v_en_PREV_REJECTED then
    v_score := v_score + v_score_PREV_REJECTED;
    v_reasons := array_append(v_reasons, 'PREVIOUS_REJECTED_ORDER');
  end if;

  -- THREE_PLUS_CANCELLATIONS
  if v_cancelled >= 3 and v_en_THREE_PLUS_CANCEL then
    v_score := v_score + v_score_THREE_PLUS_CANCEL;
    v_reasons := array_append(v_reasons, 'THREE_PLUS_CANCELLATIONS');
  end if;

  -- LARGE_ORDER — explicit flag OR threshold check (server recomputes from menu_items via validate_order_pricing)
  -- At this point NEW.subtotal is already corrected by validate_order_pricing (trigger ordering a→b)
  v_is_large := coalesce(new.subtotal, 0) >= v_large_threshold;
  if v_is_large and v_en_LARGE_ORDER then
    v_score := v_score + v_score_LARGE_ORDER;
    v_reasons := array_append(v_reasons, 'LARGE_ORDER');
  end if;

  -- RAPID_ORDERS
  if v_is_rapid and v_en_RAPID_ORDERS then
    v_score := v_score + v_score_RAPID_ORDERS;
    v_reasons := array_append(v_reasons, 'RAPID_ORDERS');
  end if;

  -- Successful bonuses exclusive: 5+ supersedes 3+, fallback to 3+ when 5+ disabled
  if v_successful >= 5 and v_en_FIVE_PLUS_SUCCESS then
    v_score := v_score + v_score_FIVE_PLUS_SUCCESS;
    v_reasons := array_append(v_reasons, 'FIVE_PLUS_SUCCESSFUL');
  elsif v_successful >= 3 and v_en_THREE_PLUS_SUCCESS then
    v_score := v_score + v_score_THREE_PLUS_SUCCESS;
    v_reasons := array_append(v_reasons, 'THREE_PLUS_SUCCESSFUL');
  end if;

  -- VERIFIED_PHONE
  if v_verified and v_en_VERIFIED_PHONE then
    v_score := v_score + v_score_VERIFIED_PHONE;
    v_reasons := array_append(v_reasons, 'VERIFIED_PHONE');
  end if;

  -- RISK-03 extrinsic signals — signal not proof
  if v_device_customer_count >= 2 and v_en_MULTI_DEVICE then
    v_score := v_score + v_score_MULTI_DEVICE;
    v_reasons := array_append(v_reasons, 'MULTIPLE_ACCOUNTS_DEVICE');
  end if;

  if v_address_customer_count >= 2 and v_en_MULTI_ADDRESS then
    v_score := v_score + v_score_MULTI_ADDRESS;
    v_reasons := array_append(v_reasons, 'MULTIPLE_ACCOUNTS_ADDRESS');
  end if;

  if v_address_failed_count >= 3 and v_en_ADDR_HIGH_FAIL then
    v_score := v_score + v_score_ADDR_HIGH_FAIL;
    v_reasons := array_append(v_reasons, 'ADDRESS_HIGH_FAILURE');
  end if;

  -- Extrinsic-only cap: shared device/address signals alone must never push to HIGH
  -- If every contributing reason is extrinsic, clamp to mediumMax (59) so decision stays at worst needs_verification.
  if array_length(v_reasons, 1) is not null then
    select bool_and(elem = any(array['NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE']))
      into v_extrinsic_only
      from unnest(v_reasons) as elem;
    if v_extrinsic_only and v_score > v_medium_max then
      v_score := v_medium_max;
    end if;
  end if;

  -- Clamp 0..100
  if v_score < 0 then v_score := 0; end if;
  if v_score > 100 then v_score := 100; end if;

  -- Level / action from thresholds (configurable, not hardcoded)
  if v_score <= v_low_max then
    v_level := 'low';
    v_action := 'approved';
  elsif v_score <= v_medium_max then
    v_level := 'medium';
    v_action := 'needs_verification';
  else
    v_level := 'high';
    v_action := 'rejected';
  end if;

  -- Write to NEW — same transaction, server-authoritative
  new.risk_score := v_score;
  new.risk_level := v_level;
  new.risk_action := v_action;
  new.risk_reasons := to_jsonb(v_reasons);
  new.risk_evaluated_at := now();

  return new;
end;
$$;

comment on function public.evaluate_order_risk_trigger() is 'RISK-04 BEFORE INSERT gate (a→b→c ordering): mirrors Dart calculateRisk (lib/domain/risk_engine.dart). Reads corrected subtotal after validate_order_pricing, collects customer_risk_profiles/device/address/rapid window, calls SQL mirror to compute score/level/action/reasons, writes orders.risk_* in same transaction. SECURITY DEFINER.';

-- ---------------------------------------------------------------------------
-- Drop ALL BEFORE INSERT triggers on orders and recreate in alphabetical order
-- a_validate, b_evaluate, c_enforce to enforce validate → evaluate → enforce
-- ---------------------------------------------------------------------------
drop trigger if exists trg_validate_order_pricing on public.orders;
drop trigger if exists trg_evaluate_order_risk on public.orders;
drop trigger if exists trg_enforce_order_rate_limit on public.orders;
drop trigger if exists trg_orders_display_number on public.orders;
-- Also drop any legacy a/b/c names if they exist from previous runs
drop trigger if exists trg_a_validate_order_pricing on public.orders;
drop trigger if exists trg_b_evaluate_order_risk on public.orders;
drop trigger if exists trg_c_enforce_order_rate_limit on public.orders;
drop trigger if exists trg_00_assign_display_number on public.orders;

create trigger trg_00_assign_display_number
  before insert on public.orders
  for each row execute function public.assign_order_display_number();

create trigger trg_a_validate_order_pricing
  before insert on public.orders
  for each row execute function public.validate_order_pricing();

create trigger trg_b_evaluate_order_risk
  before insert on public.orders
  for each row execute function public.evaluate_order_risk_trigger();

create trigger trg_c_enforce_order_rate_limit
  before insert on public.orders
  for each row execute function public.enforce_order_rate_limit();

-- Also expose a callable SECURITY DEFINER function evaluate_order_risk(p_order_id)
-- for admin re-evaluation (mirrors BEFORE trigger logic but updates existing row).
create or replace function public.evaluate_order_risk(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.orders%rowtype;
begin
  select * into r from public.orders where id = p_order_id;
  if not found then
    raise exception 'evaluate_order_risk: order % not found', p_order_id using errcode='P0002';
  end if;
  -- Reuse trigger logic by constructing a NEW-like row and calling the same scoring
  -- Instead of duplicating logic, we simulate an insert evaluation by updating risk columns
  -- via the trigger function: create a temp trigger call requires row-level logic, so
  -- we duplicate minimal update path: set risk columns via evaluate_order_risk_trigger logic
  -- For simplicity, perform an UPDATE that fires the BEFORE UPDATE? Instead we directly
  -- call the same scoring inline — reuse code by updating via a direct UPDATE with computed values.
  -- To avoid duplication, we just invoke a helper: update the row to re-trigger evaluation.
  -- Easiest: perform an UPDATE that sets risk_evaluated_at = null to force re-evaluation via trigger?
  -- But evaluate trigger is BEFORE INSERT only. So we need a separate UPDATE path.
  -- We implement the same scoring here for UPDATE: copy trigger body but write to orders table.
  -- For now, delegate to an inline block that recomputes and updates the order row.

  -- We will compute anew by selecting the existing row and applying the same logic as trigger,
  -- then update orders risk columns directly (bypass RLS via SECURITY DEFINER).
  declare
    v_low_max int := 29; v_medium_max int := 59; v_large_threshold int := 500;
    v_rapid_count int := 3; v_rapid_window int := 30;
    v_total_orders int :=0; v_successful int:=0; v_cancelled int:=0; v_failed int:=0; v_rejected int:=0; v_verified bool:=false;
    v_is_new_device bool:=false; v_device_distinct_before int:=0; v_device_customer_count int:=0;
    v_addr_distinct_before int:=0; v_addr_has_phone bool:=false; v_address_customer_count int:=0; v_address_failed_count int:=0;
    v_recent_orders int:=0; v_is_rapid bool:=false;
    v_score_NEW_CUSTOMER int:=20; v_en_NEW_CUSTOMER bool:=true;
    v_score_NEW_DEVICE int:=10; v_en_NEW_DEVICE bool:=true;
    v_score_PREV_FAILED int:=25; v_en_PREV_FAILED bool:=true;
    v_score_PREV_REJECTED int:=30; v_en_PREV_REJECTED bool:=true;
    v_score_THREE_PLUS_CANCEL int:=25; v_en_THREE_PLUS_CANCEL bool:=true;
    v_score_LARGE_ORDER int:=15; v_en_LARGE_ORDER bool:=true;
    v_score_RAPID_ORDERS int:=20; v_en_RAPID_ORDERS bool:=true;
    v_score_THREE_PLUS_SUCCESS int:=-20; v_en_THREE_PLUS_SUCCESS bool:=true;
    v_score_FIVE_PLUS_SUCCESS int:=-30; v_en_FIVE_PLUS_SUCCESS bool:=true;
    v_score_VERIFIED_PHONE int:=-15; v_en_VERIFIED_PHONE bool:=true;
    v_score_MULTI_DEVICE int:=10; v_en_MULTI_DEVICE bool:=true;
    v_score_MULTI_ADDRESS int:=10; v_en_MULTI_ADDRESS bool:=false;
    v_score_ADDR_HIGH_FAIL int:=15; v_en_ADDR_HIGH_FAIL bool:=false;
    v_score int:=0; v_reasons text[]:='{}'; v_is_large bool:=false; v_extrinsic_only bool:=false; v_level text; v_action text;
    rr record;
    new_row public.orders%rowtype;
  begin
    new_row := r;
    -- Fetch config
    begin select value::text::int into v_low_max from public.app_config where key='risk.low_max_score'; exception when others then null; end; v_low_max:=coalesce(v_low_max,29);
    begin select value::text::int into v_medium_max from public.app_config where key='risk.medium_max_score'; exception when others then null; end; v_medium_max:=coalesce(v_medium_max,59);
    begin select value::text::int into v_large_threshold from public.app_config where key='risk.large_order_threshold'; exception when others then null; end; v_large_threshold:=coalesce(v_large_threshold,500);
    begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count:=coalesce(v_rapid_count,3);
    begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window:=coalesce(v_rapid_window,30);
    if v_low_max >= v_medium_max then declare tmp int:=v_low_max; begin v_low_max:=v_medium_max; v_medium_max:=tmp; end; end if;
    if v_low_max<0 then v_low_max:=0; end if;
    if v_medium_max>100 then v_medium_max:=100; end if;
    for rr in select rule_code, score, enabled from public.risk_rules loop
      case rr.rule_code
        when 'NEW_CUSTOMER' then v_score_NEW_CUSTOMER:=rr.score; v_en_NEW_CUSTOMER:=rr.enabled;
        when 'NEW_DEVICE' then v_score_NEW_DEVICE:=rr.score; v_en_NEW_DEVICE:=rr.enabled;
        when 'PREVIOUS_FAILED_DELIVERY' then v_score_PREV_FAILED:=rr.score; v_en_PREV_FAILED:=rr.enabled;
        when 'PREVIOUS_REJECTED_ORDER' then v_score_PREV_REJECTED:=rr.score; v_en_PREV_REJECTED:=rr.enabled;
        when 'THREE_PLUS_CANCELLATIONS' then v_score_THREE_PLUS_CANCEL:=rr.score; v_en_THREE_PLUS_CANCEL:=rr.enabled;
        when 'LARGE_ORDER' then v_score_LARGE_ORDER:=rr.score; v_en_LARGE_ORDER:=rr.enabled;
        when 'RAPID_ORDERS' then v_score_RAPID_ORDERS:=rr.score; v_en_RAPID_ORDERS:=rr.enabled;
        when 'THREE_PLUS_SUCCESSFUL' then v_score_THREE_PLUS_SUCCESS:=rr.score; v_en_THREE_PLUS_SUCCESS:=rr.enabled;
        when 'FIVE_PLUS_SUCCESSFUL' then v_score_FIVE_PLUS_SUCCESS:=rr.score; v_en_FIVE_PLUS_SUCCESS:=rr.enabled;
        when 'VERIFIED_PHONE' then v_score_VERIFIED_PHONE:=rr.score; v_en_VERIFIED_PHONE:=rr.enabled;
        when 'MULTIPLE_ACCOUNTS_DEVICE' then v_score_MULTI_DEVICE:=rr.score; v_en_MULTI_DEVICE:=rr.enabled;
        when 'MULTIPLE_ACCOUNTS_ADDRESS' then v_score_MULTI_ADDRESS:=rr.score; v_en_MULTI_ADDRESS:=rr.enabled;
        when 'ADDRESS_HIGH_FAILURE' then v_score_ADDR_HIGH_FAIL:=rr.score; v_en_ADDR_HIGH_FAIL:=rr.enabled;
        else null;
      end case;
    end loop;
    if new_row.phone is not null then
      select total_orders, successful_orders, cancelled_orders, failed_deliveries, rejected_orders, phone_verified
        into v_total_orders, v_successful, v_cancelled, v_failed, v_rejected, v_verified
        from public.customer_risk_profiles where phone=new_row.phone;
      if not found then v_total_orders:=0; v_successful:=0; v_cancelled:=0; v_failed:=0; v_rejected:=0; v_verified:=false; end if;
    end if;
    if new_row.device_id is not null and new_row.device_id<>'' then
      select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id=new_row.device_id;
      if new_row.phone is not null then
        select not exists (select 1 from public.customer_devices where phone=new_row.phone and device_id=new_row.device_id) into v_is_new_device;
      else v_is_new_device:=true; end if;
      if v_is_new_device then v_device_customer_count:=v_device_distinct_before+1; else v_device_customer_count:=v_device_distinct_before; end if;
    else v_is_new_device:=false; v_device_customer_count:=0; end if;
    if new_row.address_id is not null then
      select count(distinct phone) into v_addr_distinct_before from public.orders where address_id=new_row.address_id;
      if new_row.phone is not null then
        select exists (select 1 from public.orders where address_id=new_row.address_id and phone=new_row.phone) into v_addr_has_phone;
        if v_addr_has_phone then v_address_customer_count:=v_addr_distinct_before; else v_address_customer_count:=v_addr_distinct_before+1; end if;
      else v_address_customer_count:=v_addr_distinct_before; end if;
      select count(*) into v_address_failed_count from public.orders where address_id=new_row.address_id and status='cancelled';
    else v_address_customer_count:=0; v_address_failed_count:=0; end if;
    if new_row.phone is not null and v_rapid_window>0 and v_rapid_count>0 then
      select count(*) into v_recent_orders from public.orders where phone=new_row.phone and created_at > now() - (v_rapid_window || ' minutes')::interval and id <> new_row.id;
      if (v_recent_orders+1) >= v_rapid_count then v_is_rapid:=true; else v_is_rapid:=false; end if;
    end if;
    v_score:=0; v_reasons:='{}';
    if new_row.phone is not null and v_total_orders=0 and v_en_NEW_CUSTOMER then v_score:=v_score+v_score_NEW_CUSTOMER; v_reasons:=array_append(v_reasons,'NEW_CUSTOMER'); end if;
    if v_is_new_device and v_en_NEW_DEVICE then v_score:=v_score+v_score_NEW_DEVICE; v_reasons:=array_append(v_reasons,'NEW_DEVICE'); end if;
    if v_failed>0 and v_en_PREV_FAILED then v_score:=v_score+v_score_PREV_FAILED; v_reasons:=array_append(v_reasons,'PREVIOUS_FAILED_DELIVERY'); end if;
    if v_rejected>0 and v_en_PREV_REJECTED then v_score:=v_score+v_score_PREV_REJECTED; v_reasons:=array_append(v_reasons,'PREVIOUS_REJECTED_ORDER'); end if;
    if v_cancelled>=3 and v_en_THREE_PLUS_CANCEL then v_score:=v_score+v_score_THREE_PLUS_CANCEL; v_reasons:=array_append(v_reasons,'THREE_PLUS_CANCELLATIONS'); end if;
    v_is_large:=coalesce(new_row.subtotal,0) >= v_large_threshold;
    if v_is_large and v_en_LARGE_ORDER then v_score:=v_score+v_score_LARGE_ORDER; v_reasons:=array_append(v_reasons,'LARGE_ORDER'); end if;
    if v_is_rapid and v_en_RAPID_ORDERS then v_score:=v_score+v_score_RAPID_ORDERS; v_reasons:=array_append(v_reasons,'RAPID_ORDERS'); end if;
    if v_successful>=5 and v_en_FIVE_PLUS_SUCCESS then v_score:=v_score+v_score_FIVE_PLUS_SUCCESS; v_reasons:=array_append(v_reasons,'FIVE_PLUS_SUCCESSFUL');
    elsif v_successful>=3 and v_en_THREE_PLUS_SUCCESS then v_score:=v_score+v_score_THREE_PLUS_SUCCESS; v_reasons:=array_append(v_reasons,'THREE_PLUS_SUCCESSFUL'); end if;
    if v_verified and v_en_VERIFIED_PHONE then v_score:=v_score+v_score_VERIFIED_PHONE; v_reasons:=array_append(v_reasons,'VERIFIED_PHONE'); end if;
    if v_device_customer_count>=2 and v_en_MULTI_DEVICE then v_score:=v_score+v_score_MULTI_DEVICE; v_reasons:=array_append(v_reasons,'MULTIPLE_ACCOUNTS_DEVICE'); end if;
    if v_address_customer_count>=2 and v_en_MULTI_ADDRESS then v_score:=v_score+v_score_MULTI_ADDRESS; v_reasons:=array_append(v_reasons,'MULTIPLE_ACCOUNTS_ADDRESS'); end if;
    if v_address_failed_count>=3 and v_en_ADDR_HIGH_FAIL then v_score:=v_score+v_score_ADDR_HIGH_FAIL; v_reasons:=array_append(v_reasons,'ADDRESS_HIGH_FAILURE'); end if;
    if array_length(v_reasons,1) is not null then
      select bool_and(elem = any(array['NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE'])) into v_extrinsic_only from unnest(v_reasons) as elem;
      if v_extrinsic_only and v_score > v_medium_max then v_score:=v_medium_max; end if;
    end if;
    if v_score<0 then v_score:=0; end if;
    if v_score>100 then v_score:=100; end if;
    if v_score <= v_low_max then v_level:='low'; v_action:='approved';
    elsif v_score <= v_medium_max then v_level:='medium'; v_action:='needs_verification';
    else v_level:='high'; v_action:='rejected'; end if;
    update public.orders
       set risk_score = v_score,
           risk_level = v_level,
           risk_action = v_action,
           risk_reasons = to_jsonb(v_reasons),
           risk_evaluated_at = now()
     where id = p_order_id;
  end;
end;
$$;

comment on function public.evaluate_order_risk(uuid) is 'RISK-04 callable re-evaluation (SECURITY DEFINER). Mirrors evaluate_order_risk_trigger logic for existing orders; used by admin re-evaluate or verification approval path.';
revoke all on function public.evaluate_order_risk(uuid) from public;
grant execute on function public.evaluate_order_risk(uuid) to authenticated;
grant execute on function public.evaluate_order_risk(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2. AFTER INSERT — create risk_events per reason in same transaction
-- ---------------------------------------------------------------------------
create or replace function public.create_risk_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
  v_score int := coalesce(new.risk_score, 0);
  v_level text := new.risk_level;
  v_action text := new.risk_action;
  v_reasons jsonb := coalesce(new.risk_reasons, '[]'::jsonb);
begin
  if new.phone is null then return new; end if;
  -- For each reason in risk_reasons, create an event if not already present
  -- (dedup per order_id+event_type). Metadata carries score+full reasons.
  if jsonb_typeof(v_reasons) = 'array' then
    for v_reason in select jsonb_array_elements_text(v_reasons) loop
      if v_reason is null or v_reason = '' then continue; end if;
      if not exists (select 1 from public.risk_events where order_id = new.id and event_type = v_reason) then
        insert into public.risk_events (phone, order_id, device_id, event_type, metadata)
        values (
          new.phone,
          new.id,
          new.device_id,
          v_reason,
          jsonb_build_object('score', v_score, 'level', v_level, 'action', v_action, 'reasons', v_reasons)
        );
      end if;
    end loop;
  end if;

  -- Also emit a summary event for high-risk orders that have multiple reasons
  -- (optional, but helpful for queue filtering). Only if risk_action is rejected/needs_verification
  -- and at least one reason exists — deduplicate against summary type.
  -- Keep as RISK_EVALUATED for audit if no dedicated reason (never happens because reasons mirrors score>0)
  if new.risk_action in ('needs_verification','rejected') and jsonb_array_length(v_reasons) > 0 then
    if not exists (select 1 from public.risk_events where order_id=new.id and event_type='RISK_EVALUATED') then
      insert into public.risk_events (phone, order_id, device_id, event_type, metadata)
      values (
        new.phone,
        new.id,
        new.device_id,
        'RISK_EVALUATED',
        jsonb_build_object('score', v_score, 'level', v_level, 'action', v_action, 'reasons', v_reasons)
      );
    end if;
  end if;

  return new;
end;
$$;

comment on function public.create_risk_events() is 'RISK-04 AFTER INSERT: creates risk_events per risk_reasons entry (NEW_CUSTOMER, LARGE_ORDER, RAPID_ORDERS, MULTIPLE_ACCOUNTS_DEVICE etc.) with metadata {score, reasons}. Dedup per (order_id, event_type). Runs in same transaction as order creation.';

drop trigger if exists trg_create_risk_events on public.orders;
drop trigger if exists trg_risk_events on public.orders;
create trigger trg_create_risk_events
  after insert on public.orders
  for each row execute function public.create_risk_events();

-- Ensure AFTER INSERT ordering: credit, risk_events, device tracking all AFTER.
-- Alphabetical: trg_create_risk_events (c), trg_credit_new_order (c r -> actually credit is trg_credit_new_order, create is trg_create..., credit sorts after create? c r e vs c r a? Let's keep explicit suffix ordering:
-- trg_after_create_risk_events, trg_after_credit, trg_track_device
-- For now keep alphabetical as is; Postgres order is alphabetical so create (create) < credit (credit)? Actually 'create' (c r e a) vs 'credit' (c r e d): 'create' < 'credit' (a < d), so risk_events fires before credit. That's fine; loyalty credit should run after risk flag is set (risk already in NEW before insert, so order doesn't matter — risk_action already in row).
-- We'll rename to enforce risk_events before credit before device.
drop trigger if exists trg_credit_new_order on public.orders;
drop trigger if exists trg_track_device_and_address on public.orders;

-- Recreate AFTER triggers in desired alphabetical order:
--   trg_a_after_create_risk_events
--   trg_b_after_credit_new_order
--   trg_c_after_track_device
-- But keep backwards compat names as aliases? We'll use new alphabetical names and keep old names dropped.
create trigger trg_b_after_credit_new_order
  after insert on public.orders
  for each row when (new.status = 'new' and (new.risk_action is null or new.risk_action != 'needs_verification'))
  execute function public.credit_new_order();

create trigger trg_c_after_track_device
  after insert on public.orders
  for each row execute function public.track_device_and_address();

-- Keep the risk_events trigger as a_ so it fires first
drop trigger if exists trg_create_risk_events on public.orders;
create trigger trg_a_after_create_risk_events
  after insert on public.orders
  for each row execute function public.create_risk_events();

-- ---------------------------------------------------------------------------
-- 3. AFTER UPDATE OF risk_action — credit on verification approval
-- When risk_action flips from needs_verification → approved, idempotently credit loyalty
-- (processed_orders guard handles double-credit). This covers RISK-04 spec:
-- "on post-verification approval, idempotent credit fires (via markProcessed guard)".
-- ---------------------------------------------------------------------------
create or replace function public.credit_on_verification_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ls_row public.loyalty_state;
  ls jsonb;
  redeemed int := 0;
  redeemed_type text := null;
  cost_expected int;
  mult numeric := 1.0;
  dbl boolean := false;
  earned int;
begin
  if old.risk_action = 'needs_verification' and new.risk_action = 'approved' and new.status = 'new' then
    -- Same body as credit_new_order but for an existing order that was held
    select ls2.* into ls_row
      from loyalty_state ls2
      join customers c on c.phone = ls2.phone
     where c.google_user_id = new.google_user_id
     for update of ls2;

    if ls_row is null then return new; end if;
    if ls_row.processed_orders ? new.id::text then return new; end if;

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

    mult := coalesce((select value::text::numeric from app_config where key = 'dine_in_multiplier'), 1.0);
    if new.mode <> 'dine_in' then mult := 1.0; end if;

    dbl := ls_row.double_next_order
        or exists (select 1 from campaigns
                    where kind = 'double_points' and active
                      and (starts_at is null or starts_at <= now())
                      and (ends_at   is null or ends_at   >= now()));

    earned := public.round_half_up(coalesce(new.subtotal, 0)::numeric / 10.0 * mult * case when dbl then 2 else 1 end);

    ls := to_jsonb(ls_row);
    if coalesce(new.subtotal, 0) >= coalesce((select value::text::int from app_config where key = 'stamp_min_spend'), 50) then
      ls := public.apply_stamps(ls, 1);
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
        select coalesce(jsonb_agg(elem), '[]'::jsonb) from (
          select elem from jsonb_array_elements(jsonb_build_array(new.id::text) || coalesce(l.processed_orders, '[]'::jsonb)) with ordinality t(elem, ord) where ord <= 100
        ) s
      ),
      updated_at        = now()
    where l.phone = ls_row.phone;

    insert into order_events(order_id, status, actor, at)
    values (new.id, 'new', 'system:loyalty:verification_approved', now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_credit_on_verification_approval on public.orders;
create trigger trg_credit_on_verification_approval
  after update of risk_action on public.orders
  for each row execute function public.credit_on_verification_approval();

-- ---------------------------------------------------------------------------
-- 4. Dispatch gate: patch orders_guard_update (BEFORE UPDATE) + transition_order RPC
-- Block any order with risk_action='needs_verification' from progressing to
-- accepted/in_prep/ready/out_for_delivery/done until a confirmed verification_requests row exists.
-- Raise P0001 (gate) so client can differentiate from 42501 RLS.
-- ---------------------------------------------------------------------------
create or replace function public.orders_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  v_has_verification bool := false;
begin
  select p.role into actor_role from public.profiles p where p.user_id = auth.uid();

  if actor_role is null then
    raise exception 'orders: no profile for caller' using errcode = '42501';
  end if;

  -- Money/items/identity are immutable post-insert except to admins.
  if actor_role <> 'admin' then
    if new.subtotal       is distinct from old.subtotal
    or new.delivery_fee   is distinct from old.delivery_fee
    or new.total          is distinct from old.total
    or new.items          is distinct from old.items
    or new.phone          is distinct from old.phone
    or new.google_user_id is distinct from old.google_user_id then
      raise exception 'orders: immutable columns changed' using errcode = '42501';
    end if;
    -- Risk substrate: only admin (via SECURITY DEFINER RPC/trigger) may mutate risk_*
    if new.risk_score        is distinct from old.risk_score
    or new.risk_level        is distinct from old.risk_level
    or new.risk_action       is distinct from old.risk_action
    or new.risk_reasons      is distinct from old.risk_reasons
    or new.risk_evaluated_at is distinct from old.risk_evaluated_at then
      raise exception 'orders: risk columns are server-authoritative' using errcode = '42501';
    end if;
  end if;

  -- RISK-04 dispatch gate: needs_verification blocks forward progression
  -- Admin bypasses gate implicitly via SECURITY DEFINER verification approve path
  -- which flips risk_action to approved before status advance; direct admin status
  -- updates while still needs_verification are still blocked unless verification exists.
  if old.risk_action = 'needs_verification'
     and new.status is distinct from old.status
     and new.status in ('accepted','in_prep','ready','out_for_delivery','done') then
    -- Check for confirmed verification (SECURITY DEFINER sees all)
    select exists (
      select 1 from public.verification_requests
       where order_id = new.id
         and status = 'confirmed'
    ) into v_has_verification;
    if not v_has_verification then
      raise exception 'needs verification' using errcode = 'P0001';
    end if;
  end if;

  if actor_role = 'driver' then
    if new.status <> 'done'
    or old.status <> 'out_for_delivery'
    or public.tg_n_cols_changed('status') = false then
      raise exception 'orders: driver may only mark out_for_delivery -> done'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- staff / admin fall through: full status vocabulary allowed (but gate above already checked).
  return new;
end;
$$;

drop trigger if exists trg_orders_guard on public.orders;
create trigger trg_orders_guard
  before update on public.orders
  for each row execute function public.orders_guard_update();

-- ---------------------------------------------------------------------------
-- 5. Patch transition_order RPC with same gate (staff/driver/admin path)
-- ---------------------------------------------------------------------------
create or replace function public.transition_order(
  p_order_id uuid,
  p_status text,
  p_reject_reason text default null,
  p_assigned_driver uuid default null,
  p_actor text default 'staff'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_role boolean;
  v_risk_action text;
  v_has_verification boolean := false;
begin
  v_has_role := public.has_any_role(array['staff','driver','admin']::text[]);
  if not v_has_role then
    raise exception 'transition_order: insufficient role' using errcode = '42501';
  end if;

  if p_status not in ('new','accepted','in_prep','ready','out_for_delivery','done','cancelled') then
    raise exception 'transition_order: invalid status %', p_status using errcode = '22023';
  end if;

  -- RISK-04 gate: fetch current risk_action for this order
  select risk_action into v_risk_action from public.orders where id = p_order_id;
  if v_risk_action = 'needs_verification'
     and p_status in ('accepted','in_prep','ready','out_for_delivery','done') then
    select exists (
      select 1 from public.verification_requests
       where order_id = p_order_id
         and status = 'confirmed'
    ) into v_has_verification;
    if not v_has_verification then
      raise exception 'needs verification' using errcode = 'P0001';
    end if;
  end if;

  update public.orders
     set status = p_status,
         reject_reason = case when p_status = 'cancelled' then coalesce(p_reject_reason, reject_reason) else reject_reason end,
         assigned_driver = coalesce(p_assigned_driver, assigned_driver),
         updated_at = now()
   where id = p_order_id;

  if not found then
    raise exception 'transition_order: order % not found', p_order_id using errcode = 'P0002';
  end if;

  insert into public.order_events(order_id, status, actor, at)
  values (p_order_id, p_status, coalesce(p_actor, 'staff'), now());
end;
$$;

comment on function public.transition_order(uuid,text,text,uuid,text) is 'Atomic orders.status update + order_events insert for staff/driver (CORRECTNESS-03) + RISK-04 gate: blocks needs_verification until confirmed verification_requests row (P0001).';
revoke all on function public.transition_order(uuid,text,text,uuid,text) from public;
grant execute on function public.transition_order(uuid,text,text,uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Helper RPC to confirm verification (used by RISK-05, but gate lift helper here)
-- Staff/Admin confirms pending request → flips orders.risk_action to approved so
-- dispatch gate allows progression. Called by verification queue UI.
-- Idempotent: second confirm leaves approved and does not re-credit (processed_orders guard).
-- ---------------------------------------------------------------------------
create or replace function public.confirm_verification(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_role boolean;
  v_request_id uuid;
  v_phone text;
begin
  v_has_role := public.has_any_role(array['staff','admin']::text[]);
  if not v_has_role then
    raise exception 'verification: insufficient role' using errcode='42501';
  end if;

  -- Find most recent pending request for this order
  select id, phone into v_request_id, v_phone
    from public.verification_requests
   where order_id = p_order_id
     and status = 'pending'
   order by created_at desc
   limit 1;

  if v_request_id is null then
    -- No pending request but order may still be needs_verification (e.g. legacy)
    -- Allow direct risk_action flip if order exists and is held
    select phone into v_phone from public.orders where id = p_order_id;
    if v_phone is null then
      raise exception 'verification: order % not found', p_order_id using errcode='P0002';
    end if;
  else
    update public.verification_requests
       set status = 'confirmed',
           updated_at = now()
     where id = v_request_id;
  end if;

  -- Lift gate
  update public.orders
     set risk_action = 'approved',
         risk_level = 'low',
         risk_evaluated_at = now()
   where id = p_order_id
     and risk_action = 'needs_verification';

  -- Audit: risk_events + staff_log
  if found then
    insert into public.risk_events (phone, order_id, event_type, metadata)
    values (v_phone, p_order_id, 'VERIFICATION_CONFIRMED', jsonb_build_object('order_id', p_order_id, 'by', auth.uid()::text));

    insert into public.staff_log (actor, action, target_phone, detail)
    values (auth.uid()::text, 'risk_verification_decision', v_phone, jsonb_build_object('order_id', p_order_id, 'decision', 'confirmed'));
  end if;
end;
$$;

comment on function public.confirm_verification(uuid) is 'RISK-04 helper: staff/admin confirms pending verification → flips orders.risk_action to approved (lifts dispatch gate) and emits risk_events + staff_log. SECURITY DEFINER.';
revoke all on function public.confirm_verification(uuid) from public;
grant execute on function public.confirm_verification(uuid) to authenticated;

create or replace function public.reject_verification(p_order_id uuid, p_reason text default 'verification_rejected')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_role boolean;
  v_request_id uuid;
  v_phone text;
begin
  v_has_role := public.has_any_role(array['staff','admin']::text[]);
  if not v_has_role then
    raise exception 'verification: insufficient role' using errcode='42501';
  end if;

  select id, phone into v_request_id, v_phone
    from public.verification_requests
   where order_id = p_order_id
     and status = 'pending'
   order by created_at desc
   limit 1;

  if v_request_id is not null then
    update public.verification_requests
       set status = 'rejected',
           updated_at = now()
     where id = v_request_id;
  else
    select phone into v_phone from public.orders where id = p_order_id;
  end if;

  update public.orders
     set status = 'cancelled',
         reject_reason = coalesce(p_reason, 'verification_rejected'),
         updated_at = now()
   where id = p_order_id;

  insert into public.risk_events (phone, order_id, event_type, metadata)
  values (v_phone, p_order_id, 'VERIFICATION_REJECTED', jsonb_build_object('order_id', p_order_id, 'by', auth.uid()::text, 'reason', p_reason));

  insert into public.staff_log (actor, action, target_phone, detail)
  values (auth.uid()::text, 'risk_verification_decision', v_phone, jsonb_build_object('order_id', p_order_id, 'decision', 'rejected', 'reason', p_reason));
end;
$$;

comment on function public.reject_verification(uuid,text) is 'RISK-04 helper: staff/admin rejects pending verification → cancels order with reject_reason and emits ledger. SECURITY DEFINER.';
revoke all on function public.reject_verification(uuid,text) from public;
grant execute on function public.reject_verification(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Grants for new sequences / tables (defense in depth)
-- ---------------------------------------------------------------------------
revoke all on table public.verification_requests from public, anon, authenticated;
grant select on table public.verification_requests to authenticated;
grant all on table public.verification_requests to service_role;
revoke all on sequence public.verification_requests_id_seq from public, anon, authenticated;
grant usage, select on sequence public.verification_requests_id_seq to authenticated;
grant all on sequence public.verification_requests_id_seq to service_role;

-- Ensure orders idempotency index is covered by grants (no extra table grants needed)
-- risk_events sequence already hardened in 0020.

commit;
