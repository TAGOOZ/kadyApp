-- 0017_risk_foundation.sql — RISK-01 foundation
-- Adds nullable risk columns to orders, centralises thresholds in app_config
-- (risk.*) plus optional risk_rules table, and ships pure Dart engine
-- calculateRisk (no Supabase imports) whose output drives
-- risk_score/level/action/reasons/evaluated_at. Slice is demoable by
-- inserting an order and reading back its persisted risk fields.
--
-- Do not place logic inside OrdersRepo.placeOrder() — engine lives in
-- domain/ like loyalty_rules.dart and is called from a DB before-insert
-- hook/RPC (wired in RISK-04). Money/items columns stay immutable via
-- orders_guard_update.

begin;

-- ---------------------------------------------------------------------------
-- 1. orders risk columns (nullable; server-authoritative, client must not forge)
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists risk_score int
    check (risk_score between 0 and 100);

alter table public.orders
  add column if not exists risk_level text
    check (risk_level in ('low', 'medium', 'high'));

alter table public.orders
  add column if not exists risk_action text
    check (risk_action in ('approved', 'needs_verification', 'rejected'));

alter table public.orders
  add column if not exists risk_reasons jsonb not null default '[]'::jsonb;

alter table public.orders
  add column if not exists risk_evaluated_at timestamptz;

-- Backfill for existing rows: risk_reasons defaults to [] (not null), others null.
-- No data migration needed; columns are nullable.

-- ---------------------------------------------------------------------------
-- 2. Indexes for risk queue filtering (RISK-06 verification queue)
-- ---------------------------------------------------------------------------
create index if not exists idx_orders_risk_level on public.orders (risk_level);
create index if not exists idx_orders_risk_action on public.orders (risk_action);

-- ---------------------------------------------------------------------------
-- 3. Guard: non-admin clients cannot write risk columns
--    Revoke/restrict or orders_guard_update exempt — verified by 42501 on
--    forged UPDATE. We extend the existing orders_guard_update() to treat
--    risk_* as immutable for non-admin, mirroring money/items immutability
--    (0003_order_update_hardening.sql). Customers already have no UPDATE
--    policy on orders (RLS), so any customer UPDATE fails 42501 via guard;
--    staff/driver UPDATE attempts to forge risk also raise 42501.
-- ---------------------------------------------------------------------------
create or replace function public.orders_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
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
    -- Risk substrate: only admin (via SECURITY DEFINER RPC/trigger) may
    -- mutate risk_*; any direct client UPDATE forging these is rejected.
    if new.risk_score        is distinct from old.risk_score
    or new.risk_level        is distinct from old.risk_level
    or new.risk_action       is distinct from old.risk_action
    or new.risk_reasons      is distinct from old.risk_reasons
    or new.risk_evaluated_at is distinct from old.risk_evaluated_at then
      raise exception 'orders: risk columns are server-authoritative' using errcode = '42501';
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

  -- staff / admin fall through: full status vocabulary allowed.
  return new;
end;
$$;

drop trigger if exists trg_orders_guard on public.orders;
create trigger trg_orders_guard
  before update on public.orders
  for each row execute function public.orders_guard_update();

