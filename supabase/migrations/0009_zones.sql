-- 0009_zones.sql — Zoned delivery fees (FEATURES §11.7 Phase 2).
-- MVP keeps flat `delivery_fee` in app_config; this table is the extension
-- for polygon / per-area fees. Deferred UI shows a banner until Phase 2.
create table if not exists public.zones (
  id        uuid primary key default gen_random_uuid(),
  name_ar   text not null,
  name_en   text,
  polygon   jsonb, -- GeoJSON Polygon or null for simple radius/area
  fee       int  not null check (fee >= 0)
);

comment on table public.zones is 'Zoned delivery fees — polygon + per-area fee (Phase 2, FEATURES §11.7). Flat fee in app_config until then.';

-- RLS: public read, admin write.
alter table public.zones enable row level security;

drop policy if exists "zones_public_read" on public.zones;
create policy "zones_public_read" on public.zones for select to public using (true);

drop policy if exists "zones_admin_write" on public.zones;
create policy "zones_admin_write" on public.zones for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Seed: single citywide zone (mirrors flat fee 15 EGP) for forward compat.
insert into public.zones (name_ar, name_en, fee) values
  ('المدينة', 'Citywide', 15)
on conflict do nothing;
