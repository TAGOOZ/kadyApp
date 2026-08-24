-- 0006_driver_assigned_filter.sql — P1-1 driver assigned_driver ownership (TDD).
-- Restricts driver reads to only rows where assigned_driver = auth.uid().
-- Staff/admin keep full read; driver history and realtime feed are now filtered
-- both at RLS and at the Supabase stream .eq('assigned_driver', uid) layer
-- (lib/data/repos/driver_orders_repository.dart). Also allows driver to
-- read addresses for their deliveries (previously staff/admin only).

-- 1. Replace the broad staff/driver/admin read with split policies.
drop policy if exists "orders_staff_driver_admin_read" on public.orders;

create policy "orders_staff_admin_read"
  on public.orders for select
  using (public.has_any_role(array['staff', 'admin']::text[]));

drop policy if exists "orders_driver_assigned_read" on public.orders;
create policy "orders_driver_assigned_read"
  on public.orders for select
  using (
    public.has_any_role(array['driver']::text[])
    and assigned_driver = auth.uid()
  );

-- 2. Allow driver to read addresses for their assigned deliveries.
--    staff/admin already have `addresses_staff_admin_read`; add driver.
drop policy if exists "driver_read_addresses" on public.addresses;
create policy "driver_read_addresses"
  on public.addresses for select
  using (public.has_any_role(array['staff', 'driver', 'admin']::text[]));

-- Verification (run in SQL editor):
--   select policyname, cmd, permissive, roles, qual
--   from pg_policies where tablename = 'orders' and policyname like 'orders_%';
--   -- expect orders_staff_admin_read and orders_driver_assigned_read
--   select * from pg_policies where tablename = 'addresses' and policyname = 'driver_read_addresses';
