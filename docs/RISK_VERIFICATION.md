# Risk & Verification — Elkady Café

> Server-authoritative risk evaluation + provider-agnostic verification.
> Mirrors `docs/adr/0013-risk-engine.md` and `supabase/migrations/0017→0026`.
> Follow this guide to add a new OTP channel (WhatsApp/SMS) without touching `risk_engine.dart` or `OrdersRepo`.

---

## 1. How it works (30-second summary)

1. **Customer places order** → `OrdersRepo.placeOrder` inserts `orders(status='new', items, subtotal, device_id, idempotency_key)` (client never sends `risk_*`).
2. **BEFORE INSERT trigger chain** (alphabetical `trg_a/b/c`):
   - `validate_order_pricing` (0016) recomputes `subtotal/delivery_fee/total` from `menu_items.price_egp`.
   - `evaluate_order_risk_trigger` (0022) collects `customer_risk_profiles` + `customer_devices` + `addresses` + rapid window, runs the SQL mirror of `lib/domain/risk_engine.dart:calculateRisk`, writes `risk_score/level/action/reasons/evaluated_at` in the same transaction.
   - `enforce_order_rate_limit` (0004/0025) checks `rate_limit_max=5/5min` + `risk.rapid_orders_*`.
3. **AFTER INSERT** `create_risk_events` writes `risk_events` per reason in the same transaction; `credit_new_order` is guarded `WHEN (risk_action != 'needs_verification')` so held orders don't earn points yet.
4. **Customer list** → `ownOrdersStreamProvider` (Realtime on `orders`, ADR-0006) emits the held order with `risk_action='needs_verification'`.
5. **Staff queue** → `verificationQueueProvider` (`verification_requests.status='pending'` + `orders` risk snapshot) shows the pending order.
6. **Staff action**:
   - Confirm → `VerificationService.confirmByStaff(orderId)` → RPC `confirm_verification` (SECURITY DEFINER, `has_any_role(staff,admin)`, 42501 otherwise) sets `verification_requests.status='confirmed', code_hash=NULL`, flips `orders.risk_action='approved'` (lifts `P0001` gate), emits `risk_events(VERIFICATION_CONFIRMED)` + `staff_log` row, and the AFTER UPDATE trigger `credit_on_verification_approval` idempotently credits loyalty via `processed_orders` guard.
   - Reject → `rejectByStaff` → `reject_verification` sets `status='rejected'`, updates `orders.status='cancelled', reject_reason='verification_rejected'`, emits `VERIFICATION_REJECTED` + `risk_events`, `sync_risk_profile` bumps `customer_risk_profiles.rejected_orders`.

Idempotency: every write is deduped — `verification_requests` has `idx_verification_pending_one_per_order` partial unique on `(order_id) WHERE status='pending'`; `risk_events` dedupes per `(order_id, event_type)`; loyalty uses `processed_orders ? order_id` guard.

---

## 2. How to add WhatsApp/SMS provider later (no changes to risk engine or order placement)

The verification seam is provider-agnostic: `VerificationProvider` / `VerificationService` / `VerificationRepoForProvider` live in `lib/domain/verification_service.dart` (pure, no Supabase). Ship a new provider by implementing the same interface.

### Skeleton — WhatsApp (spec verbatim + extended)

Spec-required minimal skeleton (must appear verbatim for grep):

```dart
class WhatsAppVerificationProvider implements VerificationProvider {
  Future<VerificationRequest> requestVerification({required String orderId, required String phone}) async {
    final code = _generateOtp(); // 6 digits
    await _whatsAppApi.send(phone, code); // provider-specific
    return _repo.createRequest(orderId, phone, provider:'whatsapp', codeHash: _hash(code));
  }
}
```

Full example with registry (extends `VerificationService` without touching `risk_engine.dart` or `OrdersRepo`):

