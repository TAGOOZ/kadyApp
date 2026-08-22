# Single Supabase project for MVP

We run a single Supabase project (`zrlhtwmzuljsqricpxbb`) for dev, staging and prod in v1. Chosen over separate dev/prod projects and over local Docker. Trade-off: simplest secret management (one URL/key in `.env`) and no flavor plumbing, at the cost of shared data during development. Splitting to `kady-dev` / `kady-prod` is deferred to first real customer pilot.
