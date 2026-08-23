# Plan 004: Order-status surfaces follow the language toggle

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0c1e59d..HEAD -- lib/ui/orders/order_status_screen.dart lib/ui/orders/widgets/driver_card.dart lib/ui/orders/widgets/status_timeline.dart test/widget/order_status_screen_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Why this matters

The app is Arabic-first with an English toggle (FEATURES §0; every other top-level screen watches `localeNotifierProvider`). The order-status screen and its driver card hardcode `AppLang.ar`, so a customer who switched to English still sees the entire status timeline, delivered snackbar, and driver card in Arabic — on the single most emotionally important screen of the ordering flow. The fix threads the already-existing locale state through three files and adds one pure label-picker that is trivially unit-testable.

## Current state

Relevant files:

- `lib/ui/orders/order_status_screen.dart` — screen + `_Body`; hardcodes Arabic in 3 places.
- `lib/ui/orders/widgets/driver_card.dart` — hardcodes `AppLang.ar`.
- `lib/ui/orders/widgets/status_timeline.dart` — renders `step.labelAr` unconditionally (:144).
- `lib/domain/order_status_flow.dart` — `FlowStep` carries BOTH `labelAr` and `labelEn` (:48-60); steps built per mode (:62-169).
- `test/widget/order_status_screen_test.dart` — existing widget tests to keep green.
- Locale source: `localeNotifierProvider` in `lib/domain/session_controller.dart` ecosystem (`ref.watch(localeNotifierProvider).code` / `AppLang`), used identically by e.g. `lib/ui/cart/cart_screen.dart`.

Excerpts verified at commit `0c1e59d`:

`order_status_screen.dart:108-118` — build() ignores session locale:

```dart
  @override
  Widget build(BuildContext context) {
    final strings = OrdersStringsCatalog.of(AppLang.ar);
    final orderAsync = ref.watch(watchOrderProvider(widget.orderId));
```

`order_status_screen.dart:93-105` — delivered snackbar hardcoded:

```dart
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        ...
          OrdersStringsCatalog.of(AppLang.ar)
              .deliveredBanner(doneStep?.labelAr ?? ''),
```

(also uses `doneStep?.labelAr`).

`order_status_screen.dart:143-160` (`_Body.build`) — second hardcoded catalog plus Arabic step labels:

```dart
    final strings = OrdersStringsCatalog.of(AppLang.ar);
    ...
    _DeliveredBanner(label: steps[currentIndex].labelAr),
```

`driver_card.dart:26-27`:

```dart
    final strings = OrdersStringsCatalog.of(AppLang.ar);
```

`status_timeline.dart:144`:

```dart
                      step.labelAr,
```

`order_status_flow.dart:46-60` — both labels already exist on each step:

```dart
class FlowStep {
  const FlowStep({
    required this.status,
    required this.labelAr,
    required this.labelEn,
    required this.icon,
  });
  final OrderWireStatus status;
  final String labelAr;
  final String labelEn;
  final IconData icon;
}
```

Conventions to follow:

- Screens watch `final lang = ref.watch(localeNotifierProvider);` then pick catalogs via `XxxCatalog.of(lang)` — copy the exact pattern from `lib/ui/cart/cart_screen.dart`.
- Pure helpers belong in the domain layer (`order_status_flow.dart`) so they are unit-testable without Flutter bindings (see its header contract, :1-4).
- DESIGN.md copy rules: errors say what happened + what next; sheet-dismiss wording — no copy changes needed here, only language routing.

## Commands you will need

| Purpose   | Command                    | Expected on success                                  |
|-----------|----------------------------|------------------------------------------------------|
| Analyze   | `flutter analyze`          | `No issues found!`                                    |
| All tests | `flutter test`             | ends `All tests passed!` (baseline +277 at plan time) |
| One file  | `flutter test test/widget/order_status_screen_test.dart` | all pass |

## Scope

**In scope** (the only files you should modify):

- `lib/domain/order_status_flow.dart` (add one pure extension/getter)
- `lib/ui/orders/order_status_screen.dart`
- `lib/ui/orders/widgets/driver_card.dart`
- `lib/ui/orders/widgets/status_timeline.dart` (accept resolved labels or an `AppLang`)
- `test/unit/order_status_flow_test.dart` (new cases for the label picker)
- `test/widget/order_status_screen_test.dart` (only if a pump needs a locale override)

**Out of scope** (do NOT touch):

- `OrdersListScreen`, confirmation screen, staff/driver boards — they already route locale (verified: all reference `localeNotifierProvider`).
- Any string VALUES inside `strings_orders.dart` — routing only, no copy edits.
- Realtime wiring, providers, timeline timestamp logic.

## Git workflow