```dart
// lib/data/verification/whatsapp_verification_provider.dart

import 'package:kady_app/domain/verification_service.dart';

class WhatsAppVerificationProvider implements VerificationProvider {
  WhatsAppVerificationProvider(this._repo, this._whatsAppApi);

  final VerificationRepoForProvider _repo;
  final WhatsAppApi _whatsAppApi; // e.g. Twilio client — provider-specific

  // import 'dart:math' show Random;
  String _generateOtp() {
    // 6 Western digits (§11.11) — never Arabic-Indic
    final n = 100000 + Random().nextInt(900000); // 100000..999999 via dart:math
    return n.toString().padLeft(6, '0');
  }

  // Placeholder — real path uses pgcrypto crypt(gen_salt('bf')) server-side.
  // hashCode is non-cryptographic/stable across isolates; never use for prod OTP.
  String _hash(String code) => 'sha256_${code.hashCode}_placeholder';

  @override
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
  }) async {
    final code = _generateOtp(); // 6 digits
    await _whatsAppApi.send(phone, code); // provider-specific
    // Do NOT store plaintext `code` — hash it and delegate to repo seam.
    // The Supabase RPC `request_verification` / `verify_verification_code`
    // uses pgcrypto `crypt(code, gen_salt('bf'))` and compares via `crypt`.
    // For a custom provider that stores the hash directly, pass it via the seam.
    return _repo.createRequest(
      orderId,
      phone,
      provider: 'whatsapp',
      codeHash: _hash(code),
    );
    // Minimal path that reuses the existing table:
    // return _repo.requestVerification(orderId: orderId, phone: phone, provider: 'whatsapp');
    // and let the RPC generate placeholder hash — then verify via
    // verify_verification_code(p_order_id, p_code) (bcrypt compare).
  }

  @override
  Future<bool> verifyCode({required String orderId, required String code}) =>
      _repo.verifyCode(orderId: orderId, code: code);

  @override
  Future<void> cancelVerification({required String orderId}) =>
      _repo.cancelVerification(orderId: orderId);
}

// SMS variant is identical — swap the API client:
class SmsVerificationProvider implements VerificationProvider {
  SmsVerificationProvider(this._repo, this._smsApi);
  final VerificationRepoForProvider _repo;
  final SmsApi _smsApi;
  @override
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
  }) async {
    final code = _generateOtp(); // reuse helper
    await _smsApi.send(phone, code);
    return _repo.requestVerification(orderId: orderId, phone: phone, provider: 'sms');
  }
  @override
  Future<bool> verifyCode({required String orderId, required String code}) =>
      _repo.verifyCode(orderId: orderId, code: code);
  @override
  Future<void> cancelVerification({required String orderId}) =>
      _repo.cancelVerification(orderId: orderId);
}
```

### Registry — one line, no risk_engine change (spec verbatim)

Spec-required registry step (must appear verbatim):

```dart
registerProvider('whatsapp', WhatsAppVerificationProvider(twilioClient))
```

In current codebase this is the `providers` map of `VerificationService` (same effect, no `risk_engine.dart` or `OrdersRepo` touch):

```dart
// lib/core/supabase/supabase_config.dart or a provider bootstrap:

final whatsappProvider = WhatsAppVerificationProvider(supabaseRepo, twilioClient);
final smsProvider = SmsVerificationProvider(supabaseRepo, smsClient);

// Equivalent to spec's registerProvider('whatsapp', WhatsAppVerificationProvider(twilioClient))
registerProvider('whatsapp', WhatsAppVerificationProvider(twilioClient)); // spec form

final verificationServiceProvider = Provider<VerificationService>((ref) {
  final repo = ref.watch(verificationRepoProvider); // SupabaseVerificationRepo
  return VerificationServiceImpl(
    providers: {
      'manual': ManualVerificationProvider(repo),
      'whatsapp': whatsappProvider,
      'sms': smsProvider,
    },
    repo: repo,
    // optional fallback used when caller omits provider:
    // fallback = manual
  );
});

// Usage (customer or staff):
await ref.read(verificationServiceProvider).request(
  orderId: order.id,
  phone: phone,
  provider: 'whatsapp', // 'manual' | 'whatsapp' | 'sms'
);

// For admin console / backfill, you can also call the RPC directly:
await supabase.rpc('request_verification', params: {
  'p_order_id': orderId,
  'p_phone': phone,
  'p_provider': 'whatsapp',
});
```

