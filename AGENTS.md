# AGENTS.md

Guide for AI agents working in this repo. Read this before changing anything.

## Project

**Elkady Café** — Flutter app (customer ordering + loyalty/gamification + staff/driver/admin), Arabic-first RTL. Backend: Supabase (`zrlhtwmzuljsqricpxbb`), Postgres triggers are **server-authoritative** for loyalty.

## Commands

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
flutter analyze        # gate: zero issues
flutter test           # gate: all green (~302 tests)
flutter run -d chrome --web-port 8080   # OAuth origin is pinned to :8080
```

## Docs map (read what your task touches)

| Doc | What's in it |
|---|---|
| `CONTEXT.md` | Domain glossary — Customer/Guest/Staff/Driver/Order/Stamp/Points/Voucher… use these words |
| `docs/FEATURES.md` | Full product spec; **§11 = locked decisions** — do not violate |
| `docs/adr/0001–0013` | Why things are the way they are (Supabase day-one, Riverpod 3, go_router, layer-first, RLS by google_user_id, UTC storage, no-auto-retry…) |
| `docs/DESIGN.md` | Heritage Hearth design system: tokens, type scale, contrast ledger, motion rules |
| `plans/README.md` | improve-skill audit index (all DONE) |

## Layout (layer-first)

```
lib/
  core/     theme/app_theme.dart (ONLY place for colors/fonts) · l10n/ · router.dart · supabase/ · riverpod_retry.dart
  domain/   pure logic + controllers (loyalty_rules.dart = canonical rule math)
  data/     models + repositories (db-seam interface → Supabase adapter pattern)
  ui/       screens & widgets per feature (home/menu/cart/orders/games/quests/profile/staff/lookup/driver/admin/auth)
test/       mirrors lib/ ; fakes implement db seams — never hit network in tests
supabase/migrations/  0001 init · 0002 driver RLS · 0003 order-update hardening · 0004 server-side loyalty  ← ALL APPLIED LIVE
```

## Non-negotiables

1. **Arabic default, RTL-first**, English toggle second. All copy lives in per-feature `strings_*.dart` catalogs keyed by `AppLang{ar,en}` — never inline strings in widgets. **Western digits `0123` in both languages** (§11.11).
2. **Theme tokens only** from `core/theme/app_theme.dart`. No raw hex/fontSize outside it. Contrast: body ≥4.5:1 (`textMuted #55605B` for secondary copy, never `outline`).
3. **Phone number is the Customer key** (one customer per phone). Google OAuth is the anti-fake gate; orders require auth (guests cannot order — enforced by RLS).
4. **Loyalty is server-authoritative**: `credit_new_order` / `staff_apply_stamp` / `enforce_order_rate_limit` Postgres triggers own all crediting and rate limits. The client only previews and resyncs via `refreshFor()`. Never add client-side point/stamp persistence.
5. Canonical stamp rule (complete+reset at 10, every-3rd spinner token) exists twice ON PURPOSE: Dart `loyalty_rules.dart` (pure, tested) and SQL `apply_stamps()` (migration 0004). Keep them identical when changing either.
6. **Riverpod 3** with global `retry: noAutoRetry` (main.dart) so error UI renders instantly. Tests that assert error states must pass `retry: noAutoRetry` on their own ProviderScope.
7. Realtime on `orders` is how staff/driver/customer stay in sync — don't add polling.
8. Time: store UTC (`timestamptz`), display Africa/Cairo.

## Supabase

- Migrations 0001–0004 are **applied live**. New migrations: add file under `supabase/migrations/`, apply via the supabase MCP tools (OAuth-authed to the right account), then verify with `execute_sql`.
- Keys in `.env` (gitignored): URL + publishable key are bundled in-app by design; secret key must never leave the server side.
- Role elevation for testing staff/admin features:
  ```sql
  update profiles set role='staff' where user_id='<auth-user-id>';
  ```
- Rate limit / thresholds / reward costs live in `app_config` rows — admins edit them via the admin dashboard (#015).

## Workflow conventions

- One slice per branch/worktree: `feat/NNN-slug`; commit `feat(0NN): summary`; merge with `--no-ff`.
- Gates before any commit: `flutter analyze` zero issues + `flutter test` all green.
- Widget tests: `SharedPreferences.setMockInitialValues({})` when locale/session providers hydrate; override repositories with fakes (see existing `*_test.dart` patterns); tall viewport (`tester.view.physicalSize`) when asserting below-the-fold ListView items.
- Don't touch `.env`, `android/ios/web` platform configs, or GitHub issues unless asked.
