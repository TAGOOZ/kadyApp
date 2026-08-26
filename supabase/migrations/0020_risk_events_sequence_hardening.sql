-- 0020_risk_events_sequence_hardening.sql — review fix for 0019
-- Tighten sequence grant: authenticated does not need ALL on risk_events_id_seq.
-- 0019 granted ALL to authenticated (over-permissive). Revoke and keep only
-- USAGE+SELECT for currval/nextval if needed, but service_role is sufficient
-- for the SECURITY DEFINER trigger. Also clarify dedup doc.

begin;

-- Revoke the over-permissive grant from 0019 and re-grant minimally.
revoke all on sequence public.risk_events_id_seq from public, anon, authenticated;
grant usage, select on sequence public.risk_events_id_seq to authenticated;
grant all on sequence public.risk_events_id_seq to service_role;

-- Clarify that dedup per order_id means corrections are intentionally ignored.
-- No DDL change to function logic (already fixed in 0019 + direct patch), just comment.
comment on function public.sync_risk_profile() is
  'Centralised post-order outcome sync (RISK-02, 0019+0020): one terminal outcome per order_id forever (done/cancelled). Second terminal transition (e.g. done→cancelled correction) is intentionally ignored — counters and ledger stay at first outcome; manual admin SQL required to correct. Dedup per order_id before counters prevents double total_orders. SECURITY DEFINER so counters are server-authoritative.';

commit;