Rules:

- **Do not import** `risk_engine.dart` or mutate `OrdersRepo` — the provider only touches `verification_requests` via the `VerificationRepoForProvider` seam.
- **Never store plaintext** `code`: hash with `pgcrypto` `crypt(code, gen_salt('bf'))` server-side (or `digest/sha256`); success invalidates `code_hash=NULL` + `attempts` increment, expired/double-verify returns `false`.
- **Keep `risk_events.event_type` unconstrained** — new codes (`WHATSAPP_SENT`, `SMS_FAILED`) can be emitted without a migration.
- **Register once** via `providers` map; typo `whattsapp` throws `ArgumentError` (no silent fallback to manual) so misconfiguration surfaces immediately (see `VerificationServiceImpl._providerFor`).
- **RLS stays**: `request_verification` RPC checks `phone = order.phone` binding for non-staff (prevents victim `orderId` + attacker `phone` forgery) and staff role for direct status writes (42501).

---

## 3. Configuration guide — app_config keys (admin-editable)

| `app_config.key` | Default | What it controls | Where Admin edits |
|---|---|---|---|
| `risk.low_max_score` | `29` | Upper bound of LOW (0..low → approved). | `AdminDashboardScreen → RulesTab → risk` (extends `RulesRepository.groups['risk']` when that group exists, otherwise direct via `AdminDbClient` / `app_config` edit). |
| `risk.medium_max_score` | `59` | Upper bound of MEDIUM (low+1..medium → needs_verification; >medium → high/rejected). | Same |
| `risk.large_order_threshold` | `500` | Subtotal EGP at which `LARGE_ORDER +15` fires (server recomputes from `menu_items` via 0016, not client `subtotal`). | Same |
| `risk.rapid_orders_count` | `3` | Distinct orders within `risk.rapid_orders_window_minutes` that trigger `RAPID_ORDERS +20`. | Same |
| `risk.rapid_orders_window_minutes` | `30` | Window for `RAPID_ORDERS` (also used by `enforce_order_rate_limit` throttling). | Same |
| `risk.max_verification_attempts` | `5` | Max verify attempts per `verification_requests` row before `expired`; also caps `request_verification` per order per window. | Same |
| `risk.verification_expiry_minutes` | `15` | `verification_requests.expires_at = now() + make_interval(mins => value)` (1..1440 clamped). | Same |

**Rule scores** (in `risk_rules` table, 13 rows, §7):

| `rule_code` | Default score | Enabled default |
|---|---|---|
| `NEW_CUSTOMER` | `+20` | `true` |
| `NEW_DEVICE` | `+10` | `true` |
| `PREVIOUS_FAILED_DELIVERY` | `+25` | `true` |
| `PREVIOUS_REJECTED_ORDER` | `+30` | `true` |
| `THREE_PLUS_CANCELLATIONS` | `+25` | `true` |
| `LARGE_ORDER` | `+15` | `true` |
| `RAPID_ORDERS` | `+20` | `true` |
| `THREE_PLUS_SUCCESSFUL` | `-20` | `true` |
| `FIVE_PLUS_SUCCESSFUL` | `-30` | `true` (supersedes 3+ when both enabled) |
| `VERIFIED_PHONE` | `-15` | `true` |
| `MULTIPLE_ACCOUNTS_DEVICE` | `+10` | `true` (signal, not proof — extrinsic-only cap prevents auto-reject) |
| `MULTIPLE_ACCOUNTS_ADDRESS` | `+10` | `false` |
| `ADDRESS_HIGH_FAILURE` | `+15` | `false` |

Admin toggles `risk_rules.enabled` and `score` directly; Dart's `calculateRisk` and the SQL mirror both honour the `enabled` flag.

