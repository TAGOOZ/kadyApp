# Risk engine — rule-based, server-authoritative

We chose a **rule-based, server-authoritative risk engine** over ML for MVP.

## Why rule-based not ML

- **Explainability**: every `risk_score` decomposes into `risk_reasons` wire codes (`NEW_CUSTOMER +20`, `VERIFIED_PHONE -15`) with fixed scores in `risk_rules`. Staff can explain a held order in plain Arabic without a black box. ML would require feature pipelines, labelled fraud data, and Arabic explanations we don't have.
- **Configurability**: thresholds (`risk.low_max_score=29`, `risk.medium_max_score=59`) and scores live in `app_config` / `risk_rules` and are admin-editable without a redeploy. ML thresholds would require retraining.
- **Determinism**: the same `RiskContext` always yields the same `RiskResult` (pure `calculateRisk` in `lib/domain/risk_engine.dart`, SQL mirror in `evaluate_order_risk_trigger`). Tests assert exact scores (e.g. NEW_CUSTOMER+LARGE_ORDER=35 → medium).
- **Small-data realism**: fraud signals are sparse (Mahmoudia single-branch). ML on ~hundreds of orders/week would overfit; rules capture known patterns (failed deliveries, rapid orders, shared device).

Future: ML can be added as an *additional* rule (`ML_SCORE` with a weight) without touching `risk_engine.dart`'s call sites — the rule catalog accepts new codes without DDL (`risk_events.event_type` is unconstrained).

## Why ManualVerificationProvider first

- **No external dependency**: `ManualVerificationProvider` (RISK-05) creates `verification_requests(status='pending', provider='manual', expires_at=now()+risk.verification_expiry_minutes, code_hash=placeholder SHA256)` with no OTP SMS/WhatsApp call. This keeps the slice shippable while the risk gate is proven.
- **Provider-agnostic abstraction**: `VerificationProvider` / `VerificationService` / `VerificationRepoForProvider` decouples the engine from any OTP channel. `ManualVerificationProvider` fulfils the contract via the `verification_requests` table and staff RPCs `confirm_verification` / `reject_verification`. Adding `WhatsAppVerificationProvider` later requires only a new class and `registerProvider('whatsapp', ...)` — `risk_engine.dart` and `OrdersRepo.placeOrder` stay untouched (see `docs/RISK_VERIFICATION.md` skeleton).
- **Server-authoritative verification**: `code_hash` is never plaintext, even for manual (placeholder hash via `pgcrypto` `digest/sha256`). Status can only move to `confirmed` via `has_any_role(array['staff','admin'])` (42501 otherwise), mirroring `staff_apply_stamp`'s RLS pattern.

## Why trigger ordering (BEFORE INSERT a→b→c)

Postgres fires `BEFORE INSERT` triggers alphabetically. RISK-04 enforces:

1. `trg_a_validate_order_pricing` (0016) — recompute `subtotal/total` from `menu_items.price_egp` so forgery is corrected before scoring.
2. `trg_b_evaluate_order_risk` (0022) — collects `customer_risk_profiles` + `customer_devices` + `addresses` + rapid window, runs the SQL mirror of `calculateRisk`, writes `orders.risk_*` in the same transaction.
3. `trg_c_enforce_order_rate_limit` (0004) — rate limit check last.

`AFTER INSERT` then runs `trg_a_after_create_risk_events` → `trg_b_after_credit_new_order` (WHEN `risk_action != 'needs_verification'`) → `trg_c_after_track_device`. The WHEN guard prevents loyalty credit while an order is held, and `credit_on_verification_approval` (AFTER UPDATE OF `risk_action`) credits idempotently via `processed_orders` when `needs_verification → approved`. This ordering guarantees no partial state: a single transaction contains pricing → risk → rate limit → events → device tracking.

## Why device_id as signal, not proof

- **Shared-device reality in Mahmoudia**: families share phones/tablets, so `MULTIPLE_ACCOUNTS_DEVICE (+10, signal not proof)` must never auto-reject alone. The Dart engine enforces an **extrinsic-only cap**: if every reason is from `{NEW_DEVICE, MULTIPLE_ACCOUNTS_DEVICE, MULTIPLE_ACCOUNTS_ADDRESS, ADDRESS_HIGH_FAILURE}`, the score is clamped to `mediumMaxScore (59)` → at worst `needs_verification`, never `high/rejected`.
- **Privacy-preserving**: `device_id` is a stable `UUID v4` per install (`device_id_provider.dart`), not a hardware identifier, and is nullable. Server derives `deviceCustomerCount` as distinct phones per `device_id` at evaluate time; client never sends counts.
- **Extensibility**: disabling `MULTIPLE_ACCOUNTS_DEVICE` via `risk_rules.enabled=false` removes the signal without code changes; enabling `MULTIPLE_ACCOUNTS_ADDRESS` / `ADDRESS_HIGH_FAILURE` follows the same pattern.

## Consequences

- Dart `lib/domain/risk_engine.dart` and SQL `evaluate_order_risk_trigger` must stay **identical** when changing scores, thresholds, or extrinsic cap (see file headers).
- `risk_events.event_type` is unconstrained text for extensibility; canonical seed codes are documented in the `risk_events` comment.
- `orders.risk_*` and `customer_risk_profiles` counters are mutated only via `SECURITY DEFINER` triggers/functions — no RLS write policy grants client writes (42501 on forgery).
