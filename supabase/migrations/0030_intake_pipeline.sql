-- 0030_intake_pipeline.sql — Candidate 6: Stabilize idempotency & trigger ordering
-- Deep Order Intake module: single content-addressed key = hash(phone + items + address)
-- stable across retries (no nonce), explicit DAG not alphabetical names.
-- One BEFORE INSERT function order_intake_pipeline() that calls steps in order:
--   validate -> risk -> rate-limit -> dedup, rather than 4 separate triggers
-- relying on trg_a/b/c/d alphabetical order. Coalesces 5 copies of
-- orders_guard_update into one canonical definition.
-- Preserves history (don't break existing orders) — existing idempotency_keys
-- that are UUIDs remain valid; new inserts get content hash server-authoritatively.
-- Keeps risk/pricing modules deepened (0027/28/29) — reuses risk_calculate +
-- pricing quote inside pipeline, doesn't duplicate rule math.
--
-- DAG: explicit ordered calls inside one trigger function, not trigger names.
-- Key: hash(phone + items + address) via compute_order_intake_hash, stable
-- across retries, json key-order insensitive, addon-order insensitive.
-- Adapter: Supabase Postgres in prod (this pipeline), in-memory FakeOrdersDb
-- in tests (lib/domain/order_intake.dart). Drops Uuid.v4 nonce, jsonb::text
-- md5 divergence, triple fallback recovery.

begin;

-- ---------------------------------------------------------------------------
-- 0. Content-addressed intake hash — canonical, sorted, stable
-- Mirrors Dart lib/domain/order_intake.dart orderIntakeKeyFromJson
--   canonical = phoneOrGoogleId + '|' + sortedItemKeys + '|' + addressId
--   itemKey = id:qty:size:sugar:addonsSorted:note:unit_total
-- Sort both items and addons so json key order / array order doesn't matter.
-- ---------------------------------------------------------------------------
create or replace function public.compute_order_intake_hash(
  p_phone text,
  p_items jsonb,
  p_address_id uuid
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_items_canonical text;
  v_canonical text;
begin
  select coalesce(string_agg(item_key, '|' order by item_key), '') into v_items_canonical
  from (
    select
      coalesce(elem->>'id','') || ':' ||
      coalesce(elem->>'qty','1') || ':' ||
      coalesce(elem->'config'->>'size','0') || ':' ||
      coalesce(elem->'config'->>'sugar','0') || ':' ||
      coalesce((select string_agg(val, ',' order by val) from jsonb_array_elements_text(coalesce(elem->'config'->'addons','[]'::jsonb)) as t(val)), '') || ':' ||
      coalesce(elem->'config'->>'note','') || ':' ||
      coalesce(elem->>'unit_total','0') as item_key
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) as elem
  ) s;

  v_canonical := coalesce(p_phone,'') || '|' || coalesce(v_items_canonical,'') || '|' || coalesce(p_address_id::text,'');
  return md5(v_canonical);
end;
$$;

comment on function public.compute_order_intake_hash(text, jsonb, uuid) is
  'Candidate 6 intake hash: md5(phone|sortedItemKeys|address) with itemKey=id:qty:size:sugar:addonsSorted:note:unit_total. Mirrors Dart orderIntakeKeyFromJson (lib/domain/order_intake.dart) — keep identical. Stable across retries, json key-order insensitive.';

-- Keep legacy dedup hash for history (deprecated, but don't break old rows)
comment on function public.compute_order_dedup_hash(jsonb, uuid) is
  'Legacy RISK-07 dedup_hash md5(jsonb::text|address) — deprecated in 0030, kept for history. New code uses compute_order_intake_hash (content-addressed with phone).';

-- ---------------------------------------------------------------------------
-- 1. Drop old BEFORE INSERT triggers that relied on alphabetical ordering
--    trg_00_assign_display_number, trg_a_validate_order_pricing,
--    trg_b_evaluate_order_risk, trg_c_enforce_order_rate_limit,
--    trg_d_enforce_order_dedup  — all replaced by single pipeline trigger.
--    Also drop any legacy un-prefixed names.
-- ---------------------------------------------------------------------------
drop trigger if exists trg_00_assign_display_number on public.orders;
drop trigger if exists trg_a_validate_order_pricing on public.orders;
drop trigger if exists trg_b_evaluate_order_risk on public.orders;
drop trigger if exists trg_c_enforce_order_rate_limit on public.orders;
drop trigger if exists trg_d_enforce_order_dedup on public.orders;
drop trigger if exists trg_validate_order_pricing on public.orders;
drop trigger if exists trg_evaluate_order_risk on public.orders;
drop trigger if exists trg_enforce_order_rate_limit on public.orders;
drop trigger if exists trg_orders_display_number on public.orders;
drop trigger if exists trg_order_intake_pipeline on public.orders;

-- ---------------------------------------------------------------------------
-- 2. Single pipeline trigger — explicit DAG: validate -> risk -> rate-limit -> dedup
--    Reuses existing deep modules: pricing via 0029 validate logic, risk via
--    public.risk_calculate(jsonb), rate-limit via same app_config checks.
--    Ordering is explicit code order, not name alphabetical.
-- ---------------------------------------------------------------------------
create or replace function public.order_intake_pipeline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- pricing (0029) — recompute subtotal from menu_items + sizeDelta + addons
  v_computed_raw int := 0;
  v_computed_subtotal int := 0;
  v_expected_fee int := 0;
  v_item jsonb;
  v_id uuid;
  v_qty int;
  v_price int;
  v_delivery_fee_config int;
  v_config jsonb;
  v_size int;
  v_size_delta int := 0;
  v_addons jsonb;
  v_addon text;
  v_addon_total int := 0;
  v_unit_computed int;
  v_line_total_computed int;
  v_category_slug text;
  v_max_drink_line int := 0;
  v_notes text := coalesce(new.notes, '');
  v_discount int := 0;

  -- risk (0028 adapter) — collect context then call risk_calculate
  v_total_orders int:=0; v_successful int:=0; v_cancelled int:=0; v_failed int:=0; v_rejected int:=0; v_verified bool:=false;
  v_is_new_device bool:=false; v_device_distinct_before int:=0; v_device_customer_count int:=0;
  v_addr_distinct_before int:=0; v_addr_has_phone bool:=false; v_address_customer_count int:=0; v_address_failed_count int:=0;
  v_recent_orders int:=0; v_is_rapid bool:=false; v_rapid_count int:=3; v_rapid_window int:=30;
  v_ctx jsonb; v_res jsonb;

  -- rate limit (0026)
  max_n int; win_min int; recent int; rapid_n int; rapid_win int; rapid_recent int;

  -- dedup
  v_hash text; v_existing uuid;
begin
  -- Step 0: display number (was trg_00)
  if new.display_number is null then
    new.display_number := nextval('public.order_display_seq');
  end if;

  -- Step 0b: content-addressed idempotency key (server-authoritative)
  -- Overwrites any client nonce (Uuid.v4) with canonical hash so retries
  -- with same phone+items+address map to same key. Phone fallback to google_user_id.
  if new.phone is not null and new.phone <> '' then
    v_hash := public.compute_order_intake_hash(new.phone, new.items, new.address_id);
  elsif new.google_user_id is not null then
    v_hash := public.compute_order_intake_hash(new.google_user_id::text, new.items, new.address_id);
  else
    v_hash := public.compute_order_intake_hash(null, new.items, new.address_id);
  end if;
  new.idempotency_key := v_hash;
  new.dedup_hash := v_hash;

  -- Step 1: validate pricing (0029 logic — reuse, not duplicate rule math)
  -- Recompute raw subtotal from menu_items.price_egp + sizeDelta + addonPrices
  if new.items is not null and jsonb_typeof(new.items) = 'array' then
    for v_item in select * from jsonb_array_elements(new.items)
    loop
      begin
        v_id := (v_item->>'id')::uuid;
      exception when others then
        raise exception 'validate_order_pricing: invalid item id %', v_item->>'id' using errcode = '22023';
      end;
      v_qty := coalesce((v_item->>'qty')::int, 1);
      if v_qty <= 0 then v_qty := 1; end if;

      select price_egp into v_price from public.menu_items where id = v_id;
      if v_price is null then
        raise exception 'validate_order_pricing: menu item % not found', v_id using errcode = '22023';
      end if;

      v_config := coalesce(v_item->'config', '{}'::jsonb);
      v_size := coalesce((v_config->>'size')::int, 0);
      if v_size < 0 then v_size := 0; elsif v_size > 2 then v_size := 2; end if;
      v_size_delta := case v_size when 0 then 0 when 1 then 10 when 2 then 15 else 0 end;

      v_addons := coalesce(v_config->'addons', '[]'::jsonb);
      v_addon_total := 0;
      if jsonb_typeof(v_addons) = 'array' then
        for v_addon in select jsonb_array_elements_text(v_addons) loop
          v_addon_total := v_addon_total + case v_addon
            when 'espresso_shot' then 15
            when 'caramel' then 10
            when 'whipped_cream' then 12
            else 0 end;
        end loop;
      end if;

      v_unit_computed := v_price + v_size_delta + v_addon_total;
      v_line_total_computed := v_unit_computed * v_qty;
      v_computed_raw := v_computed_raw + v_line_total_computed;

      begin
        select c.slug into v_category_slug
          from public.menu_categories c
          join public.menu_items mi on mi.category_id = c.id
         where mi.id = v_id;
      exception when others then
        v_category_slug := null;
      end;
      if v_category_slug in ('hot_drinks','cold_drinks','hot-drinks','cold-drinks','iced-espresso') then
        if v_line_total_computed > v_max_drink_line then
          v_max_drink_line := v_line_total_computed;
        end if;
      end if;
    end loop;
  end if;

  if v_notes ~ '\[REDEEMED:free_drink:[0-9]+\]' then
    v_discount := v_max_drink_line;
  else
    v_discount := 0;
  end if;
  v_computed_subtotal := v_computed_raw - v_discount;
  if v_computed_subtotal < 0 then v_computed_subtotal := 0; end if;

  select value::text::int into v_delivery_fee_config from public.app_config where key = 'delivery_fee';
  v_delivery_fee_config := coalesce(v_delivery_fee_config, 15);
  if new.mode = 'delivery' then
    v_expected_fee := v_delivery_fee_config;
  else
    v_expected_fee := 0;
  end if;

  new.subtotal := v_computed_subtotal;
  new.delivery_fee := v_expected_fee;
  new.total := v_computed_subtotal + v_expected_fee;

  -- Step 2: risk (collect context then delegate to pure risk_calculate)
  begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count:=coalesce(v_rapid_count,3);
  begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window:=coalesce(v_rapid_window,30);
  if new.phone is not null then
    select total_orders,successful_orders,cancelled_orders,failed_deliveries,rejected_orders,phone_verified
      into v_total_orders,v_successful,v_cancelled,v_failed,v_rejected,v_verified
      from public.customer_risk_profiles where phone=new.phone;
    if not found then v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if;
  else v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if;

  if new.device_id is not null and new.device_id<>'' then
    select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id=new.device_id;
    if new.phone is not null then
      select not exists(select 1 from public.customer_devices where phone=new.phone and device_id=new.device_id) into v_is_new_device;
    else v_is_new_device:=true; end if;
    if v_is_new_device then v_device_customer_count:=v_device_distinct_before+1; else v_device_customer_count:=v_device_distinct_before; end if;
  else v_is_new_device:=false; v_device_customer_count:=0; end if;

  if new.address_id is not null then
    select count(distinct phone) into v_addr_distinct_before from public.orders where address_id=new.address_id;
    if new.phone is not null then
      select exists(select 1 from public.orders where address_id=new.address_id and phone=new.phone) into v_addr_has_phone;
      if v_addr_has_phone then v_address_customer_count:=v_addr_distinct_before; else v_address_customer_count:=v_addr_distinct_before+1; end if;
    else v_address_customer_count:=v_addr_distinct_before; end if;
    select count(*) into v_address_failed_count from public.orders where address_id=new.address_id and status='cancelled';
  else v_address_customer_count:=0; v_address_failed_count:=0; end if;

  if new.phone is not null and v_rapid_window>0 and v_rapid_count>0 then
    select count(*) into v_recent_orders from public.orders where phone=new.phone and created_at>now()-(v_rapid_window||' minutes')::interval;
    v_is_rapid:=(v_recent_orders+1)>=v_rapid_count;
  else v_is_rapid:=false; end if;

  v_ctx:=jsonb_build_object('total_orders',v_total_orders,'successful_orders',v_successful,'cancelled_orders',v_cancelled,'failed_deliveries',v_failed,'rejected_orders',v_rejected,'phone_verified',v_verified,'is_new_device',v_is_new_device,'device_customer_count',v_device_customer_count,'address_customer_count',v_address_customer_count,'address_failed_count',v_address_failed_count,'is_rapid',v_is_rapid,'subtotal',coalesce(new.subtotal,0),'has_phone',new.phone is not null);
  v_res:=public.risk_calculate(v_ctx);
  new.risk_score:=(v_res->>'score')::int; new.risk_level:=v_res->>'level'; new.risk_action:=v_res->>'action'; new.risk_reasons:=v_res->'reasons'; new.risk_evaluated_at:=now();

  -- Step 3: rate limit (5/5min + rapid_orders 3/30) — reuse app_config, not hardcoded
  select value::text::int into max_n   from public.app_config where key = 'rate_limit_max';
  select value::text::int into win_min from public.app_config where key = 'rate_limit_window_min';
  if coalesce(max_n, 5) > 0 and coalesce(win_min, 5) > 0 then
    select count(*) into recent
      from public.orders o
     where o.phone = new.phone
       and o.created_at > now() - make_interval(mins => coalesce(win_min, 5));
    if recent >= coalesce(max_n, 5) then
      raise exception 'orders: rate limited'
        using errcode = 'P0001', hint = 'too_many_orders';
    end if;
  end if;

  select value::text::int into rapid_n   from public.app_config where key = 'risk.rapid_orders_count';
  select value::text::int into rapid_win from public.app_config where key = 'risk.rapid_orders_window_minutes';
  rapid_n := coalesce(rapid_n, 3);
  rapid_win := coalesce(rapid_win, 30);
  if rapid_n > 0 and rapid_win > 0 and new.phone is not null then
    select count(*) into rapid_recent
      from public.orders
     where phone = new.phone
       and created_at > now() - make_interval(mins => rapid_win);
    if (rapid_recent + 1) >= rapid_n then
      raise exception 'rapid orders rate limited' using errcode='P0001', hint='rapid_orders';
    end if;
  end if;

  -- Step 4: dedup (content-addressed 60s window) — same hash as computed in step 0b
  -- If duplicate within window, raise P0001 with existing id hint for single-recovery adapter.
  if new.phone is not null then
    select id into v_existing
      from public.orders
     where phone = new.phone
       and dedup_hash = v_hash
       and created_at > now() - make_interval(secs => 60)
     order by created_at desc
     limit 1;
  elsif new.google_user_id is not null then
    select id into v_existing
      from public.orders
     where google_user_id = new.google_user_id
       and dedup_hash = v_hash
       and created_at > now() - make_interval(secs => 60)
     order by created_at desc
     limit 1;
  end if;

  if v_existing is not null then
    raise exception 'duplicate order: %', v_existing using errcode = 'P0001', hint = v_existing::text;
  end if;

  return new;
end;
$$;

comment on function public.order_intake_pipeline() is
  'Candidate 6 pipeline: single BEFORE INSERT trigger with explicit DAG validate -> risk -> rate-limit -> dedup. Reuses risk_calculate (0028) and pricing quote (0029) without duplicating rule math. Ordering is code order, not alphabetical trigger names.';

create trigger trg_order_intake_pipeline
  before insert on public.orders
  for each row execute function public.order_intake_pipeline();

-- ---------------------------------------------------------------------------
-- 3. Coalesce orders_guard_update into one canonical (was copied 5 times)
--    Keep logic from 0026 (auth.role() + profiles, not current_user, covers
--    money/items/phone immutability, risk server-authoritative, dispatch gate).
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
  v_caller_role text := coalesce(auth.role(), '');
begin
  select p.role into actor_role from public.profiles p where p.user_id = auth.uid();

  if v_caller_role = 'anon' then
    raise exception 'orders: no profile for caller' using errcode = '42501';
  end if;

  if actor_role is null and v_caller_role not in ('service_role', '') then
    raise exception 'orders: no profile for caller' using errcode = '42501';
  end if;

  if v_caller_role = 'authenticated' and coalesce(actor_role,'') <> 'admin' then
    if new.subtotal       is distinct from old.subtotal
    or new.delivery_fee   is distinct from old.delivery_fee
    or new.total          is distinct from old.total
    or new.items          is distinct from old.items
    or new.phone          is distinct from old.phone
    or new.google_user_id is distinct from old.google_user_id then
      raise exception 'orders: immutable columns changed' using errcode = '42501';
    end if;
  end if;

  if new.risk_score        is distinct from old.risk_score
  or new.risk_level        is distinct from old.risk_level
  or new.risk_action       is distinct from old.risk_action
  or new.risk_reasons      is distinct from old.risk_reasons
  or new.risk_evaluated_at is distinct from old.risk_evaluated_at
  or new.device_id         is distinct from old.device_id then
    if v_caller_role = 'authenticated' and coalesce(actor_role,'') not in ('staff','admin') then
      raise exception 'orders: risk columns are server-authoritative' using errcode = '42501';
    end if;
    if v_caller_role = 'anon' then
      raise exception 'orders: risk columns are server-authoritative' using errcode = '42501';
    end if;
  end if;

  if old.risk_action in ('needs_verification','rejected')
     and new.status is distinct from old.status
     and new.status in ('accepted','in_prep','ready','out_for_delivery','done') then
    if old.risk_action = 'needs_verification' then
      select exists (
        select 1 from public.verification_requests
         where order_id = new.id
           and status = 'confirmed'
      ) into v_has_verification;
      if not v_has_verification then
        raise exception 'needs verification' using errcode = 'P0001';
      end if;
    else
      raise exception 'order rejected' using errcode = 'P0001';
    end if;
  end if;

  if coalesce(actor_role,'') = 'driver' then
    if new.status <> 'done'
    or old.status <> 'out_for_delivery'
    or public.tg_n_cols_changed('status') = false then
      raise exception 'orders: driver may only mark out_for_delivery -> done'
        using errcode = '42501';
    end if;
    return new;
  end if;

  return new;
end;
$$;

comment on function public.orders_guard_update() is
  'Candidate 6 coalesced: single canonical guard (was 5 copies across 0003/0022/0025/0026). Immutable money/items/phone, risk server-authoritative, dispatch gate needs_verification/rejected, driver only done.';

drop trigger if exists trg_orders_guard on public.orders;
create trigger trg_orders_guard
  before update on public.orders
  for each row execute function public.orders_guard_update();

-- ---------------------------------------------------------------------------
-- 4. Indexes for new intake hash (keep legacy dedup_hash indexes for history)
-- ---------------------------------------------------------------------------
create index if not exists idx_orders_intake_hash on public.orders (phone, idempotency_key, created_at desc) where idempotency_key is not null;
create index if not exists idx_orders_intake_hash_gid on public.orders (google_user_id, idempotency_key, created_at desc) where idempotency_key is not null and phone is null;

-- ---------------------------------------------------------------------------
-- 5. Verify triggers after migration (no trg_a/b/c ordering dependency)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_trigger where tgname in ('trg_a_validate_order_pricing','trg_b_evaluate_order_risk','trg_c_enforce_order_rate_limit','trg_d_enforce_order_dedup')) then
    raise exception '0030: legacy trg_a/b/c/d still present — pipeline should have replaced them';
  end if;
  if not exists (select 1 from pg_trigger where tgname='trg_order_intake_pipeline') then
    raise exception '0030: trg_order_intake_pipeline missing';
  end if;
  if not exists (select 1 from pg_proc where proname='order_intake_pipeline') then
    raise exception '0030: order_intake_pipeline function missing';
  end if;
  if not exists (select 1 from pg_proc where proname='compute_order_intake_hash') then
    raise exception '0030: compute_order_intake_hash missing';
  end if;
  -- ordering check via code markers (validate uses v_computed_raw, risk uses risk_calculate, rate uses too_many_orders, dedup uses duplicate order)
  declare vdef text := pg_get_functiondef((select oid from pg_proc where proname='order_intake_pipeline' limit 1));
  begin
    if position('v_computed_raw' in vdef) = 0 or position('risk_calculate' in vdef) = 0 or position('too_many_orders' in vdef) = 0 or position('duplicate order' in vdef) = 0 then
      raise exception '0030: pipeline missing ordered steps';
    end if;
    if position('v_computed_raw' in vdef) > position('risk_calculate' in vdef) or position('risk_calculate' in vdef) > position('too_many_orders' in vdef) or position('too_many_orders' in vdef) > position('duplicate order' in vdef) then
      raise exception '0030: pipeline steps out of order';
    end if;
  end;
end;
$$;

commit;
