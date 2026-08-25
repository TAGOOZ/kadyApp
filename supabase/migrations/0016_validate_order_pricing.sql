-- 0016_validate_order_pricing.sql — SECURITY-03
-- Validate order pricing server-side — recompute subtotal/total from menu_items.
-- Client previously supplied subtotal/delivery_fee/total/items verbatim;
-- an attacker could inflate subtotal to farm points or deflate total to
-- pay less. This BEFORE INSERT trigger recomputes from ground truth.

create or replace function public.validate_order_pricing()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  v_computed_subtotal int := 0;
  v_expected_fee int := 0;
  v_item jsonb;
  v_id uuid;
  v_qty int;
  v_price int;
  v_delivery_fee_config int;
begin
  -- Recompute subtotal from menu_items.price_egp if items provided
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
      -- Note: config addons pricing not in menu_items; for now base price only.
      -- If addons have extra cost, they should be added here via lookup.
      v_computed_subtotal := v_computed_subtotal + (v_price * v_qty);
    end loop;
  end if;

  -- Validate delivery_fee against app_config
  select value::text::int into v_delivery_fee_config from public.app_config where key = 'delivery_fee';
  v_delivery_fee_config := coalesce(v_delivery_fee_config, 15);
  if new.mode = 'delivery' then
    v_expected_fee := v_delivery_fee_config;
  else
    v_expected_fee := 0;
  end if;

  -- Overwrite client-supplied values with server-computed ones.
  -- This is a hard correction, not just validation — prevents forging.
  -- If subtotal was 0 (empty cart) we still allow but credit trigger will handle stamps check.
  new.subtotal := v_computed_subtotal;
  new.delivery_fee := v_expected_fee;
  new.total := v_computed_subtotal + v_expected_fee;

  -- Optional sanity: reject if items empty but subtotal >0 etc handled by above.

  return new;
end;
$$;

drop trigger if exists trg_validate_order_pricing on public.orders;
create trigger trg_validate_order_pricing
  before insert on public.orders
  for each row execute function public.validate_order_pricing();

comment on function public.validate_order_pricing() is 'SECURITY-03: recompute subtotal/delivery_fee/total from menu_items, ignore client-supplied values.';
