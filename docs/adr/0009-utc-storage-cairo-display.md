# UTC storage, Africa/Cairo display

All timestamps (`orders.created_at`, `pickup_slot`, `campaign windows`) are stored as `timestamptz` UTC in Supabase. Flutter formats with `Africa/Cairo` offset for display. Chosen over storing Cairo local or bare strings to keep sorting correct across DST and to allow future multi-branch timezones. Consequence: every read formats via `toLocal()` with Cairo.
