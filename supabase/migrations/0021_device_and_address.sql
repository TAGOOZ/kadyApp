-- 0021_device_and_address.sql — RISK-03
-- Implements extrinsic risk signals: lightweight device tracking (stable
-- app-level device_id per install, not browser fingerprinting) and
-- delivery-address enrichment (coords + history). Both feed the pure engine
-- as signals, not proof — shared device/address raises score but never
-- auto-rejects alone, matching the Mahmoudia single-café reality (families
-- share devices/addresses).
--
-- Naming note: issue #48 spec calls this 0019_device_and_address.sql, but
-- migrations 0019_risk_profile_fixes.sql and 0020_risk_events_sequence_hardening.sql
-- already occupy 0019/0020 live, so this is 0021. Content matches 0019 spec.
--
-- Client device_id: lib/core/device/device_id_provider.dart →
-- SharedPreferences key `risk.device_id`, UUID v4 once per install, exposed
-- via Provider<String>. Sent on every OrdersRepo.placeOrder as `orders.device_id`
-- (new nullable column) — see header doc on column choice. Value treated as
-- untrusted signal server-side; server hook upserts customer_devices and emits
-- risk_events.

begin;

-- ---------------------------------------------------------------------------
-- 1. customer_devices — lightweight device tracking per Customer
-- ---------------------------------------------------------------------------
create table if not exists public.customer_devices (
  id            uuid primary key default gen_random_uuid(),
  phone         text not null references public.customers (phone) on delete cascade,
  device_id     text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  unique (phone, device_id)
);

comment on table public.customer_devices is 'Lightweight device tracking (RISK-03): stable app-level device_id per install (risk.device_id). Shared device_id across phones raises signal but never auto-rejects (families share devices). Server upserts via BEFORE INSERT trigger on orders.';
comment on column public.customer_devices.device_id is 'Untrusted client signal — UUID v4 from SharedPreferences risk.device_id; server verifies by counting distinct phones per device_id.';
comment on column public.customer_devices.first_seen_at is 'First time this phone used this device_id (UTC, ADR-0009).';
comment on column public.customer_devices.last_seen_at is 'Last time this phone used this device_id — updated on every order from same device.';

create index if not exists idx_customer_devices_device_id on public.customer_devices (device_id);
create index if not exists idx_customer_devices_phone on public.customer_devices (phone);

-- ---------------------------------------------------------------------------
-- 2. addresses enrichment — coords + updated_at
-- ---------------------------------------------------------------------------
alter table public.addresses
  add column if not exists latitude double precision;
alter table public.addresses
  add column if not exists longitude double precision;
alter table public.addresses
  add column if not exists updated_at timestamptz not null default now();

-- Backfill: existing addresses.updated_at = created_at (spec)
-- Single pass: set updated_at to created_at for all existing rows.
update public.addresses
   set updated_at = created_at
 where created_at is not null;

comment on column public.addresses.latitude is 'Nullable WGS84 latitude (RISK-03 address enrichment, never required).';
comment on column public.addresses.longitude is 'Nullable WGS84 longitude.';
comment on column public.addresses.updated_at is 'Last update time (UTC, ADR-0009) — kept fresh by set_updated_at() trigger.';

-- Keep updated_at fresh (reuse existing set_updated_at() with search_path hardened in 0019)
drop trigger if exists trg_addresses_updated_at on public.addresses;
create trigger trg_addresses_updated_at
  before update on public.addresses
  for each row execute function public.set_updated_at();

-- Indexes as per spec: (phone) already exists via idx_addresses_phone (0001), but
-- ensure it exists; (latitude, longitude) for future area check.
create index if not exists idx_addresses_phone on public.addresses (phone);
create index if not exists idx_addresses_coords on public.addresses (latitude, longitude);
-- Optional GiST for geo proximity (future area check) — if btree_gist not available, skip
-- We keep btree above; GiST is commented for future:
-- create extension if not exists btree_gist;
-- create index if not exists idx_addresses_coords_gist on public.addresses using gist (latitude, longitude);

-- ---------------------------------------------------------------------------
-- 3. orders.device_id — nullable untrusted device signal per order
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists device_id text;

comment on column public.orders.device_id is 'Untrusted client device signal (risk.device_id UUID v4). Nullable, never required; server hook treats as signal not proof. Mirrors lib/core/device/device_id_provider.dart.';
create index if not exists idx_orders_device_id on public.orders (device_id) where device_id is not null;
create index if not exists idx_orders_address_id on public.orders (address_id) where address_id is not null;

-- ---------------------------------------------------------------------------
-- 4. RLS: customer_devices + addresses (update + new columns)
-- ---------------------------------------------------------------------------
alter table public.customer_devices enable row level security;