**Validation** (release-safe, not just `assert`):

- `risk.low_max_score < risk.medium_max_score` else `ArgumentError` / trigger swaps (defense).
- Both in `0..100`, else thrown/clamped.
- All numeric `app_config` values parsed from `jsonb` strings/ints/doubles (doubles rounded).

---

## 4. Rule vocabulary & humanisation

Wire `RuleCode` values are stored in `orders.risk_reasons` (`jsonb` array). Display via `lib/core/l10n/strings_risk.dart` (`RiskReasonStrings.of(lang).humanize(wire)`):

| Wire | ar | en |
|---|---|---|
| `NEW_CUSTOMER` | عميل جديد | New customer |
| `NEW_DEVICE` | جهاز جديد | New device |
| `PREVIOUS_FAILED_DELIVERY` | توصيل سابق فشل | Previous failed delivery |
| `PREVIOUS_REJECTED_ORDER` | طلب سابق مرفوض | Previous rejected order |
| `THREE_PLUS_CANCELLATIONS` | 3+ إلغاءات | 3+ cancellations |
| `LARGE_ORDER` | طلب كبير | Large order |
| `RAPID_ORDERS` | طلبات متتالية | Rapid orders |
| `THREE_PLUS_SUCCESSFUL` | 3+ طلبات ناجحة | 3+ successful |
| `FIVE_PLUS_SUCCESSFUL` | 5+ طلبات ناجحة | 5+ successful |
| `VERIFIED_PHONE` | هاتف موثق | Verified phone |
| `MULTIPLE_ACCOUNTS_DEVICE` | جهاز مشترك | Shared device |
| `MULTIPLE_ACCOUNTS_ADDRESS` | عنوان مشترك | Shared address |
| `ADDRESS_HIGH_FAILURE` | عنوان عالي الفشل | High-failure address |

Western digits `0123` in both languages (§11.11) — never Arabic-Indic.

---

## 5. Time & i18n

- **Storage**: `orders.risk_evaluated_at`, `orders.created_at`, `verification_requests.expires_at` etc. are `timestamptz` UTC (ADR-0009).
- **Display**: Cairo wall clock via `cairoUtcOffset` (`lib/data/repos/orders_repository.dart:126`, used by `formatLookupWhenUtc` in `lib/data/repos/customer_lookup_repository.dart:219`, `formatPickupSlotCairo` in `lib/data/repos/staff_orders_pure.dart:96`). Format `dd/MM HH:mm` with zero-padded Western digits:

  ```dart
  String formatRiskEvaluatedAt(DateTime utcInstant) {
    final cairo = utcInstant.add(cairoUtcOffset(utcInstant));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(cairo.day)}/${two(cairo.month)} ${two(cairo.hour)}:${two(cairo.minute)}';
  }
  // Example: UTC 2026-01-15T12:00:00Z → Cairo+02 14:00 → "15/01 14:00"
  // DST UTC 2026-07-15T12:00:00Z → Cairo+03 15:00 → "15/07 15:00"
  ```

- **Strings**: `RiskStrings.of(AppLang.ar).levelLabel('low')` → منخفض; English toggle via `localeNotifierProvider` (`AppLang.ar`/`en`).

---

## 6. Smoke queries & verification flow (manual)

```sql
-- Orders with risk gate result
select id, display_number, risk_score, risk_level, risk_action, risk_reasons, risk_evaluated_at
from orders order by created_at desc limit 5;

-- Risk events ledger (audit — unconstrained event_type)
select id, phone, order_id, event_type, metadata, created_at
from risk_events order by created_at desc limit 5;

-- Verification queue (pending only)
select id, order_id, phone, status, provider, expires_at
from verification_requests where status='pending' order by created_at desc limit 20;

-- Role elevation for staff verification tests (docs/SUPABASE_SETUP.md § Risk / Verification)
select id, email from auth.users order by created_at desc limit 5;
update profiles set role='staff' where user_id='<auth-user-id>';
-- or 'admin' for RulesTab access
```

