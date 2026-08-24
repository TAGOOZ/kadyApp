-- 0008_hours.sql — Admin hours & delivery availability (FEATURES §6).
-- 7-day week: day 0=Saturday (Egyptian week start) … 6=Friday.
-- open/close are wall-clock times (Cairo), null = closed.
create table if not exists public.hours (
  day              int  primary key check (day between 0 and 6),
  open             time,
  close            time,
  delivery_enabled boolean not null default true
);

comment on table public.hours is 'Opening hours & delivery availability per day (FEATURES §6, admin-editable).';
comment on column public.hours.day is '0=Sat,1=Sun,2=Mon,3=Tue,4=Wed,5=Thu,6=Fri';

-- Seed 7 days: 09:00–23:00, delivery enabled.
insert into public.hours (day, open, close, delivery_enabled) values
  (0, '09:00', '23:00', true),
  (1, '09:00', '23:00', true),
  (2, '09:00', '23:00', true),
  (3, '09:00', '23:00', true),
  (4, '09:00', '23:00', true),
  (5, '09:00', '23:00', true),
  (6, '09:00', '23:00', true)
on conflict (day) do nothing;

-- RLS: public read, admin write.
alter table public.hours enable row level security;

drop policy if exists "hours_public_read" on public.hours;
create policy "hours_public_read" on public.hours for select to public using (true);

drop policy if exists "hours_admin_write" on public.hours;
create policy "hours_admin_write" on public.hours for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
