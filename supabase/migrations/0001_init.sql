-- ============================================================================
-- Elkady Café App — initial schema (0001_init.sql)
-- Project: https://zrlhtwmzuljsqricpxbb.supabase.co
--
-- Mirrors the domain language in CONTEXT.md:
--   Customer (phone = business key), Staff, Driver, Admin,
--   Order / Service Mode / Check-in / Visit / Stamp / Points / Tier /
--   Voucher / Game Token.
--
-- Decisions honored (docs/FEATURES.md §11 + ADRs):
--   ADR-0001 Supabase day-one · ADR-0005 storage bucket `menu-photos` ·
--   ADR-0006 realtime on `orders` · ADR-0007 RLS by google_user_id,
--   phone business key · ADR-0009 UTC timestamptz everywhere ·
--   ADR-0010 Edge-Function rate limit params live in app_config.
--
-- Idempotency: create table if not exists, drop-if-exists before triggers,
-- on-conflict-do-nothing seed inserts, DO-block guards around policies and
-- the realtime publication membership. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto; -- gen_random_uuid() fallback for PG < 13

-- ---------------------------------------------------------------------------
-- 1. profiles — role per google account (Customer/Staff/Driver/Admin)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text        not null default 'customer'
             check (role in ('customer', 'staff', 'driver', 'admin')),
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'One row per auth.users id; role drives RLS (customer/staff/driver/admin).';

-- ---------------------------------------------------------------------------
-- 2. Helper functions (security definer — read profiles across RLS)
-- ---------------------------------------------------------------------------
-- NOTE: named app_current_role(), NOT current_role(): CURRENT_ROLE is a fully
-- reserved keyword in PostgreSQL 15 and cannot be used as an unquoted
-- function name. Same intent: resolve the signed-in profile's role.

create or replace function public.app_current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role from public.profiles p where p.user_id = auth.uid();
$$;

create or replace function public.has_any_role(roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid()
      and p.role = any (roles)
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_any_role(array['admin']::text[]);
$$;

-- Shared trigger fn: keep updated_at fresh on customers/menu_items/orders.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, role)
  values (new.id, 'customer')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 3. customers — phone is the canonical Customer business key (ADR-0007)