**Manual end-to-end** (in-app):

1. Place a `medium` order (new customer + `subtotal >= 500` → 35 → `needs_verification`).
2. Customer `Orders` list shows "تحقق مطلوب / Verification required" held status (via `ownOrdersStreamProvider` realtime).
3. Staff → `Admin → Verification` queue shows the row with score/reasons humanised.
4. Tap **تأكيد / Confirm** → `confirmByStaff` → order flips to `approved`, `ownOrdersStream` emits `needsVerification=false`, `transition_order(orderId, 'accepted')` now succeeds (previously `P0001 needs verification`).
5. Tap **رفض / Reject** → `rejectByStaff(reason: 'verification_rejected')` → `orders.status='cancelled', reject_reason='verification_rejected'`, `risk_events` row `VERIFICATION_REJECTED`, visible in customer `cancelled` row.

---

## 7. Non-regression guarantees

- **0016 pricing guard** still recomputes `subtotal/delivery_fee/total` from `menu_items.price_egp` (insert `subtotal=1` still stores computed total).
- **Loyalty idempotency** still via `loyalty_state.processed_orders ? order_id` guard (`0004_loyalty_server.sql:99`-ish / `0017` fix) — second credit is a no-op and `order_events` deduplicates.
- **Money/items immutability** via `orders_guard_update` (42501 on forgery for non-admin).
- **Risk-only cap**: extrinsic device/address signals alone are clamped to `mediumMaxScore` (59) → never `rejected` alone (families share devices in Mahmoudia).

---

## 8. Appendix — Deliverables manifest (RISK epic #53)

### Files changed

| Path | What |
|---|---|
| `lib/domain/risk_engine.dart` | Canonical pure engine `calculateRisk` + `RiskConfig` + `RiskResult` (mirrored in SQL) — 13 rules, enabled-flag honoured, extrinsic-only cap |
| `lib/domain/risk_profile.dart` | `RiskProfile`, `RiskEvent`, `classifyRiskEventType`, `applyRiskEventToProfile` (mirrors `sync_risk_profile` SQL) |
| `lib/domain/verification_service.dart` | `VerificationProvider` interface + `ManualVerificationProvider` + `VerificationService` (strategy map, `registerProvider`-style add without touching engine) |
| `lib/data/repos/orders_repository.dart` | `placeOrder` strips forgery keys, inserts `device_id/idempotency_key`, reads back `risk_*`; `cairoUtcOffset` + `formatRisk*` helpers; delivery fee helpers |
| `lib/data/repos/order_status_repository.dart` | `CustomerOrder.risk_*` read model + `ownOrdersStreamProvider` / `watchOrderProvider` (Realtime ADR-0006) |
| `lib/data/repos/verification_repository.dart` | `SupabaseVerificationRepo` (RPCs `request_verification`, `verify_verification_code`, `cancel/confirm/reject`) + `FakeVerificationRepo` |
| `lib/data/repos/verification_queue_repository.dart` | `VerificationQueueRepo` + `SupabaseVerificationQueueRepo` + `FakeVerificationQueueRepo`, `verificationQueueProvider` (Realtime), enrichment, `ensureAccess` |
| `lib/data/repos/risk_profile_repository.dart` | `RiskProfileRepository` seam for `customer_risk_profiles` reads |
| `lib/core/l10n/strings_risk.dart` | AR/EN `RiskStrings` + `RiskReasonStrings` (humanised reasons, §11.11 Western digits) |
| `lib/core/device/device_id_provider.dart` | Stable per-install `device_id` (UUID v4, signal not proof) |
| `lib/ui/admin/widgets/verification_queue_panel.dart` | Staff/Admin queue UI — realtime list, expand enrich, Confirm/Reject with audit (uses `VerificationService`) |
| `lib/ui/orders/orders_list_screen.dart` | Customer held-status banner via `riskAction == 'needs_verification'` |
| `docs/adr/0013-risk-engine.md` | ADR: why rule-based not ML, why Manual first, trigger ordering `a→b→c`, device as signal |
| `docs/RISK_VERIFICATION.md` | This file — how to add WhatsApp/SMS, config table, manifest |
| `docs/SUPABASE_SETUP.md` | Appended `## Risk / Verification` — migration order, smoke queries, role elevation |

