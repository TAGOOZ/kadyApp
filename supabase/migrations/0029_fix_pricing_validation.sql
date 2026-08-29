-- 0029_fix_pricing_validation.sql — Candidate 3 (Worth exploring)
-- Collapse pricing into one module: validate full unit_total (price + sizeDelta
-- + addonPrices), not base price alone. Canonical encoding is `unit_total =
-- menu_items.price_egp + sizeDelta(0/10/15) + sum(addonPrices)` — already
-- price+deltas client-side (lib/domain/pricing.dart pricingUnitTotalFor,
-- lib/domain/cart_controller.dart CartLine.unitPriceEgp, lib/ui/menu/item_detail_sheet.dart).
-- Server validates against the same table + delta catalog (hard-coded addon map
-- mirroring kPricingAddonPricesEgp), no overwrite surprise — preview == credited.
--
-- Seeded catalog note (0005_el_kady_menu.sql, 101 rows):
--   Small/large variants are separate MenuItem rows with distinct base prices
--   (e.g. 'قهوة القاضي صغير' 35 vs 'كبير' 50). ItemConfig.sizeDelta (0/10/15) is
--   additive on top of whichever row the customer adds. The UI still exposes
--   size choices for every item, so the server models pricing as
--   `base + delta + addons` for every line — the same additive model the client
--   preview uses. A future migration could consolidate to one base row per drink
--   and encode size purely via deltas.
--
-- Redemption note: free_drink redemption zeroes the highest-priced drink line
-- (lib/domain/loyalty_rules.dart drinkLineDiscountEgp / lib/domain/pricing.dart
-- pricingDiscountFor). When notes contains [REDEEMED:free_drink:N], recomputed
-- subtotal is `rawSubtotal - maxDrinkLineTotal` (clamped 0) so discounted
-- preview and credited subtotal stay aligned. Topping/snack redemptions deduct
-- points only — no cash discount.
begin;

create or replace function public.validate_order_pricing()
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
begin
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

      -- Decode ItemConfig from items[].config (same encoding as OrderItemPayload.toJson())
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

      -- Track max drink line for free_drink redemption discount (mirrors
      -- loyalty_rules.isDrinkCategorySlug: hot_drinks / cold_drinks).
      -- Also handle hyphen variants in seeded catalog (hot-drinks etc.) defensively.
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

  -- Redemption discount: free_drink zeroes the highest drink line (points-only
  -- redemptions have no cash discount). Mirrors checkout_screen discount logic.
  if v_notes ~ '\[REDEEMED:free_drink:[0-9]+\]' then
    v_discount := v_max_drink_line;
  else
    v_discount := 0;
  end if;
  v_computed_subtotal := v_computed_raw - v_discount;
  if v_computed_subtotal < 0 then v_computed_subtotal := 0; end if;

  -- Validate delivery_fee against app_config (admin-editable FeeTable)
  select value::text::int into v_delivery_fee_config from public.app_config where key = 'delivery_fee';
  v_delivery_fee_config := coalesce(v_delivery_fee_config, 15);
  if new.mode = 'delivery' then
    v_expected_fee := v_delivery_fee_config;
  else
    v_expected_fee := 0;
  end if;

  -- Overwrite client-supplied values with server-computed ones — but now
  -- includes size/addon deltas so preview (price+deltas) == credited.
  new.subtotal := v_computed_subtotal;
  new.delivery_fee := v_expected_fee;
  new.total := v_computed_subtotal + v_expected_fee;

  return new;
end;
$$;

-- Preserve alphabetical BEFORE INSERT ordering: trg_a_validate_order_pricing
drop trigger if exists trg_validate_order_pricing on public.orders;
drop trigger if exists trg_a_validate_order_pricing on public.orders;

create trigger trg_a_validate_order_pricing
  before insert on public.orders
  for each row execute function public.validate_order_pricing();

comment on function public.validate_order_pricing() is 'SECURITY-03 (0029 fix): recompute subtotal/delivery_fee/total from menu_items.price_egp + sizeDelta(0/10/15) + addonPrices(espresso_shot 15, caramel 10, whipped_cream 12) and redemption discount, matching lib/domain/pricing.dart quote() — preview == credited.';

-- Verification guard
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'validate_order_pricing') then
    raise exception '0029: validate_order_pricing missing';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_a_validate_order_pricing') then
    raise exception '0029: trg_a_validate_order_pricing missing';
  end if;
end $$;

commit;
