# Black-box Harness — Elkady Café (`kady.pages.dev`)

For agents testing via `chrome-devtools` MCP. Google OAuth is **blocked** in automation, this doc gives the password bypass.

## 1) Why Google login fails in `chrome-devtools`

* `chrome-devtools` launches headless Chromium with `navigator.webdriver=true`, `AutomationControlled`, no user gesture.
* Google risk engine returns `This browser or app may not be secure` for any `accounts.google.com` OAuth flow in that browser. **Not an app bug** — real Chrome on `kady.pages.dev` works.
* Traces confirm correct config:
  ```
  client_id=947063960774-…apps.googleusercontent.com
  redirect_uri=https://zrlhtwmzuljsqricpxbb.supabase.co/auth/v1/callback
  redirect_to=https://kady-api.mostafatageldeen588.workers.dev/auth/callback?next=/
  ```
* CSP blocks `cdn.jsdelivr.net`, so you **cannot** `import supabase-js` from CDN inside the page. Use direct `fetch` to Supabase Auth.

## 2) Seeded test accounts (already created — idempotent)

All passwords `KadyTest123!` — email-confirmed, `profiles.role` set, `customers` row linked for phone-lookup flows.

| Role | Email | Phone | `auth.users.id` |
|---|---|---|---|
| customer | `blackbox_customer@kady.test` | `+201000000111` | `c1d586ac-108f-4ec7-9c11-d043a27cf248` |
| staff | `blackbox_staff@kady.test` | `+201000000222` | `3bd0a2c6-3184-4e13-b42f-510075736727` |
| driver | `blackbox_driver@kady.test` | `+201000000333` | `b56edee5-afb6-4acf-b1d0-caffd25a4784` |
| admin | `blackbox_admin@kady.test` | `+201000000444` | `edfa827c-9fa2-4e67-b251-547140fd447a` |

Existing owner accounts kept: `mostafatageldeen588@gmail.com` (admin, `+201211310357`), `201801840@pua.edu.eg` (customer).

Recreate if deleted — run `scripts/blackbox_setup.sh` or re-apply `scripts/blackbox_seed.sql` via Supabase MCP `supabase_execute_sql`.

## 3) How to log in (chrome-devtools MCP)

### 3.1 One-liner — paste into `chrome-devtools_evaluate_script` (pageId = kady.pages.dev)

```js
// LOGIN AS <role> — change email below
async () => {
  const email = "blackbox_customer@kady.test"; // or blackbox_staff / driver / admin
  const password = "KadyTest123!";
  const supaUrl = "https://zrlhtwmzuljsqricpxbb.supabase.co";
  const anonKey = "sb_publishable_7eznl_xMNGXmxHSzWVdaJQ_r4dj3Apf";
  const proj = "zrlhtwmzuljsqricpxbb";
  // clear previous session so RLS doesn't leak across roles
  localStorage.clear();
  const res = await fetch(`${supaUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password })
  });
  const j = await res.json();
  if (!res.ok) return {ok:false, status:res.status, error:j};
  localStorage.setItem(`sb-${proj}-auth-token`, JSON.stringify({
    access_token: j.access_token,
    refresh_token: j.refresh_token,
    expires_in: j.expires_in,
    expires_at: j.expires_at,
    token_type: j.token_type,
    user: j.user
  }));
  return {ok:true, email: j.user.email, role: j.user.role};
}
```

Then reload:

```
chrome-devtools_navigate_page pageId=1 type=reload
```

Wait 2.5s, then verify:

```js
() => ({ href: location.href, hash: location.hash, role: localStorage.getItem("flutter.session.role"), ls: !!localStorage.getItem("sb-zrlhtwmzuljsqricpxbb-auth-token") })
```

Expected redirects:
* customer → `#/home` (role `"customer"`)
* staff → `#/staff` with heading `لوحة الطلبات`
* driver → `#/driver`
* admin → `#/admin`

### 3.2 File helper

`scripts/blackbox_login.js` exports `loginAs(email,password)` for copy-paste. Use `default.chrome-devtools_evaluate_script` with that function body.

### 3.3 Logout / switch role

Always `localStorage.clear()` before logging in as another role — otherwise `flutter.session.role` and Supabase token leak. Then re-run the snippet with the next email.

### 3.4 Alternative: curl + manual inject

