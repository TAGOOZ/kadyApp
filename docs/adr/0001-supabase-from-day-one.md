# Supabase from day one

We started with a local-only plan (ADR 0001 draft) but the owner provided a live Supabase project (`zrlhtwmzuljsqricpxbb`) immediately, so v1 is built directly against Supabase via `supabase_flutter` + Riverpod. Repository interfaces stay, but implementations are Supabase-backed from slice #001 onwards. Consequence: cross-device sync (customer → staff → driver) works from day one; OTP remains simulated (`123456`) until Supabase phone auth is configured; publishable key + URL are bundled in-app (public), secret key stays server-only in `.env`.
