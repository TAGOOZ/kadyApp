# Supabase Realtime for orders

Orders use Supabase Realtime channels (`orders` table Realtime enabled, Riverpod `StreamProvider` subscription) instead of poll/pull-to-refresh. Chosen because staff/driver/customer must see live status transitions without manual refresh, and Riverpod maps cleanly to streams. Consequence: Realtime must be enabled on the table and RLS must allow `SELECT` for subscribed roles.
