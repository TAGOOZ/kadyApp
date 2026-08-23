-- 0002_driver_rls.sql — driver role access fixes surfaced by slice #014.
-- Run in Supabase SQL editor after 0001_init.sql.

-- Drivers may read customer contact basics for their deliveries.
drop policy if exists "driver_read_customers" on customers;
create policy "driver_read_customers"
  on customers for select
  using (exists (
    select 1 from profiles p
    where p.user_id = auth.uid() and p.role in ('staff','driver','admin')
  ));

-- Drivers may append their own order events (accepted / picked_up / delivered).
drop policy if exists "driver_insert_order_events" on order_events;
create policy "driver_insert_order_events"
  on order_events for insert
  with check (exists (
    select 1 from profiles p
    where p.user_id = auth.uid() and p.role in ('staff','driver','admin')
  ));
