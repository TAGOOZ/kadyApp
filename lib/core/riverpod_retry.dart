/// Riverpod 3 retry hook — `null` stops the retry loop immediately.
///
/// Riverpod 3 auto-retries failing providers (up to ~10 backoff attempts),
/// which masks our error UX: permission lock panels and retry banners must
/// render immediately (audit #8/#9 contracts; ADR-0013). Our standard error
/// policy is manual retry + offline banner, so auto-retry stays off.
Duration? noAutoRetry(int retryCount, Object error) => null;
