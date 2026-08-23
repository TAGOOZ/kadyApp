# Riverpod 3 with auto-retry disabled

We migrated flutter_riverpod 2.6 → 3.x (improve-audit finding #10) and disabled
its new provider auto-retry globally (`ProviderScope(retry: noAutoRetry)`,
`lib/core/riverpod_retry.dart`). Rationale: rp3's default backoff (≈10 attempts)
masks our error UX — permission lock panels and retry banners must render
immediately (audit findings #8/#9), and non-transient errors like
StaffPermissionException should never be retried. Our standard error policy is
manual retry controls + offline banner. If transient-failure auto-retry is
wanted later, add a selective strategy that skips typed permission exceptions
instead of re-enabling the global default.