-- ---------------------------------------------------------------------------
create table if not exists public.customers (
  phone          text primary key check (phone ~ '^\+20[0-9]{10}$'),
  google_user_id uuid        not null unique references auth.users (id) on delete cascade,
  name           text        not null,
  email          text,
  birthdate      date,
  is_student     boolean     default false,
  city           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.customers is 'One Customer per phone number (+20XXXXXXXXXX); Google account linked 1↔1.';

drop trigger if exists trg_customers_updated_at on public.customers;
create trigger trg_customers_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. loyalty_state — Points/Stamps/Tier/Vouchers/Game Tokens per Customer.
--    tier is NOT stored: computed in-app from lifetime_points vs app_config
--    thresholds (tier_silver / tier_gold).
-- ---------------------------------------------------------------------------
create table if not exists public.loyalty_state (
  phone            text primary key references public.customers (phone) on delete cascade,
  points           int         not null default 0,
  lifetime_points  int         not null default 0,
  stamps           int         not null default 0,
  completed_cards  int         not null default 0,
  spinner_tokens   int         not null default 0,
  match_tokens     int         not null default 0,
  scratch_tokens   int         not null default 0,
  double_next_order boolean    not null default false,
  vouchers         jsonb       not null default '[]'::jsonb,
  processed_orders jsonb       not null default '[]'::jsonb,
  updated_at       timestamptz not null default now()
);

comment on column public.loyalty_state.processed_orders is 'Order ids already credited to loyalty — guards double-crediting on retries.';

drop trigger if exists trg_loyalty_state_updated_at on public.loyalty_state;
create trigger trg_loyalty_state_updated_at
before update on public.loyalty_state
for each row execute function public.set_updated_at();

create or replace function public.handle_new_customer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.loyalty_state (phone)
  values (new.phone)
  on conflict (phone) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_on_customer_created on public.customers;
create trigger trg_on_customer_created
after insert on public.customers
for each row execute function public.handle_new_customer();

-- ---------------------------------------------------------------------------
-- 5. menu_categories
-- ---------------------------------------------------------------------------
create table if not exists public.menu_categories (
  id      serial primary key,
  slug    text unique,
  name_ar text,
  name_en text,
  sort    int
);

-- ---------------------------------------------------------------------------
-- 6. menu_items — photos live in the public `menu-photos` bucket (ADR-0005);
--    image_url holds that URL. slug added so seed inserts are idempotent.
-- ---------------------------------------------------------------------------
create table if not exists public.menu_items (
  id           uuid primary key default gen_random_uuid(),
  category_id  int references public.menu_categories (id),
  slug         text        not null unique,
  name_ar      text,
  name_en      text,
  desc_ar      text,
  desc_en      text,
  price_egp    int         not null default 0 check (price_egp >= 0),
  image_url    text,
  is_available boolean     not null default true,
  sort         int,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists trg_menu_items_updated_at on public.menu_items;
create trigger trg_menu_items_updated_at
before update on public.menu_items
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 7. addresses — Delivery targets (Home / Work / Other labels)
-- ---------------------------------------------------------------------------
create table if not exists public.addresses (
  id           uuid primary key default gen_random_uuid(),
  phone        text        not null references public.customers (phone) on delete cascade,
  label        text        not null check (label in ('home', 'work', 'other')),
  address_text text        not null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_addresses_phone on public.addresses (phone);

-- ---------------------------------------------------------------------------
-- 8. orders — one Service Mode per Order; status vocabulary per FEATURES §3.6.
--    display_number filled from order_display_seq (#1000+) when null.
-- ---------------------------------------------------------------------------
create sequence if not exists order_display_seq start 1000;

-- Fills orders.display_number from order_display_seq (#1000+) when null.
create or replace function public.assign_order_display_number()
returns trigger
language plpgsql
as $$
begin
  if new.display_number is null then
    new.display_number := nextval('public.order_display_seq');
  end if;
  return new;
end;
$$;

create table if not exists public.orders (
  id             uuid primary key default gen_random_uuid(),
  display_number int         not null,
  phone          text        references public.customers (phone),
  google_user_id uuid        not null references auth.users (id),
  mode           text        not null check (mode in ('dine_in', 'pickup', 'delivery')),
  status         text        not null default 'new'
                 check (status in ('new','accepted','in_prep','ready','out_for_delivery','done','cancelled')),
  reject_reason  text,
  items          jsonb       not null default '[]'::jsonb,
  subtotal       int,
  delivery_fee   int         not null default 0,
  total          int,
  table_area     text,
  pickup_slot    timestamptz,          -- stored UTC (ADR-0009), Cairo display in-app
  address_id     uuid        references public.addresses (id),
  notes          text,
  points_preview int,
  assigned_driver uuid       references auth.users (id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.orders is 'Live Order flow (new→…→done/cancelled); Realtime enabled (ADR-0006).';

create index if not exists idx_orders_status_created on public.orders (status, created_at desc);
create index if not exists idx_orders_phone on public.orders (phone);
create index if not exists idx_orders_google_user_id on public.orders (google_user_id);
create index if not exists idx_orders_assigned_driver on public.orders (assigned_driver);

drop trigger if exists trg_orders_display_number on public.orders;
create trigger trg_orders_display_number
before insert on public.orders
for each row execute function public.assign_order_display_number();

-- ---------------------------------------------------------------------------
-- 9. order_events — append-only Order history
-- ---------------------------------------------------------------------------
create table if not exists public.order_events (
  id       bigserial primary key,
  order_id uuid        not null references public.orders (id) on delete cascade,
  status   text,
  actor    text,
  at       timestamptz not null default now()
);

create index if not exists idx_order_events_order on public.order_events (order_id, at);

-- ---------------------------------------------------------------------------
-- 10. campaigns — admin-editable windows (double_points/match_night/etc.)
-- ---------------------------------------------------------------------------
create table if not exists public.campaigns (
  id        uuid primary key default gen_random_uuid(),
  kind      text not null check (kind in ('double_points', 'match_night', 'exam_season', 'ramadan')),
  name_ar   text,
  active    boolean not null default false,
  starts_at timestamptz,
  ends_at   timestamptz
);

-- ---------------------------------------------------------------------------
-- 11. app_config — admin-editable loyalty & ops parameters (FEATURES §4).
--     rate_limit_max/rate_limit_window_min feed the ADR-0010 Edge Function
--     stub (function itself deployed separately).
-- ---------------------------------------------------------------------------
create table if not exists public.app_config (
  key   text primary key,
  value jsonb not null
);

insert into public.app_config (key, value) values
  ('points_per_10egp',      '1'::jsonb),
  ('dine_in_multiplier',    '1.1'::jsonb),
  ('stamp_min_spend',       '50'::jsonb),
  ('redeem_min_points',     '200'::jsonb),
  ('reward_topping',        '100'::jsonb),
  ('reward_snack',          '150'::jsonb),
  ('reward_drink',          '200'::jsonb),
  ('delivery_fee',          '15'::jsonb),
  ('group_checkin_count',   '3'::jsonb),
  ('group_bonus_points',    '25'::jsonb),
  ('tier_silver',           '2000'::jsonb),
  ('tier_gold',             '5000'::jsonb),
  ('rate_limit_max',        '5'::jsonb),
  ('rate_limit_window_min', '5'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 12. visits — Check-ins + qualifying Orders feeding Stamps
-- ---------------------------------------------------------------------------
create table if not exists public.visits (
  id         bigserial primary key,
  phone      text        not null references public.customers (phone),
  source     text        not null check (source in ('checkin', 'order')),
  spend_egp  int,
  table_area text,
  staff      text,
  at         timestamptz not null default now()
);

create index if not exists idx_visits_phone_at on public.visits (phone, at desc);

-- ---------------------------------------------------------------------------
-- 13. staff_log — audit trail of Staff/Admin manual actions
-- ---------------------------------------------------------------------------
create table if not exists public.staff_log (
  id           bigserial primary key,
  actor        text,
  action       text,
  target_phone text,
  detail       jsonb,
  at           timestamptz not null default now()
);

create index if not exists idx_staff_log_target on public.staff_log (target_phone, at desc);

-- ---------------------------------------------------------------------------
-- 14. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.customers       enable row level security;
alter table public.loyalty_state   enable row level security;
alter table public.menu_categories enable row level security;
alter table public.menu_items      enable row level security;
alter table public.addresses       enable row level security;
alter table public.orders          enable row level security;
alter table public.order_events    enable row level security;
alter table public.campaigns       enable row level security;
alter table public.app_config      enable row level security;
alter table public.visits          enable row level security;
alter table public.staff_log       enable row level security;

-- PG15 lacks CREATE POLICY IF NOT EXISTS — each policy is created inside a
-- guard so re-running this script is safe.

do $rls$
begin

  -- profiles -----------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_select_own') then
    create policy profiles_select_own on public.profiles
      for select to authenticated
      using (user_id = auth.uid());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_staff_read_all') then
    create policy profiles_staff_read_all on public.profiles
      for select to authenticated
      using (public.has_any_role(array['staff', 'driver', 'admin']::text[]));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_admin_update_roles') then
    create policy profiles_admin_update_roles on public.profiles
      for update to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;

  -- customers ----------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customers' and policyname = 'customers_select_own') then
    create policy customers_select_own on public.customers
      for select to authenticated
      using (google_user_id = auth.uid());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customers' and policyname = 'customers_insert_own') then
    create policy customers_insert_own on public.customers
      for insert to authenticated
      with check (google_user_id = auth.uid());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customers' and policyname = 'customers_update_own') then
    create policy customers_update_own on public.customers
      for update to authenticated
      using (google_user_id = auth.uid())
      with check (google_user_id = auth.uid());
  end if;

  -- staff/admin full read of Customer records (lookup by phone/name)
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customers' and policyname = 'customers_staff_admin_read') then
    create policy customers_staff_admin_read on public.customers
      for select to authenticated
      using (public.has_any_role(array['staff', 'admin']::text[]));
  end if;

  -- loyalty_state --------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'loyalty_state' and policyname = 'loyalty_select_own') then
    create policy loyalty_select_own on public.loyalty_state
      for select to authenticated
      using (exists (
        select 1 from public.customers c
        where c.phone = loyalty_state.phone and c.google_user_id = auth.uid()
      ));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'loyalty_state' and policyname = 'loyalty_update_own') then
    create policy loyalty_update_own on public.loyalty_state
      for update to authenticated
      using (exists (
        select 1 from public.customers c
        where c.phone = loyalty_state.phone and c.google_user_id = auth.uid()
      ))
      with check (exists (
        select 1 from public.customers c
        where c.phone = loyalty_state.phone and c.google_user_id = auth.uid()
      ));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'loyalty_state' and policyname = 'loyalty_staff_admin_read') then
    create policy loyalty_staff_admin_read on public.loyalty_state
      for select to authenticated
      using (public.has_any_role(array['staff', 'admin']::text[]));
  end if;

  -- addresses ------------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'addresses' and policyname = 'addresses_select_own') then
    create policy addresses_select_own on public.addresses
      for select to authenticated
      using (exists (
        select 1 from public.customers c
        where c.phone = addresses.phone and c.google_user_id = auth.uid()
      ));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'addresses' and policyname = 'addresses_insert_own') then
    create policy addresses_insert_own on public.addresses
      for insert to authenticated
      with check (exists (
        select 1 from public.customers c
        where c.phone = addresses.phone and c.google_user_id = auth.uid()
      ));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'addresses' and policyname = 'addresses_update_own') then
    create policy addresses_update_own on public.addresses
      for update to authenticated
      using (exists (
        select 1 from public.customers c
        where c.phone = addresses.phone and c.google_user_id = auth.uid()
      ))
      with check (exists (
        select 1 from public.customers c
        where c.phone = addresses.phone and c.google_user_id = auth.uid()
      ));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'addresses' and policyname = 'addresses_delete_own') then
    create policy addresses_delete_own on public.addresses
      for delete to authenticated
      using (exists (
        select 1 from public.customers c
        where c.phone = addresses.phone and c.google_user_id = auth.uid()
      ));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'addresses' and policyname = 'addresses_staff_admin_read') then
    create policy addresses_staff_admin_read on public.addresses
      for select to authenticated
      using (public.has_any_role(array['staff', 'admin']::text[]));
  end if;

  -- menu_categories / menu_items / app_config / campaigns ----------------------
  -- Public catalog: anon + authenticated read; writes Admin only.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'menu_categories' and policyname = 'menu_categories_public_read') then
    create policy menu_categories_public_read on public.menu_categories
      for select to public
      using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'menu_categories' and policyname = 'menu_categories_admin_write') then
    create policy menu_categories_admin_write on public.menu_categories
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'menu_items' and policyname = 'menu_items_public_read') then
    create policy menu_items_public_read on public.menu_items
      for select to public
      using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'menu_items' and policyname = 'menu_items_admin_write') then
    create policy menu_items_admin_write on public.menu_items
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'app_config' and policyname = 'app_config_public_read') then
    create policy app_config_public_read on public.app_config
      for select to public
      using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'app_config' and policyname = 'app_config_admin_write') then
    create policy app_config_admin_write on public.app_config
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'campaigns' and policyname = 'campaigns_public_read') then
    create policy campaigns_public_read on public.campaigns
      for select to public
      using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'campaigns' and policyname = 'campaigns_admin_write') then
    create policy campaigns_admin_write on public.campaigns
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;

  -- orders ---------------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'orders' and policyname = 'orders_select_own') then
    create policy orders_select_own on public.orders
      for select to authenticated
      using (google_user_id = auth.uid());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'orders' and policyname = 'orders_staff_driver_admin_read') then
    create policy orders_staff_driver_admin_read on public.orders
      for select to authenticated
      using (public.has_any_role(array['staff', 'driver', 'admin']::text[]));
  end if;

  -- Customers place Orders for themselves only; must start at status 'new'.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'orders' and policyname = 'orders_insert_own_customer') then
    create policy orders_insert_own_customer on public.orders
      for insert to authenticated
      with check (
        google_user_id = auth.uid()
        and status = 'new'
        and exists (
          select 1 from public.customers c
          where c.phone = orders.phone and c.google_user_id = auth.uid()
        )
      );
  end if;

  -- Status transitions are Staff/Driver/Admin only; Customers never update.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'orders' and policyname = 'orders_status_ops_update') then
    create policy orders_status_ops_update on public.orders
      for update to authenticated
      using (public.has_any_role(array['staff', 'driver', 'admin']::text[]))
      with check (public.has_any_role(array['staff', 'driver', 'admin']::text[]));
  end if;

  -- order_events ---------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'order_events' and policyname = 'order_events_staff_admin_all') then
    create policy order_events_staff_admin_all on public.order_events
      for all to authenticated
      using (public.has_any_role(array['staff', 'admin']::text[]))
      with check (public.has_any_role(array['staff', 'admin']::text[]));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'order_events' and policyname = 'order_events_customer_read_own') then
    create policy order_events_customer_read_own on public.order_events
      for select to authenticated
      using (exists (
        select 1 from public.orders o
        where o.id = order_events.order_id and o.google_user_id = auth.uid()
      ));
  end if;

  -- visits ---------------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'visits' and policyname = 'visits_staff_admin_all') then
    create policy visits_staff_admin_all on public.visits
      for all to authenticated
      using (public.has_any_role(array['staff', 'admin']::text[]))
      with check (public.has_any_role(array['staff', 'admin']::text[]));
  end if;

  -- staff_log ------------------------------------------------------------------
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'staff_log' and policyname = 'staff_log_staff_admin_all') then
    create policy staff_log_staff_admin_all on public.staff_log
      for all to authenticated
      using (public.has_any_role(array['staff', 'admin']::text[]))
      with check (public.has_any_role(array['staff', 'admin']::text[]));
  end if;

