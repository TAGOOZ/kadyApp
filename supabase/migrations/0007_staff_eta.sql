-- 0007_staff_eta.sql — P2 ETA slider (FEATURES §6).
-- Adds `orders.expected_ready_at` for staff to adjust expected-ready time
-- (5–60 min via slider). Staff/admin may PATCH this column via RLS.
-- The board's rolling avgPrepMinutes still uses created_at; expected time
-- is displayed as a Cairo HH:mm chip (Western digits §11.11).

alter table public.orders
  add column if not exists expected_ready_at timestamptz;

comment on column public.orders.expected_ready_at is
  'Staff-adjusted expected ready time (Cairo display via formatExpectedReadyCairo).';

-- Allow staff/admin to update expected_ready_at via the existing
-- orders_status_ops_update policy (has_any_role staff/driver/admin).
-- No new RLS needed — that policy already permits update for those roles.
-- For driver, we keep the same guard; driver may also update if assigned
-- (future hardening can restrict to assigned_driver).

-- Index for potential filtering/sorting by expected time.
create index if not exists idx_orders_expected_ready_at
  on public.orders (expected_ready_at);

-- Verification:
--   select column_name, data_type from information_schema.columns
--   where table_name = 'orders' and column_name = 'expected_ready_at';
--   -- expect timestamptz
