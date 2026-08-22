# go_router for navigation

We chose `go_router` over `auto_route` and raw `Navigator 1.0`. Needed declarative, deep-link-ready routes with role-guarded branches (customer/staff/driver/admin shells) and easy integration with Riverpod auth state for redirects. Consequence: `lib/core/router.dart` is the single route table; no imperative `push` outside it.