end;
$rls$;

-- Storage: public bucket `menu-photos` (ADR-0005); writes Admin only --------
insert into storage.buckets (id, name, public)
values ('menu-photos', 'menu-photos', true)
on conflict (id) do nothing;

do $storage$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'menu_photos_public_read'
  ) then
    create policy menu_photos_public_read on storage.objects
    for select to public
    using (bucket_id = 'menu-photos');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'menu_photos_admin_write'
  ) then
    create policy menu_photos_admin_write on storage.objects
    for all to authenticated
    using (bucket_id = 'menu-photos' and public.is_admin())
    with check (bucket_id = 'menu-photos' and public.is_admin());
  end if;
end;
$storage$;

-- Realtime on orders (ADR-0006) — ignore duplicate membership ----------------
do $realtime$
begin
  alter publication supabase_realtime add table public.orders;
exception
  when duplicate_object then null; -- already a member
end;
$realtime$;

-- ---------------------------------------------------------------------------
-- 15. Seed data — 4 categories + 12 items (Egyptian café, EGP prices)
-- ---------------------------------------------------------------------------
insert into public.menu_categories (slug, name_ar, name_en, sort) values
  ('hot_drinks',  'مشروبات ساخنة', 'Hot Drinks',  1),
  ('cold_drinks', 'مشروبات باردة', 'Cold Drinks', 2),
  ('snacks',      'سناكس',         'Snacks',      3),
  ('specials',    'عروض خاصة',     'Specials',    4)
