-- 0032_patch_hash_and_clamp.sql — patch residual prod fails
-- #A: drop unit_total from intake hash (dedup on intent, not computed price)
--     price change between retries still dedupes; mirrors Dart order_intake.dart
-- #B: clamp → throw on out-of-range size (0..2) fails fast 22023

-- #A fix hash (was btrim(phone) + btrim(note) + unit_total; now without unit_total)
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
      btrim(coalesce(elem->'config'->>'note','')) as item_key
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) as elem
  ) s;

  v_canonical := btrim(coalesce(p_phone,'')) || '|' || coalesce(v_items_canonical,'') || '|' || coalesce(p_address_id::text,'');
  return md5(v_canonical);
end;
$$;

comment on function public.compute_order_intake_hash(text, jsonb, uuid) is
  '0032 intent-only: md5(btrim(phone)|sortedItemKeys|address) itemKey=id:qty:size:sugar:addonsSorted:btrim(note) — unit_total excluded so price edit between retries still dedupes. Mirrors Dart orderIntakeKeyFromJson.';

-- #B fix pipeline clamp → 22023 (rebuild function to keep DAG intact)
-- We recreate order_intake_pipeline with size validation throwing.
-- Reuse current 0030 body but patch the v_size block.

create or replace function public.order_intake_pipeline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
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
  v_total_orders int:=0; v_successful int:=0; v_cancelled int:=0; v_failed int:=0; v_rejected int:=0; v_verified bool:=false;
  v_is_new_device bool:=false; v_device_distinct_before int:=0; v_device_customer_count int:=0;
  v_addr_distinct_before int:=0; v_addr_has_phone bool:=false; v_address_customer_count int:=0; v_address_failed_count int:=0;
  v_recent_orders int:=0; v_is_rapid bool:=false; v_rapid_count int:=3; v_rapid_window int:=30;
  v_ctx jsonb; v_res jsonb;
  max_n int; win_min int; recent int; rapid_n int; rapid_win int; rapid_recent int;
  v_hash text; v_existing uuid;
begin
  if new.display_number is null then
    new.display_number := nextval('public.order_display_seq');
  end if;

  if new.phone is not null and btrim(new.phone) <> '' then
    v_hash := public.compute_order_intake_hash(btrim(new.phone), new.items, new.address_id);
  elsif new.google_user_id is not null then
    v_hash := public.compute_order_intake_hash(new.google_user_id::text, new.items, new.address_id);
  else
    v_hash := public.compute_order_intake_hash(null, new.items, new.address_id);
  end if;
  new.idempotency_key := v_hash;
  new.dedup_hash := v_hash;

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
      if v_size < 0 or v_size > 2 then
        raise exception 'validate_order_pricing: invalid size %', v_size using errcode = '22023';
      end if;
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

  begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count:=coalesce(v_rapid_count,3);
  begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window:=coalesce(v_rapid_window,30);
  if new.phone is not null then
    select total_orders,successful_orders,cancelled_orders,failed_deliveries,rejected_orders,phone_verified
      into v_total_orders,v_successful,v_cancelled,v_failed,v_rejected,v_verified
      from public.customer_risk_profiles where phone=btrim(new.phone);
    if not found then v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if;
  else v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if;

  if new.device_id is not null and btrim(new.device_id)<>'' then
    select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id=btrim(new.device_id);
    if new.phone is not null then
      select not exists(select 1 from public.customer_devices where phone=btrim(new.phone) and device_id=btrim(new.device_id)) into v_is_new_device;
    else v_is_new_device:=true; end if;
    if v_is_new_device then v_device_customer_count:=v_device_distinct_before+1; else v_device_customer_count:=v_device_distinct_before; end if;
  else v_is_new_device:=false; v_device_customer_count:=0; end if;

  if new.address_id is not null then
    select count(distinct phone) into v_addr_distinct_before from public.orders where address_id=new.address_id;
    if new.phone is not null then
      select exists(select 1 from public.orders where address_id=new.address_id and phone=btrim(new.phone)) into v_addr_has_phone;
      if v_addr_has_phone then v_address_customer_count:=v_addr_distinct_before; else v_address_customer_count:=v_addr_distinct_before+1; end if;
    else v_address_customer_count:=v_addr_distinct_before; end if;
    select count(*) into v_address_failed_count from public.orders where address_id=new.address_id and status='cancelled';
  else v_address_customer_count:=0; v_address_failed_count:=0; end if;

  if new.phone is not null and v_rapid_window>0 and v_rapid_count>0 then
    select count(*) into v_recent_orders from public.orders where phone=btrim(new.phone) and created_at>now()-(v_rapid_window||' minutes')::interval;
    v_is_rapid:=(v_recent_orders+1)>=v_rapid_count;
  else v_is_rapid:=false; end if;

  v_ctx:=jsonb_build_object('total_orders',v_total_orders,'successful_orders',v_successful,'cancelled_orders',v_cancelled,'failed_deliveries',v_failed,'rejected_orders',v_rejected,'phone_verified',v_verified,'is_new_device',v_is_new_device,'device_customer_count',v_device_customer_count,'address_customer_count',v_address_customer_count,'address_failed_count',v_address_failed_count,'is_rapid',v_is_rapid,'subtotal',coalesce(new.subtotal,0),'has_phone',new.phone is not null);
  v_res:=public.risk_calculate(v_ctx);
  new.risk_score:=(v_res->>'score')::int; new.risk_level:=v_res->>'level'; new.risk_action:=v_res->>'action'; new.risk_reasons:=v_res->'reasons'; new.risk_evaluated_at:=now();

  select value::text::int into max_n   from public.app_config where key = 'rate_limit_max';
  select value::text::int into win_min from public.app_config where key = 'rate_limit_window_min';
  if coalesce(max_n, 5) > 0 and coalesce(win_min, 5) > 0 then
    select count(*) into recent
      from public.orders o
     where o.phone = btrim(new.phone)
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
     where phone = btrim(new.phone)
       and created_at > now() - make_interval(mins => rapid_win);
    if (rapid_recent + 1) >= rapid_n then
      raise exception 'rapid orders rate limited' using errcode='P0001', hint='rapid_orders';
    end if;
  end if;

  if new.phone is not null then
    select id into v_existing
      from public.orders
     where phone = btrim(new.phone)
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