-- ---------------------------------------------------------------------------
-- 4. app_config seeds — configurable thresholds (conflict-safe, idempotent)
-- ---------------------------------------------------------------------------
insert into public.app_config (key, value) values
  ('risk.low_max_score',               '29'::jsonb),
  ('risk.medium_max_score',            '59'::jsonb),
  ('risk.large_order_threshold',        '500'::jsonb),
  ('risk.rapid_orders_count',           '3'::jsonb),
  ('risk.rapid_orders_window_minutes',  '30'::jsonb),
  ('risk.max_verification_attempts',    '5'::jsonb),
  ('risk.verification_expiry_minutes',  '15'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Optional risk_rules table — rule catalog (idempotent, disabled-flag honoured)
-- ---------------------------------------------------------------------------
create table if not exists public.risk_rules (
  id          uuid primary key default gen_random_uuid(),
  rule_code   text unique not null,
  description text,
  score       int not null,
  enabled     boolean not null default true,
  configuration jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.risk_rules is 'Rule catalog for risk engine; scores match plan §7; disabled-flags honoured by calculateRisk.';

-- keep updated_at fresh
drop trigger if exists trg_risk_rules_updated_at on public.risk_rules;
create trigger trg_risk_rules_updated_at
  before update on public.risk_rules
  for each row execute function public.set_updated_at();

-- RLS: public read (for config inspect), admin write
alter table public.risk_rules enable row level security;

do $risk_rls$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'risk_rules'
      and policyname = 'risk_rules_public_read'
  ) then
    create policy risk_rules_public_read on public.risk_rules
      for select to public using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'risk_rules'
      and policyname = 'risk_rules_admin_write'
  ) then
    create policy risk_rules_admin_write on public.risk_rules
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end;
$risk_rls$;

-- Seed 10 rows idempotently — scores match plan §7
insert into public.risk_rules (rule_code, description, score, enabled) values
  ('NEW_CUSTOMER',              'First order for this phone',                20, true),
  ('NEW_DEVICE',                'First order from this device',              10, true),
  ('PREVIOUS_FAILED_DELIVERY',  'Prior failed delivery',                     25, true),
  ('PREVIOUS_REJECTED_ORDER',   'Prior rejected order',                      30, true),
  ('THREE_PLUS_CANCELLATIONS',  'Three or more cancellations',               25, true),
  ('LARGE_ORDER',               'Order subtotal >= large threshold',         15, true),
  ('RAPID_ORDERS',              'Rapid orders within window',                20, true),
  ('THREE_PLUS_SUCCESSFUL',     'Three or more successful orders',          -20, true),
  ('FIVE_PLUS_SUCCESSFUL',      'Five or more successful orders',           -30, true),
  ('VERIFIED_PHONE',            'Phone verified',                           -15, true)
on conflict (rule_code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Fix pre-existing credit_new_order slice bug (discovered during RISK-01 smoke)
--    jsonb [0:99] subscript not supported on current Postgres; replace with
--    jsonb_agg limiting to 100. Keeps migration idempotent and preserves
--    existing 0004/0013 logic otherwise.
-- ---------------------------------------------------------------------------
create or replace function public.credit_new_order()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  ls_row   public.loyalty_state;
  ls       jsonb;
  redeemed int := 0;
  redeemed_type text := null;
  cost_expected int;
  mult     numeric := 1.0;
  dbl      boolean := false;
  earned   int;
begin
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

  mult := coalesce(
    (select value::text::numeric from app_config where key = 'dine_in_multiplier'),
    1.0);
  if new.mode <> 'dine_in' then mult := 1.0; end if;

  dbl := ls_row.double_next_order
      or exists (select 1 from campaigns
                  where kind = 'double_points' and active
                    and (starts_at is null or starts_at <= now())
                    and (ends_at   is null or ends_at   >= now()));

  earned := public.round_half_up(
    coalesce(new.subtotal, 0)::numeric / 10.0 * mult * case when dbl then 2 else 1 end);

  ls := to_jsonb(ls_row);
  if coalesce(new.subtotal, 0) >= coalesce(
       (select value::text::int from app_config where key = 'stamp_min_spend'), 50) then
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
      select jsonb_agg(elem) from (
        select elem from jsonb_array_elements(jsonb_build_array(new.id::text) || l.processed_orders) with ordinality t(elem, ord) where ord <= 100
      ) s
    ),
    updated_at        = now()
  where l.phone = ls_row.phone;

  insert into order_events(order_id, status, actor, at)
  values (new.id, 'new', 'system:loyalty', now());

  return new;
end;
$$;

commit;