- Branch: `advisor/004-order-status-locale`
- One commit per file-cluster; style like `fix(006): status timeline follows locale toggle`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Pure label picker in the domain layer

In `lib/domain/order_status_flow.dart` add:

```dart
extension FlowStepX on FlowStep {
  /// Pre-localized label per app language (catalog-free, pure).
  String label(AppLang lang) => lang == AppLang.ar ? labelAr : labelEn;
}
```

`AppLang` lives in `core/l10n/app_strings.dart`. Importing it here introduces the file's first core import beyond `Icons` — acceptable (type-only dependency, no Flutter widgets beyond IconData already imported). If the analyzer complains about layering, instead add a top-level function `String flowStepLabel(FlowStep step, AppLang lang)` in the same file.

**Verify**: `flutter analyze` → `No issues found!`; `flutter test test/unit/order_status_flow_test.dart` → existing tests pass.

### Step 2: Route locale through the screen

In `order_status_screen.dart`:

1. In `build()` (:108): `final lang = ref.watch(localeNotifierProvider);` then `final strings = OrdersStringsCatalog.of(lang);`. Import comes from the same module used by cart_screen.
2. Same replacement inside `_onOrderData`'s snackbar (:97) — use the watched value. `_onOrderData` runs inside `ref.listen` callbacks where `context` is available but you should capture `lang` at listen setup OR read once via `ref.read(localeNotifierProvider)` inside the callback (read is correct for event handlers).
3. In `_Body.build` (:145): same watch + catalog swap; pass `lang` down:
   - `_DeliveredBanner(label: steps[currentIndex].label(lang))`,
   - `StatusTimeline(..., lang: lang)` (Step 3),
   - `DriverCard(..., lang: lang)` (Step 4).
4. Keep the cancelled-label strings coming from the catalog as today (they already route through `strings.cancelledChip`).

**Verify**: `flutter analyze` → `No issues found!`; `flutter test test/widget/order_status_screen_test.dart` → all pass (existing tests pump Arabic default; nothing should break).

### Step 3: `StatusTimeline` takes the language

Add `required this.lang` (`AppLang`) to `StatusTimeline`'s constructor and replace line :144's `step.labelAr` with `step.label(lang)`. Update the call site from Step 2. Default-free — force callers to be explicit so this class of bug can't silently return.

**Verify**: `flutter analyze` → `No issues found!`

### Step 4: `DriverCard` takes the language

Same pattern: constructor param `required this.lang`, replace `OrdersStringsCatalog.of(AppLang.ar)` (:27) with `.of(lang)`. Update the Step-2 call site.

**Verify**: `flutter analyze` → `No issues found!`; full `flutter test` → `All tests passed!`.

### Step 5: Pin with tests

1. Unit: in `test/unit/order_status_flow_test.dart` add cases asserting `flowStepLabel`/`FlowStepX.label` returns Arabic text for `AppLang.ar` and English for `AppLang.en` on one dine-in step (e.g. received: 'تم الاستلام' vs 'Received').
2. Widget: extend `test/widget/order_status_screen_test.dart` with ONE case pumping under an overridden `localeNotifierProvider` state of `AppLang.en` (follow how `test/unit/locale_test.dart`/profile language tests override it) asserting an English step label ('Received') renders.

**Verify**: `flutter test` → count ≥ baseline + 2, all green.

## Test plan

- New cases from Step 5 (pure picker ar/en + one EN-mode widget render).
- Patterns: `test/unit/order_status_flow_test.dart` (pure), `test/widget/order_status_screen_test.dart` (widget pumps with provider overrides).
- Verification: full suite exits 0; ≥2 new tests.

## Done criteria

- [ ] `flutter analyze` exits 0 printing `No issues found!`
- [ ] `grep -n "AppLang.ar" lib/ui/orders/order_status_screen.dart lib/ui/orders/widgets/driver_card.dart lib/ui/orders/widgets/status_timeline.dart` returns NO matches
- [ ] Full suite ≥ baseline + 2 new tests, all passing
- [ ] No files outside the in-scope list modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Excerpts don't match live tree (drift past `0c1e59d`).
- Forcing `lang` through `StatusTimeline`/`DriverCard` breaks OTHER call sites not listed above (search first: `grep -rn "StatusTimeline(\|DriverCard(" lib/`) — report the extra callers rather than editing out-of-scope files.
- Widget override of `localeNotifierProvider` proves impossible without restructuring session hydration — report.

## Maintenance notes

- Any future orders-surface widget must take `AppLang` explicitly; consider a reviewer checklist line for it.
- If deep links land (unresolved item in FEATURES §11), this screen is the entry point — locale routing added here is exactly what a cold-start deep link needs.
- Reviewer focus: confirm no behavioral change when locale == ar (byte-identical output) and that realtime listeners were untouched.
