-- 0011_driver_positions.sql — live driver tracking (FEATURES §7).
-- Driver publishes lat/lng per order; customer/staff see via Realtime.
-- Minimal: one row per driver×order, upsert on publish.

create table if not exists public.driver_positions (
  driver_id  uuid not null references auth.users (id) on delete cascade,
  order_id   uuid not null references public.orders (id) on delete cascade,
  lat        double precision not null,
  lng        double precision not null,
  updated_at timestamptz not null default now(),
  primary key (driver_id, order_id)
);

comment on table public.driver_positions is 'Live driver positions per order — driver upserts, customer+staff read (Realtime).';

alter table public.driver_positions enable row level security;

drop policy if exists "driver_positions_driver_write" on public.driver_positions;
create policy "driver_positions_driver_write" on public.driver_positions
  for all to authenticated
  using (driver_id = auth.uid() and public.has_any_role(array['driver']))
  with check (driver_id = auth.uid() and public.has_any_role(array['driver']));

drop policy if exists "driver_positions_customer_staff_read" on public.driver_positions;
create policy "driver_positions_customer_staff_read" on public.driver_positions
  for select to authenticated
  using (
    public.has_any_role(array['staff','admin','driver'])
    or exists (
      select 1 from public.orders o
      where o.id = driver_positions.order_id
        and o.phone = (select phone from public.customers where google_user_id = auth.uid())
    )
  );

-- Helper: is_driver (mirror is_admin/is_staff pattern in 0001)
create or replace function public.is_driver()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'driver');
$$;

-- Realtime: enable publication for driver_positions (if not already).
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'driver_positions') then
    alter publication supabase_realtime add table public.driver_positions;
  end if;
exception when duplicate_object then null;
end $$;

-- Index for order_id lookups.
create index if not exists idx_driver_positions_order on public.driver_positions (order_id);