```bash
curl -s -X POST https://zrlhtwmzuljsqricpxbb.supabase.co/auth/v1/token?grant_type=password \
  -H "apikey: sb_publishable_7eznl_xMNGXmxHSzWVdaJQ_r4dj3Apf" \
  -H "Authorization: Bearer sb_publishable_7eznl_xMNGXmxHSzWVdaJQ_r4dj3Apf" \
  -H "Content-Type: application/json" \
  -d '{"email":"blackbox_customer@kady.test","password":"KadyTest123!"}' | jq
# then inject via evaluate_script as above
```

## 4) Flutter-web a11y testing

CanvasKit doesn't expose DOM — you must enable semantics:

```js
() => { const el=document.querySelector('flt-semantics-placeholder'); if(el) el.click(); return true; }
```

Then `chrome-devtools_take_snapshot` shows tappable nodes. All tabs:
* `الرئيسية` (home), `القائمة` (menu), `الألعاب` (games), `حسابي` (profile)
* Staff tabs: `#/staff`, `#/admin`, `#/driver` are role-gated (RLS).

## 5) Seed data for edge cases

Already in DB:
* 101 `menu_items` across 12 categories — cheapest 35 EGP (`قهوة القاضي صغير`), used for §11.11 Western-digits check.
* `loyalty_state` for `+201000000111` = 0/0 so you can test first-stamp flow (`≥50 EGP` → 1 stamp, 10→reset+reward, every-3rd → spinner token).

To add controlled data:

```sql
-- address for delivery mode (required)
insert into addresses(phone,label,address_text) values ('+201000000111','home','اختبار — ١٢ شارع النيل، القاهرة') on conflict do nothing;
-- bump points to test voucher thresholds 100/150/200
update loyalty_state set points=190, lifetime_points=190 where phone='+201000000111';
-- reset loyalty (between test suites)
update loyalty_state set points=0,lifetime_points=0,stamps=0,completed_cards=0,spinner_tokens=0,vouchers='[]'::jsonb,processed_orders='[]'::jsonb where phone='+201000000111';
delete from orders where phone='+201000000111';
```

Full reset file: `scripts/blackbox_reset.sql`.

## 6) Scenario checklist (normal + edge)

Run each as **guest** vs **authed**; check Supabase MCP `supabase_execute_sql` + console for server-authoritative effects (triggers `credit_new_order`, `enforce_order_rate_limit`).

### Auth & RLS
- [ ] Guest can browse `/#/menu` and `/#/home` campaigns but **cannot** place order (RLS → `orders` insert fails, UI should show login prompt).
- [ ] Duplicate phone `+201000000111` rejected on profile save (`customers.phone` UNIQUE + check `^\+20[0-9]{10}$`).
- [ ] Password login with wrong password → 400, no `localStorage` write.
- [ ] Switching role without `localStorage.clear()` leaks previous role → verify bug/fix.
- [ ] Staff cannot access `admin` route, customer cannot access `#/staff` (RLS + router guard).

### Menu → Cart math (§4 + §11.11)
- [ ] Quantity minus disabled at 1, plus increments price linearly.
- [ ] Size `صغير/وسط+10/كبير+15` and add-ons (`+15/+10/+12`) sum correctly — test `35+10+15=60 × qty`.
- [ ] XSS in notes: `<script>alert(1)</script>` + emoji `🎉` — must be escaped, not executed, persists in `orders.notes` and `order_detail_sheet`.
- [ ] Very long note (500+ chars) — truncation or scroll, no overflow.
- [ ] Add same item twice with different modifiers → separate cart lines vs merged? Verify.
- [ ] Empty cart → `متابعة الدفع` hidden/disabled, direct nav to `#/menu`?

