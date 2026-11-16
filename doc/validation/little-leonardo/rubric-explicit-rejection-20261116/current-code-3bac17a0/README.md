# Explicit rubric rejection evidence

This folder records native UI evidence for PR #435 at product source `3bac17a0c6f3e8e5b60f8be2b8e525f1f067b7b8`.

The English UI test passed and captured HTTP 503, HTTP 413, and terminal HTTP 409 states. The host fixture confirms one stable request ID and no automatic response POST after either explicit 503 rejection or 413; HTTP 409 followed a deliberate Retry. The retained draft JSON proves the 413 response remains in `pendingSend` with `requiresUserRetry: true` and the response preserved.

The Spanish UI run failed before XCTest could launch the app. CoreSimulator could not install the app because its placeholder promise was missing. This is recorded as a runner failure, not a product failure; no Spanish screenshot is claimed. The owner asked us not to repeat the failed runner attempt.