on conflict (slug) do nothing;

insert into public.menu_items
  (id, category_id, slug, name_ar, name_en, desc_ar, desc_en, price_egp, image_url, is_available, sort)
values
  -- Hot Drinks
  ('c0ffe001-0000-4000-8000-000000000001', (select id from public.menu_categories where slug = 'hot_drinks'),
   'espresso', 'إسبريسو', 'Espresso',
   'جرعة مركزة من حبوب محمصة طازجة.', 'A concentrated shot of freshly roasted beans.',
   30, null, true, 1),
  ('c0ffe002-0000-4000-8000-000000000002', (select id from public.menu_categories where slug = 'hot_drinks'),
   'latte', 'لاتيه', 'Latte',
   'إسبريسو مع حليب مبخّر ناعم.', 'Espresso topped with silky steamed milk.',
   45, null, true, 2),
  ('c0ffe003-0000-4000-8000-000000000003', (select id from public.menu_categories where slug = 'hot_drinks'),
   'cappuccino', 'كابتشينو', 'Cappuccino',
   'إسبريسو ورغوة حليب ورشة كاكاو.', 'Espresso, foamed milk and a dusting of cocoa.',
   40, null, true, 3),
  ('c0ffe004-0000-4000-8000-000000000004', (select id from public.menu_categories where slug = 'hot_drinks'),
   'turkish_coffee', 'قهوة تركي', 'Turkish Coffee',
   'قهوة تركي على الرمل، على أصولها.', 'Turkish coffee brewed the traditional way.',
   35, null, true, 4),

  -- Cold Drinks
  ('c0ffe005-0000-4000-8000-000000000005', (select id from public.menu_categories where slug = 'cold_drinks'),
   'karkadeh', 'كركديه', 'Hibiscus',
   'كركديه أحمر من النوبة، ساخن أو ساقع.', 'Nubian red hibiscus, hot or iced.',
   25, null, true, 1),
  ('c0ffe006-0000-4000-8000-000000000006', (select id from public.menu_categories where slug = 'cold_drinks'),
   'iced_latte', 'آيس لاتيه', 'Iced Latte',
   'لاتيه بارد على ثلج بحبوب مزدوجة.', 'Chilled latte over ice with a double shot.',
   55, null, true, 2),
  ('c0ffe007-0000-4000-8000-000000000007', (select id from public.menu_categories where slug = 'cold_drinks'),
   'lemon_mint', 'ليمون بالنعناع', 'Lemon Mint',
   'ليمون طازج بالنعناع، المنعش الأول.', 'Fresh lemon blended with mint — the ultimate cooler.',
   35, null, true, 3),
  ('c0ffe008-0000-4000-8000-000000000008', (select id from public.menu_categories where slug = 'cold_drinks'),
   'mango_juice', 'عصير مانجو', 'Mango Juice',
   'مانجو بلدي طبيعي 100%.', '100% natural local mango.',
   40, null, true, 4),

  -- Snacks
  ('c0ffe009-0000-4000-8000-000000000009', (select id from public.menu_categories where slug = 'snacks'),
   'croissant', 'كرواسون', 'Croissant',
   'كرواسون زبدة مخبوز يوميًا.', 'Buttery croissant baked fresh daily.',
   30, null, true, 1),
  ('c0ffe00a-0000-4000-8000-00000000000a', (select id from public.menu_categories where slug = 'snacks'),
   'cheese_fatayer', 'فطير جبنة', 'Cheese Fatayer',
   'فطير جبنة طرية من الفرن.', 'Soft cheese pastry straight from the oven.',
   25, null, true, 2),
  ('c0ffe00b-0000-4000-8000-00000000000b', (select id from public.menu_categories where slug = 'snacks'),
   'basbousa', 'بسبوسة', 'Basbousa',
   'بسبوسة بالقشطة على الطريقة المصرية.', 'Cream-filled semolina cake, Egyptian style.',
   20, null, true, 3),

  -- Specials
  ('c0ffe00c-0000-4000-8000-00000000000c', (select id from public.menu_categories where slug = 'specials'),
   'mixed_nuts_bowl', 'مكسرات مشكلة', 'Mixed Nuts Bowl',
   'تشكيلة مكسرات مشكلة للمشاركة.', 'A sharing bowl of mixed nuts.',
   45, null, true, 1)
on conflict (slug) do nothing;

commit;

-- ============================================================================
-- Post-run verification snippets (also in docs/SUPABASE_SETUP.md):
--   select count(*) from public.menu_items;    -- expect 12
--   select count(*) from public.menu_categories; -- expect 4
--   select count(*) from public.app_config;    -- expect 14
-- ============================================================================