### Checkout — mode validation
- [ ] Dine-in without `table_area` → error `حدّد رقم الترابيزة أو المنطقة` (currently persists even after filling — **known bug** see §7).
- [ ] Dine-in with `5` + `داخل` → succeeds, `delivery_fee=0`, `points_preview = round(60/10*1.1)=7`.
- [ ] Pickup without `pickupTiming` (null) → blocked `اختر وقت الاستلام`; with `الآن` (Now, `pickup_slot` null) or explicit slot → succeeds. Default is `الآن` selected, so blocked state is reached via double-tap on `الآن` to deselect (or via pure `CheckoutDraft(mode: pickup, pickupTiming: null)` unit test `candidate.canSubmit` at `lib/ui/cart/checkout_screen.dart:124`).
- [ ] Delivery without address → prompts `add-address`; with address → `delivery_fee=15` (flat, admin-editable), total `subtotal+15`.
- [ ] Points preview rounding: 95 EGP → `round(9.5)=10`; dine-in 90 EGP → `round(9*1.1=9.9)=10`; 49 EGP → `round(4.9)=5` but **no stamp** if `<50` — **49 not achievable via UI** (menu 35/40/45/50 + addons +10/+15/+12 cannot make 49; 35+14 has no combo). Use **35 EGP (<50) as proxy** — verified 35 → 4 pts, no stamp (stamps stayed 1 after #1042). To test 49 specifically, use synthetic subtotal via `supabase_execute_sql` direct `orders` insert or pure `loyalty_rules.earnedFor(subtotal:49)` unit test.

### Orders & Loyalty (server-authoritative — migration 0004)
- [ ] Place dine-in 60 EGP → `loyalty_state.points` +7, `stamps` +1 via trigger `credit_new_order`. Client preview must match trigger math — run `select * from loyalty_state where phone='+201000000111'`.
- [ ] 10th stamp → `completed_cards+1`, `stamps` reset to 0, `vouchers` + free-snack.
- [ ] Every 3rd stamp → `spinner_tokens+1`.
- [ ] Rate limit: 5 orders / 5min via `enforce_order_rate_limit` → 6th should be rejected (check `supabase_query_logs` for `throttle`).
- [ ] Idempotency: double-tap `تأكيد الطلب` within 30s with same `idempotency_key` → only one `orders` row (check `dedup_hash`/`idempotency_key` unique).
- [ ] Realtime: staff tab on `#/staff` sees new order without refresh (orders stream).

### Staff / Driver / Admin
- [ ] Staff `#/staff` → Accept → `in_prep` → `ready` → `done`, plus ETA slider 5–60 and notes field persist (migration 0007).
- [ ] Staff customer lookup `+201000000111` → profile card + manual reward + visit log.
- [ ] Driver `#/driver` sees only assigned deliveries, map hint + external nav handoff.
- [ ] Admin `#/admin` CRUD menu item, validation (`name/price/sort/URL`), delete+undo, toggles `is_available`.
- [ ] Admin loyalty params: change `points_per_10egp`, thresholds 100/150/200, tiers 2000/5000 — verify trigger uses new config.

### i18n / Design
- [ ] Arabic default RTL, EN toggle → no layout break, Western digits `0123` in both (check `35 ج.م` not `٣٥`).
- [ ] Theme tokens only from `core/theme/app_theme.dart` — no raw hex in UI (visual audit).
- [ ] Offline banner + `Failed — Retry` preserves cart (no background retry — `noAutoRetry`). **Do NOT test via `chrome-devtools_emulate Offline` + `navigate reload` — that shows `chrome-error://chromewebdata/` not the app banner. Correct: add to cart → `chrome-devtools_emulate networkConditions=Offline` **without reload** → tap `تأكيد` → expect SnackBar `فشل إرسال الطلب — حاول تاني` + cart intact (1 line), then `networkConditions` back to Online → retry should succeed.**

## 7) Known harness-found issues (2026-08-29)

1. **Dine-in validation banner sticks**: error `حدّد رقم الترابيزة أو المنطقة` remains visible after `table_area` filled and after successful order. Order still creates (`#1030` seen by staff), but UX misleading. Repro: customer `+201000000111` → menu → add `60ج` item → `تأكيد` without table → error → fill `5` + `داخل` → click `تأكيد` again → error still shown, staff sees order. Fix: clear error on `table_area` change or on success.

2. **Staff sees phantom order after customer validation bug**: consequential to #1 — if UI submitted despite error display, staff list shows `الكل (1)` with `جديد` even though customer still on checkout. Not a separate bug but confirms server did accept.

Document any new failures here and file under `test/` with `noAutoRetry` ProviderScope where needed.

## 8) Useful MCP queries

```sql
-- who am I (verify RLS)
select auth.uid(), current_user;
-- loyalty diff after order
select phone, points, stamps, spinner_tokens, vouchers from loyalty_state where phone='+201000000111';
-- recent orders
select display_number, mode, status, subtotal, delivery_fee, total, table_area, points_preview, created_at from orders where phone='+201000000111' order by created_at desc limit 5;
-- risk (if testing promo abuse)
select * from customer_risk_profiles where phone='+201000000111';
-- logs
-- use supabase_query_logs with source='postgres_logs' and filter for "credit_new_order"
```

---

Keep this doc updated when you add new black-box failures. Other agents: start at §3.1, pick a role, and run §6 top-down.
