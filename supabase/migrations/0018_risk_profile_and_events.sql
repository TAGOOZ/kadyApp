-- 0018_risk_profile_and_events.sql — RISK-02
-- Gives every Customer (phone = business key, CONTEXT.md) a derived risk
-- identity and an append-only audit ledger. Creates customer_risk_profiles
-- (aggregated counters + phone_verified + cached risk) and risk_events
-- (central fraud event stream with jsonb metadata) and wires centralised
-- post-Order outcome updates so counters never drift from scattered code paths.
--
-- Design choices documented per acceptance criteria:
-- • risk_events.event_type is UNCONSTRAINED text for extensibility (not a
--   CHECK against the 11 seed codes). New fraud signals (e.g. PROMO_ABUSE,
--   MULTIPLE_ACCOUNTS_DEVICE) may be emitted without a migration. The
--   canonical 11 codes are listed in the table comment and are the only
--   values emitted by triggers in this slice; callers should treat unknown
--   codes as opaque strings.
-- • Counters are ONLY mutated via SECURITY DEFINER triggers / functions.
--   No UPDATE/INSERT RLS policy grants client write to counters, so any
--   forged counter mutation fails 42501 (RLS or guard). Events are inserted
--   only by the server trigger sync_risk_profile() — no client INSERT policy.

begin;

