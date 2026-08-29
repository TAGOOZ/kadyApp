-- 0031_fix_intake_hash_trim.sql — High bug #1: trim divergence
-- Dart orderIntakeKey strips phone + note; SQL must do same or same cart
-- with " note " vs "note" yields different hash → dedup bypass / false dedup.
-- Fix: btrim phone + note in compute_order_intake_hash to mirror Dart.

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
      btrim(coalesce(elem->'config'->>'note','')) || ':' ||
      coalesce(elem->>'unit_total','0') as item_key
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) as elem
  ) s;

  v_canonical := btrim(coalesce(p_phone,'')) || '|' || coalesce(v_items_canonical,'') || '|' || coalesce(p_address_id::text,'');
  return md5(v_canonical);
end;
$$;

comment on function public.compute_order_intake_hash(text, jsonb, uuid) is
  '0031 trimmed: md5(btrim(phone)|sortedItemKeys|address) itemKey uses btrim(note). Mirrors Dart orderIntakeKeyFromJson btrim — parity test with whitespace note/phone must pass.';