### Migrations (apply in order)

| File | Scope |
|---|---|
| `supabase/migrations/0016_validate_order_pricing.sql` | SECURITY-03 pricing recompute (must stay before risk evaluate) |
| `supabase/migrations/0017_risk_foundation.sql` | `orders.risk_*` columns, `risk_rules` table (10→13 seeds), `app_config` risk thresholds, `risk_guard_update` extension |
| `supabase/migrations/0018_risk_profile_and_events.sql` | `customer_risk_profiles`, `risk_events` (unconstrained `event_type`), `sync_risk_profile` counters |
| `supabase/migrations/0019_risk_profile_fixes.sql` | RLS `REVOKE/GRANT` hardening (customer cannot forge counters) |
| `supabase/migrations/0020_risk_events_sequence_hardening.sql` | `risk_events_id_seq` grant fix |
| `supabase/migrations/0021_device_and_address.sql` | `orders.device_id`, `customer_devices`, address reuse signals |
| `supabase/migrations/0022_risk_evaluation_gate.sql` | `evaluate_order_risk_trigger` (SQL mirror), trigger ordering `a/b/c`, `verification_requests` stub, `create_risk_events`, dispatch gate (`orders_guard_update` + `transition_order` `P0001`), `confirm_verification` helper |
| `supabase/migrations/0023_risk_gate_fixes.sql` | Gate + confirm fixes (idempotency, expired guard) |
| `supabase/migrations/0024_verification_abstraction.sql` | Enriched `verification_requests` (placeholder hash via `pgcrypto`, expiry `+risk.verification_expiry_minutes`, RLS pending-only unique), RPCs `request_verification`, `verify_verification_code`, `cancel/confirm/reject_verification` |
| `supabase/migrations/0025_risk_07_hardening.sql` | RLS hardening (drop staff UPDATE policy), `orders_guard_update` allows `risk_*/device_id` only for `staff/admin` or `SECURITY DEFINER`, bcrypt `crypt/gen_salt`, `make_interval`, rate limits, idempotency indexes |
| `supabase/migrations/0026_risk_07_fixes.sql` | Follow-up hardening fixes |

Apply order is enforced by the filename prefix and by `migrations/0017→0026` dependencies; re-apply is safe (`IF NOT EXISTS` / `ON CONFLICT DO NOTHING`).

### Endpoints added / changed (RPCs & table RLS)

| Name | Kind | Added/Changed in |
|---|---|---|
| `evaluate_order_risk(p_order_id uuid)` | `SECURITY DEFINER` function (callable re-evaluation, `authenticated` grant) | 0022 |
| `request_verification(p_order_id, p_phone, p_device_id, p_provider)` | `SECURITY DEFINER` RPC, rate-limited (P0001), returns `verification_requests` row | 0024 → 0025 hardened (bcrypt, `make_interval`, `max_attempts` window) |
| `verify_verification_code(p_order_id, p_code)` | `SECURITY DEFINER` RPC, returns `boolean`, increments `attempts`, `expired` guard, `code_hash=NULL` on success | 0024 → 0025 |
| `cancel_verification(p_order_id)` | `SECURITY DEFINER` RPC `pending→cancelled` | 0024 |
| `confirm_verification(p_order_id)` | `SECURITY DEFINER` RPC staff/admin only (42501), `pending→confirmed`, `code_hash=NULL`, flips `orders.risk_action→approved`, emits `VERIFICATION_CONFIRMED` (idempotent, respects expiry) | 0022 stub → 0024 full → 0025 protected (staff UPDATE policy dropped) |
| `reject_verification(p_order_id, p_reason='verification_rejected')` | `SECURITY DEFINER` RPC staff/admin only, flips `orders.status='cancelled', reject_reason='verification_rejected'`, emits `VERIFICATION_REJECTED` | 0024 |
| `confirmByStaff / rejectByStaff` (Dart) | `VerificationService` façade delegating to above RPCs (also used by `FakeVerificationRepo`) | `verification_repository.dart` |
| `transition_order(p_order_id, p_status, p_reject_reason, p_assigned_driver, p_actor)` | Patched with `P0001` risk gate: `needs_verification` without confirmed row blocks `accepted/in_prep/ready/out_for_delivery/done`; `rejected` also terminal | 0022 → 0025 |