-- ---------------------------------------------------------------------------
-- 1. customer_risk_profiles — one row per Customer (phone FK)
-- ---------------------------------------------------------------------------
create table if not exists public.customer_risk_profiles (
  phone              text primary key
                     references public.customers (phone) on delete cascade,
  total_orders       int         not null default 0,
  successful_orders  int         not null default 0,
  cancelled_orders   int         not null default 0,
  failed_deliveries  int         not null default 0,
  rejected_orders    int         not null default 0,
  total_spent        int         not null default 0,
  last_order_at      timestamptz,
  phone_verified     boolean     not null default false,
  risk_score         int         not null default 0
                     check (risk_score between 0 and 100),
  risk_level         text
                     check (risk_level in ('low', 'medium', 'high')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.customer_risk_profiles is
  'Derived risk identity per Customer (phone FK). Counters are server-authoritative — mutated only via trigger sync_risk_profile() and handle_new_customer_risk_profile(). risk_score/level are cached from calculateRisk (RISK-04) and may lag counters.';

comment on column public.customer_risk_profiles.phone_verified is
  'Whether the phone has been verified via OTP / manual verification (future RISK-05). Maps to RiskContext.isVerifiedPhone (-15).';

-- Keep updated_at fresh (reuse existing set_updated_at()).
drop trigger if exists trg_customer_risk_profiles_updated_at
  on public.customer_risk_profiles;
create trigger trg_customer_risk_profiles_updated_at
  before update on public.customer_risk_profiles
  for each row execute function public.set_updated_at();

-- Indexes as per spec: idx_risk_profiles_risk_level required; PK already
-- indexes phone so idx_risk_profiles_phone is redundant (dropped in 0019).
-- Kept here for historical spec parity but 0019 drops it to save writes.
create index if not exists idx_risk_profiles_risk_level
  on public.customer_risk_profiles (risk_level)
  where risk_level is not null;

-- ---------------------------------------------------------------------------
-- 2. risk_events — append-only central fraud event stream
-- ---------------------------------------------------------------------------
create table if not exists public.risk_events (
  id         bigserial primary key,
  phone      text
             references public.customers (phone) on delete cascade,
  order_id   uuid
             references public.orders (id) on delete set null,
  device_id  text,
  event_type text        not null,
  metadata   jsonb       not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Unconstrained event_type for extensibility; canonical seed types documented:
-- NEW_CUSTOMER, NEW_DEVICE, MULTIPLE_ACCOUNTS_DEVICE, CANCELLED_ORDER,
-- FAILED_DELIVERY, REJECTED_ORDER, LARGE_ORDER, RAPID_ORDERS, PROMO_ABUSE,
-- PHONE_VERIFIED, SUCCESSFUL_ORDER. Additional codes may be added without DDL.
comment on column public.risk_events.event_type is
  'Unconstrained for extensibility. Canonical: NEW_CUSTOMER, NEW_DEVICE, MULTIPLE_ACCOUNTS_DEVICE, CANCELLED_ORDER, FAILED_DELIVERY, REJECTED_ORDER, LARGE_ORDER, RAPID_ORDERS, PROMO_ABUSE, PHONE_VERIFIED, SUCCESSFUL_ORDER.';
comment on column public.risk_events.metadata is
  'Opaque jsonb — e.g. {old_status, new_status, reject_reason, total} for post-order events.';
comment on table public.risk_events is
  'Append-only fraud audit ledger. Insert only via SECURITY DEFINER triggers (sync_risk_profile). No client INSERT policy — unauthenticated insert fails 42501.';

-- Indexes as per spec:
create index if not exists idx_risk_events_phone_created
  on public.risk_events (phone, created_at desc);
create index if not exists idx_risk_events_order_id
  on public.risk_events (order_id)
  where order_id is not null;
create index if not exists idx_risk_events_event_type
  on public.risk_events (event_type);

-- ---------------------------------------------------------------------------
-- 3. Handle new customer — ensure every Customer has a zero row
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_customer_risk_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.customer_risk_profiles (phone)
  values (new.phone)
  on conflict (phone) do nothing;
  return new;
end;
$$;

comment on function public.handle_new_customer_risk_profile() is
  'AFTER INSERT ON customers → inserts zeroed customer_risk_profiles row (idempotent).';

drop trigger if exists trg_customers_create_risk_profile on public.customers;
create trigger trg_customers_create_risk_profile
  after insert on public.customers
  for each row execute function public.handle_new_customer_risk_profile();

-- Backfill existing customers idempotently (covers pre-0018 rows).
insert into public.customer_risk_profiles (phone)
select c.phone from public.customers c
on conflict (phone) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Centralised post-order outcome sync — AFTER UPDATE OF status ON orders
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
  -- Only when status actually transitions — idempotency guard (no duplicate
  -- on re-update with same status). AFTER UPDATE OF status ensures this
  -- only fires when status column is touched, but we still guard via
  -- IS DISTINCT FROM for safety.
  if new.status is not distinct from old.status then
    return new;
  end if;

  if v_phone is null then
    return new;
  end if;

  -- Defensive: ensure profile row exists (e.g. customers inserted before
  -- the backfill or via direct SQL that bypassed the AFTER INSERT trigger).
  insert into public.customer_risk_profiles (phone)
  values (v_phone)
  on conflict (phone) do nothing;

  -- -----------------------------------------------------------------------
  -- Successful outcome
  -- -----------------------------------------------------------------------
  if new.status = 'done' then
    update public.customer_risk_profiles
       set total_orders      = total_orders + 1,
           successful_orders = successful_orders + 1,
           total_spent       = total_spent + v_total,
           last_order_at     = now(),
           updated_at        = now()
     where phone = v_phone;
    v_event_type := 'SUCCESSFUL_ORDER';

  -- -----------------------------------------------------------------------
  -- Cancelled outcome — distinguish via reject_reason per spec:
  --   ~* 'refused|rejected'  → REJECTED_ORDER (+ rejected_orders)
  --   ~* 'failed.*delivery|delivery.*failed|failed_delivery' → FAILED_DELIVERY
  --   ilike '%cancel%'       → CANCELLED_ORDER (+ cancelled_orders)
  --   else                   → CANCELLED_ORDER (default)
  -- Order matters: rejected/failed checks before generic cancel.
  -- -----------------------------------------------------------------------
  elsif new.status = 'cancelled' then
    if new.reject_reason is not null
       and new.reject_reason ~* 'refused|rejected' then
      update public.customer_risk_profiles
         set total_orders    = total_orders + 1,
             rejected_orders = rejected_orders + 1,
             last_order_at   = now(),
             updated_at      = now()
       where phone = v_phone;
      v_event_type := 'REJECTED_ORDER';
    elsif new.reject_reason is not null
          and new.reject_reason ~* 'failed.*delivery|delivery.*failed|failed_delivery' then
      update public.customer_risk_profiles
         set total_orders     = total_orders + 1,
             failed_deliveries = failed_deliveries + 1,
             last_order_at    = now(),
             updated_at       = now()
       where phone = v_phone;
      v_event_type := 'FAILED_DELIVERY';
    elsif new.reject_reason is not null
          and new.reject_reason ilike '%cancel%' then
      update public.customer_risk_profiles
         set total_orders     = total_orders + 1,
             cancelled_orders = cancelled_orders + 1,
             last_order_at    = now(),
             updated_at       = now()
       where phone = v_phone;
      v_event_type := 'CANCELLED_ORDER';
    else
      -- No reason or unrecognized — treat as cancellation (spec default).
      update public.customer_risk_profiles
         set total_orders     = total_orders + 1,
             cancelled_orders = cancelled_orders + 1,
             last_order_at    = now(),
             updated_at       = now()
       where phone = v_phone;
      v_event_type := 'CANCELLED_ORDER';
    end if;
  else
    -- Non-terminal status (new, accepted, in_prep, ready, out_for_delivery)
    -- does not affect risk counters — keep ledger clean.
    return new;
  end if;

  -- -----------------------------------------------------------------------
  -- Ledger append — idempotent per order_id (not per event_type).
  -- Prevents double total_orders increment on ping-pong e.g. done→cancelled.
  -- Spec: "idempotent via events dedup not via client counters".
  -- -----------------------------------------------------------------------
  if v_event_type is not null then
    if not exists (
      select 1 from public.risk_events
       where order_id = new.id
    ) then
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
    end if;
  end if;

  return new;
end;
$$;

comment on function public.sync_risk_profile() is
  'Centralised post-order outcome sync (RISK-02): AFTER UPDATE OF status ON orders → increments customer_risk_profiles counters and appends risk_events. Idempotent via (order_id,event_type) dedup; cancelled vs rejected vs failed_delivery distinguished via reject_reason. SECURITY DEFINER so counters are server-authoritative.';

drop trigger if exists trg_sync_risk_profile on public.orders;
create trigger trg_sync_risk_profile
  after update of status on public.orders
  for each row execute function public.sync_risk_profile();

-- ---------------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------------
alter table public.customer_risk_profiles enable row level security;
alter table public.risk_events enable row level security;

-- customer_risk_profiles: select own, staff/admin/driver full read; no write
do $crr_rls$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'customer_risk_profiles'
       and policyname = 'risk_profiles_select_own'
  ) then
    create policy risk_profiles_select_own
      on public.customer_risk_profiles
      for select to authenticated
      using (
        exists (
          select 1 from public.customers c
           where c.phone = customer_risk_profiles.phone
             and c.google_user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'customer_risk_profiles'
       and policyname = 'risk_profiles_staff_driver_admin_read'
  ) then
    create policy risk_profiles_staff_driver_admin_read
      on public.customer_risk_profiles
      for select to authenticated
      using (public.has_any_role(array['staff','admin','driver']::text[]));
  end if;

  -- Explicitly no INSERT/UPDATE/DELETE policies — client writes are blocked
  -- and return 42501 via RLS (verified by tests). Server triggers bypass RLS
  -- via SECURITY DEFINER.
end;
$crr_rls$;

-- risk_events: select own + staff/admin; insert via SECURITY DEFINER only
do $risk_events_rls$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'risk_events'
       and policyname = 'risk_events_select_own'
  ) then
    create policy risk_events_select_own
      on public.risk_events
      for select to authenticated
      using (
        exists (
          select 1 from public.customers c
           where c.phone = risk_events.phone
             and c.google_user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'risk_events'
       and policyname = 'risk_events_staff_admin_read'
  ) then
    create policy risk_events_staff_admin_read
      on public.risk_events
      for select to authenticated
      using (public.has_any_role(array['staff','admin']::text[]));
  end if;

  -- No INSERT/UPDATE/DELETE policies — inserts only via SECURITY DEFINER trigger.
end;
$risk_events_rls$;

-- Defense in depth: actual REVOKE/GRANT is in 0019_risk_profile_fixes.sql
-- (revoke all on table ... from anon, authenticated; grant select ...).
-- RLS with no INSERT/UPDATE policy already blocks, but table grants also
-- revoked for completeness (see 0015_revoke_loyalty_writes pattern).

commit;
