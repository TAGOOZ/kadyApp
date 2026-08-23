# Supabase Setup Guide — Elkady Café

One-time backend setup for the Elkady Café app on the existing project
**`zrlhtwmzuljsqricpxbb`** (https://zrlhtwmzuljsqricpxbb.supabase.co).

Everything in `supabase/migrations/0001_init.sql` is safe to re-run
(`if not exists` / `on conflict do nothing` guards throughout).

---

## 1. Run the initial migration (schema + RLS + seeds)

1. Open the SQL editor:
   https://supabase.com/dashboard/project/zrlhtwmzuljsqricpxbb/sql/new
2. Paste the **full contents** of `supabase/migrations/0001_init.sql`.
3. Click **Run**.

Expected output: **`Success. No rows returned`** and no error banner.
(Notices about skipped triggers/extensions are normal on a re-run.)

What this created:

- Tables: `profiles`, `customers`, `loyalty_state`, `menu_categories`,
  `menu_items`, `addresses`, `orders`, `order_events`, `campaigns`,
  `app_config`, `visits`, `staff_log`
- Sequence `order_display_seq` (Order display numbers start at **#1000**)
- RLS policies on every table (Customer sees own data by
  `google_user_id`; Staff/Driver/Admin see all; catalog/config are public read)
- Realtime enabled on `orders`
- Storage bucket **`menu-photos`** (public) + storage policies
- Seed data: 4 menu categories, 12 items, 14 `app_config` loyalty params

## 2. Verify Realtime on `orders`

Dashboard → **Database → Replication** → under `public`, confirm the toggle for
**`orders`** is ON (`supabase_realtime`).

> The migration script already attempts this via SQL; this screen is where you
> visually verify. If it shows OFF, flip it on here.

## 3. Google OAuth provider

1. In [Google Cloud Console](https://console.cloud.google.com/), create/select
   a project.
2. **APIs & Services → OAuth consent screen**: External, fill app name +
   support email, save.
3. **Credentials → Create credentials → OAuth client ID → Web application**:
   - Authorized redirect URI:
     `https://zrlhtwmzuljsqricpxbb.supabase.co/auth/v1/callback`
   - Save the generated **Client ID** and **Client secret**.
4. Back in Supabase: **Authentication → Providers → Google** → enable and paste
   the Client ID / Client secret → **Save**.

> Keep the same **Web Client ID** handy — Flutter Web sign-in needs it later
> (passed to `signInWithOAuth` / GoogleSignIn web config).

## 4. Verify the `menu-photos` bucket

Dashboard → **Storage**: confirm bucket **`menu-photos`** exists and is marked
**Public**. Uploads/writes via API require an **admin** profile; public URL
reads are open (that URL is what goes into `menu_items.image_url`).

## 5. Secrets hygiene

`.env` in the repo root (never committed):

| Key | Where it lives | Notes |
|---|---|---|
| `SUPABASE_URL` | app bundle (.env) | Public by design |
| `SUPABASE_ANON_KEY` | app bundle (.env) | Public by design — RLS protects data |
| `SUPABASE_SECRET_KEY` | server only | **Never** put in the app or repo |

The anon key ships inside the app binary; safety comes from Row Level Security,
which this migration enables on every table. The secret/service key must only
ever live in Edge Function/server environments.

## 6. Smoke checks (run in SQL editor)

Seed counts:

```sql
select count(*) from public.menu_items;      -- expect 12
select count(*) from public.menu_categories; -- expect  4
select count(*) from public.app_config;      -- expect 14
select last_value from public.order_display_seq; -- expect 1000 (is_called = false)
```

Realtime membership:

```sql
select * from pg_publication_tables
where pubname = 'supabase_realtime' and tablename = 'orders'; -- expect 1 row
```

RLS enabled everywhere:

```sql
select tablename from pg_tables
where schemaname = 'public' and not rowsecurity; -- expect 0 rows
```

Quick RLS sanity note: open the app signed out — the Menu loads (public read),
but Orders/Loyalty return empty until Google sign-in. A signed-in Customer only
sees their own orders; Staff/Driver/Admin roles see all orders. Roles are set
by updating `profiles.role` for the account (Admin does this after first login).

## 7. What is deliberately NOT in this migration

- **Edge Function for order rate limiting** (ADR-0010): its parameters
  (`rate_limit_max`, `rate_limit_window_min`) are seeded in `app_config`;
  the function itself is deployed separately when built.
- **Push notifications / FCM**, analytics, POS integration — post-MVP phases.
- **Menu photos**: `image_url` is `null` for all seed items; upload photos to
  `menu-photos` and set URLs via the Admin menu editor (#015).

## Elevate a test user to staff/admin (required for slices #012/#015)

RLS gates staff/driver/admin visibility and writes on `profiles.role`.
After signing in once with your Google account, promote yourself:

```sql
-- see who you are
select id, email from auth.users order by created_at desc limit 5;
update profiles set role = 'staff' where user_id = '<your-auth-user-id>';
-- or 'admin' for the owner dashboard (#015)
```

The Flutter role switcher only changes the local shell; server permissions come
from this row.

## Migration 2 — driver RLS (run after 0001)

Paste `supabase/migrations/0002_driver_rls.sql` the same way as migration 1.
It grants `driver` role read access to customers and insert access to
order_events (needed by the delivery stepper in slice #014).

## Migration 3 — order update hardening (run after 0002)

Paste `supabase/migrations/0003_order_update_hardening.sql`. Adds a guard
trigger: money/items/identity columns become immutable (admin exempt);
drivers may only flip `out_for_delivery → done`; staff/admin keep the full
status vocabulary. Verify by attempting a money edit as staff — it must fail.