do $cust_dev_rls$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'customer_devices'
       and policyname = 'customer_devices_select_own'
  ) then
    create policy customer_devices_select_own
      on public.customer_devices
      for select to authenticated
      using (
        exists (
          select 1 from public.customers c
           where c.phone = customer_devices.phone
             and c.google_user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'customer_devices'
       and policyname = 'customer_devices_insert_own'
  ) then
    create policy customer_devices_insert_own
      on public.customer_devices
      for insert to authenticated
      with check (
        exists (
          select 1 from public.customers c
           where c.phone = customer_devices.phone
             and c.google_user_id = auth.uid()
        )
      );
  end if;

  -- Update own row (last_seen_at refresh) — limited to own phone
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'customer_devices'
       and policyname = 'customer_devices_update_own'
  ) then
    create policy customer_devices_update_own
      on public.customer_devices
      for update to authenticated
      using (
        exists (
          select 1 from public.customers c
           where c.phone = customer_devices.phone
             and c.google_user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.customers c
           where c.phone = customer_devices.phone
             and c.google_user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'customer_devices'
       and policyname = 'customer_devices_staff_admin_read'
  ) then
    create policy customer_devices_staff_admin_read
      on public.customer_devices
      for select to authenticated
      using (public.has_any_role(array['staff','admin']::text[]));
  end if;

  -- No delete policy for clients — server cascade only.
end;
$cust_dev_rls$;

-- Addresses RLS: existing policies already allow own-row select/insert/update/delete
-- and staff/admin read. New columns are writable via same own-row update policy
-- (no extra policy needed). Document and ensure staff/admin read still covers coords.
-- For completeness, recreate addresses update own check to be explicit (idempotent).
do $addr_rls$
begin
  -- Existing policies from 0001 already handle own-row; we just ensure they remain.
  -- Add driver read for addresses via assigned deliveries (already in 0006)
  -- — no change needed. This block is no-op if policies exist.
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'addresses'
       and policyname = 'addresses_staff_admin_read'
  ) then
    create policy addresses_staff_admin_read on public.addresses
      for select to authenticated
      using (public.has_any_role(array['staff','admin']::text[]));
  end if;
end;
$addr_rls$;

-- ---------------------------------------------------------------------------
-- 5. risk_rules — seed MULTIPLE_ACCOUNTS_DEVICE (+10) for signal-not-proof
--    plus optional address signals (tunable, disabled-flag honoured by Dart engine)
-- ---------------------------------------------------------------------------
insert into public.risk_rules (rule_code, description, score, enabled) values
  ('MULTIPLE_ACCOUNTS_DEVICE', 'Same device used by 2+ phones (signal, not proof)', 10, true)
on conflict (rule_code) do nothing;

-- Optional: address-based signals for future RISK-03 enrichment (kept disabled
-- by default so engine tests stay deterministic; enable via admin when geo checks land)
insert into public.risk_rules (rule_code, description, score, enabled) values
  ('MULTIPLE_ACCOUNTS_ADDRESS', 'Same address used by 2+ phones (signal, not proof)', 10, false),
  ('ADDRESS_HIGH_FAILURE', 'Address with 3+ failed/cancelled deliveries', 15, false)
on conflict (rule_code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Server hook — AFTER INSERT ON orders: upsert customer_devices + risk_events
--    (AFTER to avoid FK violation on risk_events.order_id; BEFORE would fail
--    because parent row not yet visible for FK check)
-- ---------------------------------------------------------------------------
create or replace function public.track_device_and_address()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_first_device boolean := false;
  v_device_phone_count int := 0;
  v_orders_at_address int := 0;
begin
  if new.phone is not null and new.device_id is not null and new.device_id <> '' then
    insert into public.customer_devices (phone, device_id, first_seen_at, last_seen_at)
    values (new.phone, new.device_id, now(), now())
    on conflict (phone, device_id) do update set last_seen_at = now()
    returning (xmax = 0) into v_is_first_device;

    select count(distinct phone) into v_device_phone_count
      from public.customer_devices
     where device_id = new.device_id;

    if v_is_first_device then
      insert into public.risk_events (phone, order_id, device_id, event_type, metadata)
      values (new.phone, new.id, new.device_id, 'NEW_DEVICE', jsonb_build_object('device_id', new.device_id, 'first_seen', true));
    end if;

    if v_device_phone_count >= 2 then
      if not exists (select 1 from public.risk_events where order_id = new.id and event_type = 'MULTIPLE_ACCOUNTS_DEVICE') then
        insert into public.risk_events (phone, order_id, device_id, event_type, metadata)
        values (new.phone, new.id, new.device_id, 'MULTIPLE_ACCOUNTS_DEVICE', jsonb_build_object('device_id', new.device_id, 'device_phone_count', v_device_phone_count));
      end if;
    end if;
  end if;

  if new.address_id is not null then
    select count(*) into v_orders_at_address from public.orders where address_id = new.address_id;
    -- AFTER INSERT count includes the just-inserted row, so >=2 means prior history exists
    if v_orders_at_address >= 2 then
      insert into public.risk_events (phone, order_id, event_type, metadata)
      values (new.phone, new.id, 'ADDRESS_REUSE', jsonb_build_object('address_id', new.address_id, 'orders_at_address', v_orders_at_address - 1));
    end if;
  end if;

  return new;
end;
$$;

comment on function public.track_device_and_address() is 'RISK-03 AFTER INSERT hook (fixed from BEFORE to avoid FK violation): upserts customer_devices (INSERT … ON CONFLICT DO UPDATE last_seen_at), emits risk_events NEW_DEVICE on first-seen and MULTIPLE_ACCOUNTS_DEVICE when device shared by ≥2 phones. Address reuse emits ADDRESS_REUSE with orders_at_address count. Device/address are signals not proof — never auto-rejects alone. SECURITY DEFINER.';

drop trigger if exists trg_track_device_and_address on public.orders;
create trigger trg_track_device_and_address
  after insert on public.orders
  for each row execute function public.track_device_and_address();

-- ---------------------------------------------------------------------------
-- 7. Hardening: revoke/grant for new table (defense in depth, like 0019)
--    RLS already blocks anon writes, but revoke table grants for completeness.
-- ---------------------------------------------------------------------------
revoke all on table public.customer_devices from public, anon, authenticated;
grant select, insert, update on table public.customer_devices to authenticated;
grant all on table public.customer_devices to service_role;

-- Addresses and orders already have grants; ensure new columns are covered.
-- No additional revoke needed — keep existing grants.

-- Ensure risk_events sequence grants still minimal (0020 hardened)
revoke all on sequence public.risk_events_id_seq from public, anon;
grant usage, select on sequence public.risk_events_id_seq to authenticated;
grant all on sequence public.risk_events_id_seq to service_role;

commit;
