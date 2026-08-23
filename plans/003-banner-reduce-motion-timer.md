# Plan 003: Banner carousel honors reduce-motion after touch — and derives page count from data

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0c1e59d..HEAD -- lib/ui/home/widgets/banner_carousel.dart test/unit/banner_dots_test.dart test/widget/home_screen_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0c1e59d`, 2026-08-23

## Why this matters

`docs/DESIGN.md` (Motion section) makes a hard house rule: "Banner carousel: auto-advance timer never starts under reduce-motion." The widget honors that only in `didChangeDependencies`. The moment a reduce-motion customer touches the carousel (any swipe or tap-drag), `onPointerUp` restarts the 5-second auto-advance timer unconditionally — the banned animation starts anyway. The same file also hardcodes the banner count (`count: 3`) instead of using the list length, so adding/removing a localized banner silently corrupts advance math.

## Current state

Relevant files:

- `lib/ui/home/widgets/banner_carousel.dart` — the whole fix lives here.
- `lib/core/l10n/strings_home.dart:116-120` — `banners` getter returns exactly 3 pairs today.
- `test/unit/banner_dots_test.dart` — existing pure-math tests for `nextBannerIndex`/dots.

Excerpts verified at commit `0c1e59d`:

`banner_carousel.dart:50-60` — the only reduce-motion guard:

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion customers get a static first banner: no timer, no
    // auto-advance animation.
    if (MediaQuery.of(context).disableAnimations) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null || !_timer!.isActive) {
      _startTimer();
    }
  }
```

`banner_carousel.dart:69-79` — `_startTimer` checks nothing about motion:

```dart
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.autoAdvance, (_) {
      if (!_controller.hasClients) return;
      final target = nextBannerIndex(current: _index, count: 3);
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }
```

`banner_carousel.dart:89-92` — pointer handlers bypass the guard:

```dart
        Listener(
          onPointerDown: (_) => _timer?.cancel(),
          onPointerUp: (_) => _startTimer(),
          onPointerCancel: (_) => _startTimer(),
```

DESIGN.md constraint being violated (quote): "**Every looping/auto animation respects `MediaQuery.disableAnimations`:** … Banner carousel: auto-advance timer never starts under reduce-motion."

Conventions to follow:

- Motion curves: `easeOutCubic` family only (already used at :77).
- Pure math extracted for unit tests (`nextBannerIndex`, :13-16) — keep any new decision logic equally extractable.
- Existing widget-test style: see `test/widget/home_screen_test.dart` for pumping with `MediaQuery` overrides.

## Commands you will need

| Purpose   | Command                    | Expected on success                                  |
|-----------|----------------------------|------------------------------------------------------|
| Analyze   | `flutter analyze`          | `No issues found!`                                    |
| All tests | `flutter test`             | ends `All tests passed!` (baseline +277 at plan time) |
| One file  | `flutter test test/widget/banner_carousel_test.dart` (created in Step 3) | all pass |

## Scope

**In scope** (the only files you should modify):

- `lib/ui/home/widgets/banner_carousel.dart`
- `test/widget/banner_carousel_test.dart` (create)
- `test/unit/banner_dots_test.dart` (only if you add a count-guard case)

**Out of scope** (do NOT touch):

- `lib/core/l10n/strings_home.dart` — banner content/count is a copy decision.
- Any other looping animation (order timeline pulse, confetti, menu shimmer) — each already handles reduce-motion; verified at `order_status_screen.dart:62-70`.
- Gradient constants (:123-139) — AA contrast ledger territory, recently polished.

## Git workflow

- Branch: `advisor/003-banner-reduce-motion`
- One or two commits; style like `fix(home): keep banner timer stopped under reduce-motion after touch`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Gate `_startTimer` on the current motion setting

Change `_startTimer` to consult `MediaQuery.disableAnimations` before starting, and derive count from data:

```dart
  void _startTimer() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _timer?.cancel();
    _timer = Timer.periodic(widget.autoAdvance, (_) {
      if (!_controller.hasClients) return;
      final banners = widget.strings.banners;
      final target = nextBannerIndex(current: _index, count: banners.length);
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }
```

This single guard fixes the bug: every call site (`didChangeDependencies`, both pointer handlers) now funnels through it. Keep the existing `didChangeDependencies` cancel branch as-is (it also STOPS an already-running timer when the setting flips on).

Note: `MediaQuery.maybeDisableAnimationsOf(context)` is legal inside State methods that have access to `context` — `_startTimer` is only ever called with the element mounted (init/didChangeDependencies/pointer handlers). If the analyzer flags use-of-context in a callback, capture `final reduceMotion = MediaQuery.of(context).disableAnimations;` into a field `_reduceMotion` updated in `didChangeDependencies` and check the field instead.

**Verify**: `flutter analyze` → `No issues found!`

### Step 2: Widget test pinning the contract

Create `test/widget/banner_carousel_test.dart` following the override/pump patterns of `test/widget/home_screen_test.dart`:

1. Test A (the regression): pump `BannerCarousel` inside a `MaterialApp` whose `builder` wraps the child in `MediaQuery(data: …copyWith(disableAnimations: true))`; provide a short `autoAdvance` (e.g. 50 ms); simulate a drag on the `PageView` (`tester.drag(find.byType(PageView), const Offset(-400, 0))`) then `await tester.pump(const Duration(milliseconds: 300))`; assert no further page change occurs across another `pump(200 ms)` window (page index stays where the drag left it).
2. Test B (motion-on sanity): same setup with `disableAnimations: false`, `autoAdvance: 10 ms`, pump ~100 ms → page advanced at least once beyond the initial index.
3. Use string keys already present (`home_banner_dots`) or `find.byType(PageView)`; do not add new localization strings.

**Verify**: `flutter test test/widget/banner_carousel_test.dart` → 2 passing tests.

### Step 3: Full suite

**Verify**: `flutter test` → ends `All tests passed!` with count ≥ baseline + 2.

## Test plan

- Tests described in Step 2: reduce-motion persistence after interaction (the regression), plus motion-on auto-advance sanity so the guard can't silently over-block.
- Structural pattern: `test/widget/home_screen_test.dart` (ProviderScope-free stateful widget pumping, MediaQuery handling).
- Verification: full suite green; new file contains exactly the two tests.

## Done criteria

- [ ] `flutter analyze` exits 0 printing `No issues found!`
- [ ] `grep -n "count: 3" lib/ui/home/widgets/banner_carousel.dart` returns no matches
- [ ] Every `_startTimer` path is guarded (single guard at function head)
- [ ] Both new widget tests pass; full suite ≥ baseline + 2
- [ ] No files outside the in-scope list modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- The excerpted code doesn't match (drift past `0c1e59d`).
- Gating `_startTimer` breaks the `didChangeDependencies` motion-OFF→ON transition in a way not fixable without restructuring lifecycle handling — report.
- Widget test cannot observe page position deterministically under the pump timings (flaky across two runs) — report instead of loosening assertions to vacuity.

## Maintenance notes

- If banners become server-driven (campaigns table), `banners.length` derivation already future-proofs the advance math; only the empty-list case would matter (`nextBannerIndex` returns 0 safely).
- Reviewer focus: confirm no OTHER auto-starting timer was introduced and that the pointer-cancel path still stops jitter on abandoned drags.