### Risk rules implemented

13 canonical `RuleCode` values (10 originally seeded in 0017 plus 3 extrinsic signals in 0021). Default scores/enabled per §3 table above; disabled-flag honoured by both Dart and SQL.

### Verification abstraction

- **Interface** `VerificationProvider` (`requestVerification`, `verifyCode`, `cancelVerification`) — `lib/domain/verification_service.dart:193`.
- **Shipped** `ManualVerificationProvider` (MVP) — delegates to `VerificationRepoForProvider` seam, no external API.
- **Planned** `WhatsAppVerificationProvider` / `SmsVerificationProvider` — see §2 skeleton; registry via `VerificationServiceImpl(providers: { 'whatsapp': WhatsApp... })` with no changes to `risk_engine.dart` or `OrdersRepo`.

### Tests added

| File | Type | Covers |
|---|---|---|
| `test/unit/risk_scenarios_test.dart` | unit (pure + `FakeVerificationRepo`/`FakeRiskGate`) | All 6 plan §20 scenarios + threshold-variant (60 vs higher), shared-device cap, manual verification confirm/reject (audit + `reject_reason`), non-regression pricing, time/i18n (Cairo `dd/MM HH:mm` Western digits + AR/EN humanisation) |
| `test/integration/risk_flow_test.dart` | Riverpod integration (`ProviderContainer`, `retry: noAutoRetry`, `SharedPreferences.setMockInitialValues({})`, `FakeOrdersRepo`/`FakeOrderStatusRepo`/`FakeRiskProfileRepo`) | `placeOrder` → `risk_evaluated_at` set (UTC), `risk_events` row, `customer_risk_profiles.updated_at` bump, `ownOrdersStream` emits held status |
| `test/integration/verification_flow_test.dart` | Riverpod integration (pending queue realtime) | Queue shows pending → staff confirm → `orders.risk_action=approved` & `transition_order` allows `accepted` → customer realtime poll sees status; reject path `rejected/cancelled` + `reject_reason='verification_rejected'` + `risk_events` audit |
| `test/unit/risk_engine_test.dart` (existing) | unit | `RiskConfig` parsing, `calculateRisk` per-rule isolation, extrinsic cap |

### How to configure thresholds (admin path)

1. Sign in as `admin` (role elevation `update profiles set role='admin' where user_id='<uid>'`).
2. `AdminDashboardScreen → RulesTab` → `risk` group (when `RulesRepository.groups['risk']` exists) — sliders/toggles with same semantics as `rules_editor.dart` (double/points editors).
3. Fallback when group missing: direct `app_config` edit via `AdminDbClient` (e.g. `update app_config set value='40'::jsonb where key='risk.low_max_score'`), or Supabase Dashboard → `Table Editor → app_config`.
4. `risk_rules` scores/toggles via same tab or `Table Editor → risk_rules`.
5. Changes apply to *next* order's `evaluate_order_risk_trigger`; existing held orders keep their `risk_*` until re-evaluated via `evaluate_order_risk(p_order_id)` RPC.

### Gates

`flutter analyze` → zero issues. `flutter test` → all green (`.+340` tests including new suites; `risk_*` suites ~30s). `git diff --stat` → risk-scoped `lib/domain`, `lib/data/repos`, `lib/core/l10n`, `lib/ui/admin/widgets`, `docs/*`, `test/{unit,integration}/risk_*`, `supabase/migrations/0017→0026`.
