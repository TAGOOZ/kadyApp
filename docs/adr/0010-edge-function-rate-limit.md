# Edge Function rate limit for orders

Spam protection is enforced server-side via a Supabase Edge Function that rate-limits order creation per `google_user_id`/`phone` (e.g. max 5 orders / 5 min). Chosen over app-side debounce alone and over no throttle. Trade-off: requires an Edge Function and a small lookup table, but prevents fake-order floods even if the client is bypassed. App still shows a 30s button debounce for instant UX.
