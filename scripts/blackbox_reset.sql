-- blackbox_reset.sql — run via Supabase MCP supabase_execute_sql between suites
-- Keeps blackbox users/phones, wipes orders/loyalty so scenarios are deterministic

-- keep only blackbox + owner phones
delete from public.order_events where order_id in (select id from public.orders where phone not in ('+201000000111','+201000000222','+201000000333','+201000000444','+201211310357','+201112310357'));
delete from public.risk_events where phone not in ('+201000000111','+201000000222','+201000000333','+201000000444','+201211310357','+201112310357');
delete from public.orders where phone in ('+201000000111','+201000000222','+201000000333','+201000000444');
delete from public.verification_requests where phone in ('+201000000111','+201000000222','+201000000333','+201000000444');
delete from public.customer_devices where phone in ('+201000000111','+201000000222','+201000000333','+201000000444');

-- reset loyalty for blackbox customer (use this for stamp/points edge cases)
update public.loyalty_state set points=0, lifetime_points=0, stamps=0, completed_cards=0, spinner_tokens=0, match_tokens=0, scratch_tokens=0, vouchers='[]'::jsonb, processed_orders='[]'::jsonb where phone='+201000000111';
-- ensure address exists for delivery tests
insert into public.addresses(phone,label,address_text) values ('+201000000111','home','اختبار — ١٢ شارع النيل، القاهرة') on conflict do nothing;
-- reset risk profile counters:
-- For loyalty suite (immediate credit): use trusted profile (total_orders=5, verified=true) so NEW_CUSTOMER+NEW_DEVICE (30) is offset by FIVE_PLUS_SUCCESSFUL (-30) + VERIFIED (-15) => 0 approved.
-- For new-customer edge tests: manually set back to 0/false before that case.
update public.customer_risk_profiles set total_orders=5, successful_orders=5, cancelled_orders=0, failed_deliveries=0, rejected_orders=0, total_spent=0, risk_score=0, risk_level='low', phone_verified=true, updated_at=now() where phone='+201000000111';

-- verify
select phone, points, stamps, spinner_tokens from public.loyalty_state where phone='+201000000111';
select count(*) as orders from public.orders where phone='+201000000111';
