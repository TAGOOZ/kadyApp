-- 0028_risk_calculate_single_source.sql — Risk engine single source of truth
-- Deep Module: collapse 340+130 line duplication into one pure SQL mirror of Dart.
--
-- LANGUAGE.md vocabulary
--   Module:    Risk scoring — deep module behind a narrow interface.
--   Interface: public.risk_calculate(jsonb) -> jsonb {score, level, action, reasons}
--   Seam:      single seam replaces two duplicated seams (trigger + RPC each owned scoring).
--             Adapters sit above the seam; the pure engine sits below.
--   Adapter:   evaluate_order_risk_trigger (BEFORE INSERT) and evaluate_order_risk(uuid)
--             are thin Adapters — they collect DB context then delegate to the engine.
--   Depth:     deep: one call hides thresholds + catalog + exclusive 5+/3+ + extrinsic cap + clamp + level/action.
--   Leverage:  high leverage — changing a score/threshold/cap in risk_calculate fixes both
--             call sites; adding a rule is a row in risk_rules, not two file edits.
--   Locality:  all scoring Locality is inside risk_calculate; adapters contain only I/O
--             (profiles/devices/addresses/rapid window -> jsonb).
--
-- Mirrors lib/domain/risk_engine.dart calculateRisk — keep identical
-- Dart is master for threshold/rule constants; SQL is server-authoritative for writes.
-- Keep is_extrinsic data-driven via risk_rules.is_extrinsic (0027) plus legacy fallback
-- for catalogs without the column, identical to Dart's `isExtrinsic || _legacyExtrinsicCodes`.
-- Single transaction intent preserved: pricing->risk->rateLimit->events->device (ADR-0013).
--
-- Changes:
--   1) CREATE OR REPLACE public.risk_calculate(p_context jsonb) — the single pure function.
--      Owns: thresholds from app_config, catalog from risk_rules (score/enabled/is_extrinsic),
--      exclusive 5+/3+ logic, extrinsic cap via is_extrinsic, clamp 0..100, level/action.
--   2) Patch evaluate_order_risk_trigger() to 15-line Adapter: collect context, jsonb_build_object, call risk_calculate.
--   3) Patch evaluate_order_risk(uuid)   to same Adapter shape for re-evaluation.
--   4) Keep trigger ordering trg_a_validate -> trg_b_evaluate -> trg_c_rate_limit alphabetical.

begin;

-- ---------------------------------------------------------------------------
-- 1. Pure engine — SQL mirror of Dart calculateRisk (lib/domain/risk_engine.dart)
-- ---------------------------------------------------------------------------
create or replace function public.risk_calculate(p_context jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_low_max        int := 29;
  v_medium_max     int := 59;
  v_large_threshold int := 500;
  v_score_NEW_CUSTOMER      int := 20; v_en_NEW_CUSTOMER      bool := true;
  v_score_NEW_DEVICE        int := 10; v_en_NEW_DEVICE        bool := true;
  v_score_PREV_FAILED       int := 25; v_en_PREV_FAILED       bool := true;
  v_score_PREV_REJECTED     int := 30; v_en_PREV_REJECTED     bool := true;
  v_score_THREE_PLUS_CANCEL int := 25; v_en_THREE_PLUS_CANCEL bool := true;
  v_score_LARGE_ORDER       int := 15; v_en_LARGE_ORDER       bool := true;
  v_score_RAPID_ORDERS      int := 20; v_en_RAPID_ORDERS      bool := true;
  v_score_THREE_PLUS_SUCCESS int := -20; v_en_THREE_PLUS_SUCCESS bool := true;
  v_score_FIVE_PLUS_SUCCESS  int := -30; v_en_FIVE_PLUS_SUCCESS  bool := true;
  v_score_VERIFIED_PHONE    int := -15; v_en_VERIFIED_PHONE    bool := true;
  v_score_MULTI_DEVICE      int := 10;  v_en_MULTI_DEVICE      bool := true;
  v_score_MULTI_ADDRESS     int := 10;  v_en_MULTI_ADDRESS     bool := false;
  v_score_ADDR_HIGH_FAIL    int := 15;  v_en_ADDR_HIGH_FAIL    bool := false;
  v_total_orders         int  := 0;
  v_successful           int  := 0;
  v_cancelled            int  := 0;
  v_failed               int  := 0;
  v_rejected             int  := 0;
  v_verified             bool := false;
  v_is_new_device        bool := false;
  v_device_customer_count int := 0;
  v_address_customer_count int := 0;
  v_address_failed_count int  := 0;
  v_is_rapid             bool := false;
  v_subtotal             int  := 0;
  v_is_large             bool := false;
  v_has_is_large         bool := false;
  v_is_new_customer      bool := false;
  v_has_is_new_customer  bool := false;
  v_phone_present        bool := true;
  v_score          int := 0;
  v_reasons        text[] := '{}';
  v_extrinsic_only bool := false;
  v_level          text;
  v_action         text;
  r record;
begin
  begin select value::text::int into v_low_max       from public.app_config where key='risk.low_max_score';       exception when others then null; end; v_low_max       := coalesce(v_low_max, 29);
  begin select value::text::int into v_medium_max    from public.app_config where key='risk.medium_max_score';    exception when others then null; end; v_medium_max    := coalesce(v_medium_max, 59);
  begin select value::text::int into v_large_threshold from public.app_config where key='risk.large_order_threshold'; exception when others then null; end; v_large_threshold := coalesce(v_large_threshold, 500);
  if v_low_max >= v_medium_max then declare tmp int := v_low_max; begin v_low_max := v_medium_max; v_medium_max := tmp; end; end if;
  if v_low_max < 0 then v_low_max := 0; end if;
  if v_medium_max > 100 then v_medium_max := 100; end if;
  for r in select rule_code, score, enabled from public.risk_rules loop
    case r.rule_code
      when 'NEW_CUSTOMER'            then v_score_NEW_CUSTOMER      := r.score; v_en_NEW_CUSTOMER      := r.enabled;
      when 'NEW_DEVICE'              then v_score_NEW_DEVICE        := r.score; v_en_NEW_DEVICE        := r.enabled;
      when 'PREVIOUS_FAILED_DELIVERY' then v_score_PREV_FAILED       := r.score; v_en_PREV_FAILED       := r.enabled;
      when 'PREVIOUS_REJECTED_ORDER'  then v_score_PREV_REJECTED     := r.score; v_en_PREV_REJECTED     := r.enabled;
      when 'THREE_PLUS_CANCELLATIONS' then v_score_THREE_PLUS_CANCEL := r.score; v_en_THREE_PLUS_CANCEL := r.enabled;
      when 'LARGE_ORDER'             then v_score_LARGE_ORDER       := r.score; v_en_LARGE_ORDER       := r.enabled;
      when 'RAPID_ORDERS'            then v_score_RAPID_ORDERS      := r.score; v_en_RAPID_ORDERS      := r.enabled;
      when 'THREE_PLUS_SUCCESSFUL'   then v_score_THREE_PLUS_SUCCESS := r.score; v_en_THREE_PLUS_SUCCESS := r.enabled;
      when 'FIVE_PLUS_SUCCESSFUL'    then v_score_FIVE_PLUS_SUCCESS  := r.score; v_en_FIVE_PLUS_SUCCESS  := r.enabled;
      when 'VERIFIED_PHONE'          then v_score_VERIFIED_PHONE    := r.score; v_en_VERIFIED_PHONE    := r.enabled;
      when 'MULTIPLE_ACCOUNTS_DEVICE' then v_score_MULTI_DEVICE      := r.score; v_en_MULTI_DEVICE      := r.enabled;
      when 'MULTIPLE_ACCOUNTS_ADDRESS' then v_score_MULTI_ADDRESS     := r.score; v_en_MULTI_ADDRESS     := r.enabled;
      when 'ADDRESS_HIGH_FAILURE'    then v_score_ADDR_HIGH_FAIL    := r.score; v_en_ADDR_HIGH_FAIL    := r.enabled;
      else null;
    end case;
  end loop;
  v_total_orders  := coalesce((p_context->>'total_orders')::int, (p_context->>'totalOrders')::int, 0);
  v_successful    := coalesce((p_context->>'successful_orders')::int, (p_context->>'successfulOrders')::int, 0);
  v_cancelled     := coalesce((p_context->>'cancelled_orders')::int, (p_context->>'cancelledOrders')::int, (p_context->>'cancellations_count')::int, 0);
  v_failed        := coalesce((p_context->>'failed_deliveries')::int, (p_context->>'failedDeliveries')::int, 0);
  v_rejected      := coalesce((p_context->>'rejected_orders')::int, (p_context->>'rejectedOrders')::int, 0);
  v_device_customer_count  := coalesce((p_context->>'device_customer_count')::int, (p_context->>'deviceCustomerCount')::int, 0);
  v_address_customer_count := coalesce((p_context->>'address_customer_count')::int, (p_context->>'addressCustomerCount')::int, 0);
  v_address_failed_count   := coalesce((p_context->>'address_failed_count')::int, (p_context->>'addressFailedCount')::int, 0);
  v_subtotal := coalesce((p_context->>'subtotal')::int, (p_context->>'subtotal_egp')::int, 0);
  v_verified      := coalesce((p_context->>'phone_verified')::bool, (p_context->>'phoneVerified')::bool, false);
  v_is_new_device := coalesce((p_context->>'is_new_device')::bool, (p_context->>'isNewDevice')::bool, false);
  v_is_rapid      := coalesce((p_context->>'is_rapid')::bool, (p_context->>'isRapid')::bool, false);
  if p_context ? 'is_large' then v_has_is_large := true; v_is_large := coalesce((p_context->>'is_large')::bool, false); else v_is_large := v_subtotal >= v_large_threshold; end if;
  if p_context ? 'is_new_customer' or p_context ? 'isNewCustomer' then v_has_is_new_customer := true; v_is_new_customer := coalesce((p_context->>'is_new_customer')::bool, (p_context->>'isNewCustomer')::bool, false); end if;
  if p_context ? 'has_phone' or p_context ? 'phone_present' then v_phone_present := coalesce((p_context->>'has_phone')::bool, (p_context->>'phone_present')::bool, true);
  elsif p_context ? 'phone' then v_phone_present := (p_context->>'phone') is not null and (p_context->>'phone') <> '' and (p_context->>'phone') <> 'null';
  else v_phone_present := true; end if;
  v_score := 0; v_reasons := '{}';
  if v_has_is_new_customer then
    if v_is_new_customer and v_en_NEW_CUSTOMER then v_score := v_score + v_score_NEW_CUSTOMER; v_reasons := array_append(v_reasons, 'NEW_CUSTOMER'); end if;
  else
    if v_phone_present and v_total_orders = 0 and v_en_NEW_CUSTOMER then v_score := v_score + v_score_NEW_CUSTOMER; v_reasons := array_append(v_reasons, 'NEW_CUSTOMER'); end if;
  end if;
  if v_is_new_device and v_en_NEW_DEVICE then v_score := v_score + v_score_NEW_DEVICE; v_reasons := array_append(v_reasons, 'NEW_DEVICE'); end if;
  if v_failed > 0 and v_en_PREV_FAILED then v_score := v_score + v_score_PREV_FAILED; v_reasons := array_append(v_reasons, 'PREVIOUS_FAILED_DELIVERY'); end if;
  if v_rejected > 0 and v_en_PREV_REJECTED then v_score := v_score + v_score_PREV_REJECTED; v_reasons := array_append(v_reasons, 'PREVIOUS_REJECTED_ORDER'); end if;
  if v_cancelled >= 3 and v_en_THREE_PLUS_CANCEL then v_score := v_score + v_score_THREE_PLUS_CANCEL; v_reasons := array_append(v_reasons, 'THREE_PLUS_CANCELLATIONS'); end if;
  if v_is_large and v_en_LARGE_ORDER then v_score := v_score + v_score_LARGE_ORDER; v_reasons := array_append(v_reasons, 'LARGE_ORDER'); end if;
  if v_is_rapid and v_en_RAPID_ORDERS then v_score := v_score + v_score_RAPID_ORDERS; v_reasons := array_append(v_reasons, 'RAPID_ORDERS'); end if;
  if v_successful >= 5 and v_en_FIVE_PLUS_SUCCESS then v_score := v_score + v_score_FIVE_PLUS_SUCCESS; v_reasons := array_append(v_reasons, 'FIVE_PLUS_SUCCESSFUL');
  elsif v_successful >= 3 and v_en_THREE_PLUS_SUCCESS then v_score := v_score + v_score_THREE_PLUS_SUCCESS; v_reasons := array_append(v_reasons, 'THREE_PLUS_SUCCESSFUL'); end if;
  if v_verified and v_en_VERIFIED_PHONE then v_score := v_score + v_score_VERIFIED_PHONE; v_reasons := array_append(v_reasons, 'VERIFIED_PHONE'); end if;
  if v_device_customer_count >= 2 and v_en_MULTI_DEVICE then v_score := v_score + v_score_MULTI_DEVICE; v_reasons := array_append(v_reasons, 'MULTIPLE_ACCOUNTS_DEVICE'); end if;
  if v_address_customer_count >= 2 and v_en_MULTI_ADDRESS then v_score := v_score + v_score_MULTI_ADDRESS; v_reasons := array_append(v_reasons, 'MULTIPLE_ACCOUNTS_ADDRESS'); end if;
  if v_address_failed_count >= 3 and v_en_ADDR_HIGH_FAIL then v_score := v_score + v_score_ADDR_HIGH_FAIL; v_reasons := array_append(v_reasons, 'ADDRESS_HIGH_FAILURE'); end if;
  if array_length(v_reasons, 1) is not null then
    select bool_and(coalesce(rr.is_extrinsic, false) or elem = any(array['NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE']))
      into v_extrinsic_only from unnest(v_reasons) as elem left join public.risk_rules rr on rr.rule_code = elem;
    if coalesce(v_extrinsic_only, false) and v_score > v_medium_max then v_score := v_medium_max; end if;
  end if;
  if v_score < 0 then v_score := 0; end if;
  if v_score > 100 then v_score := 100; end if;
  if v_score <= v_low_max then v_level := 'low'; v_action := 'approved';
  elsif v_score <= v_medium_max then v_level := 'medium'; v_action := 'needs_verification';
  else v_level := 'high'; v_action := 'rejected'; end if;
  return jsonb_build_object('score', v_score, 'level', v_level, 'action', v_action, 'reasons', to_jsonb(v_reasons));
end;
$$;
comment on function public.risk_calculate(jsonb) is 'Pure risk engine — Mirrors lib/domain/risk_engine.dart calculateRisk — keep identical. Takes JSONB context and returns {score,level,action,reasons}. Owns scoring, thresholds, extrinsic cap data-driven via is_extrinsic.';
revoke all on function public.risk_calculate(jsonb) from public; grant execute on function public.risk_calculate(jsonb) to authenticated; grant execute on function public.risk_calculate(jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Thin Adapter — BEFORE INSERT
-- ---------------------------------------------------------------------------
create or replace function public.evaluate_order_risk_trigger() returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_total_orders int:=0; v_successful int:=0; v_cancelled int:=0; v_failed int:=0; v_rejected int:=0; v_verified bool:=false;
  v_is_new_device bool:=false; v_device_distinct_before int:=0; v_device_customer_count int:=0;
  v_addr_distinct_before int:=0; v_addr_has_phone bool:=false; v_address_customer_count int:=0; v_address_failed_count int:=0;
  v_recent_orders int:=0; v_is_rapid bool:=false; v_rapid_count int:=3; v_rapid_window int:=30;
  v_ctx jsonb; v_res jsonb;
begin
  begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count:=coalesce(v_rapid_count,3);
  begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window:=coalesce(v_rapid_window,30);
  if new.phone is not null then select total_orders,successful_orders,cancelled_orders,failed_deliveries,rejected_orders,phone_verified into v_total_orders,v_successful,v_cancelled,v_failed,v_rejected,v_verified from public.customer_risk_profiles where phone=new.phone; if not found then v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if; else v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if;
  if new.device_id is not null and new.device_id<>'' then select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id=new.device_id; if new.phone is not null then select not exists(select 1 from public.customer_devices where phone=new.phone and device_id=new.device_id) into v_is_new_device; else v_is_new_device:=true; end if; if v_is_new_device then v_device_customer_count:=v_device_distinct_before+1; else v_device_customer_count:=v_device_distinct_before; end if; else v_is_new_device:=false; v_device_customer_count:=0; end if;
  if new.address_id is not null then select count(distinct phone) into v_addr_distinct_before from public.orders where address_id=new.address_id; if new.phone is not null then select exists(select 1 from public.orders where address_id=new.address_id and phone=new.phone) into v_addr_has_phone; if v_addr_has_phone then v_address_customer_count:=v_addr_distinct_before; else v_address_customer_count:=v_addr_distinct_before+1; end if; else v_address_customer_count:=v_addr_distinct_before; end if; select count(*) into v_address_failed_count from public.orders where address_id=new.address_id and status='cancelled'; else v_address_customer_count:=0; v_address_failed_count:=0; end if;
  if new.phone is not null and v_rapid_window>0 and v_rapid_count>0 then select count(*) into v_recent_orders from public.orders where phone=new.phone and created_at>now()-(v_rapid_window||' minutes')::interval; v_is_rapid:=(v_recent_orders+1)>=v_rapid_count; else v_is_rapid:=false; end if;
  v_ctx:=jsonb_build_object('total_orders',v_total_orders,'successful_orders',v_successful,'cancelled_orders',v_cancelled,'failed_deliveries',v_failed,'rejected_orders',v_rejected,'phone_verified',v_verified,'is_new_device',v_is_new_device,'device_customer_count',v_device_customer_count,'address_customer_count',v_address_customer_count,'address_failed_count',v_address_failed_count,'is_rapid',v_is_rapid,'subtotal',coalesce(new.subtotal,0),'has_phone',new.phone is not null);
  v_res:=public.risk_calculate(v_ctx);
  new.risk_score:=(v_res->>'score')::int; new.risk_level:=v_res->>'level'; new.risk_action:=v_res->>'action'; new.risk_reasons:=v_res->'reasons'; new.risk_evaluated_at:=now(); return new;
end; $$;
comment on function public.evaluate_order_risk_trigger() is 'RISK-04/09/10 Adapter (BEFORE INSERT, trg_b): thin adapter — collects context, calls public.risk_calculate (pure). Mirrors lib/domain/risk_engine.dart calculateRisk — keep identical. Ordering trg_a->trg_b->trg_c alphabetical. SECURITY DEFINER.';

-- ---------------------------------------------------------------------------
-- 3. Thin Adapter — RPC
-- ---------------------------------------------------------------------------
create or replace function public.evaluate_order_risk(p_order_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare r public.orders%rowtype; v_total_orders int:=0;v_successful int:=0;v_cancelled int:=0;v_failed int:=0;v_rejected int:=0;v_verified bool:=false; v_is_new_device bool:=false;v_device_distinct_before int:=0;v_device_customer_count int:=0; v_addr_distinct_before int:=0;v_addr_has_phone bool:=false;v_address_customer_count int:=0;v_address_failed_count int:=0; v_recent_orders int:=0;v_is_rapid bool:=false;v_rapid_count int:=3;v_rapid_window int:=30; v_ctx jsonb;v_res jsonb; begin select * into r from public.orders where id=p_order_id; if not found then raise exception 'evaluate_order_risk: order % not found',p_order_id using errcode='P0002'; end if;
  begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count:=coalesce(v_rapid_count,3);
  begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window:=coalesce(v_rapid_window,30);
  if r.phone is not null then select total_orders,successful_orders,cancelled_orders,failed_deliveries,rejected_orders,phone_verified into v_total_orders,v_successful,v_cancelled,v_failed,v_rejected,v_verified from public.customer_risk_profiles where phone=r.phone; if not found then v_total_orders:=0;v_successful:=0;v_cancelled:=0;v_failed:=0;v_rejected:=0;v_verified:=false; end if; end if;
  if r.device_id is not null and r.device_id<>'' then select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id=r.device_id; if r.phone is not null then select not exists(select 1 from public.customer_devices where phone=r.phone and device_id=r.device_id) into v_is_new_device; else v_is_new_device:=true; end if; if v_is_new_device then v_device_customer_count:=v_device_distinct_before+1; else v_device_customer_count:=v_device_distinct_before; end if; else v_is_new_device:=false;v_device_customer_count:=0; end if;
  if r.address_id is not null then select count(distinct phone) into v_addr_distinct_before from public.orders where address_id=r.address_id; if r.phone is not null then select exists(select 1 from public.orders where address_id=r.address_id and phone=r.phone) into v_addr_has_phone; if v_addr_has_phone then v_address_customer_count:=v_addr_distinct_before; else v_address_customer_count:=v_addr_distinct_before+1; end if; else v_address_customer_count:=v_addr_distinct_before; end if; select count(*) into v_address_failed_count from public.orders where address_id=r.address_id and status='cancelled'; else v_address_customer_count:=0;v_address_failed_count:=0; end if;
  if r.phone is not null and v_rapid_window>0 and v_rapid_count>0 then select count(*) into v_recent_orders from public.orders where phone=r.phone and created_at>now()-(v_rapid_window||' minutes')::interval and id<>r.id; v_is_rapid:=(v_recent_orders+1)>=v_rapid_count; end if;
  v_ctx:=jsonb_build_object('total_orders',v_total_orders,'successful_orders',v_successful,'cancelled_orders',v_cancelled,'failed_deliveries',v_failed,'rejected_orders',v_rejected,'phone_verified',v_verified,'is_new_device',v_is_new_device,'device_customer_count',v_device_customer_count,'address_customer_count',v_address_customer_count,'address_failed_count',v_address_failed_count,'is_rapid',v_is_rapid,'subtotal',coalesce(r.subtotal,0),'has_phone',r.phone is not null);
  v_res:=public.risk_calculate(v_ctx);
  update public.orders set risk_score=(v_res->>'score')::int,risk_level=v_res->>'level',risk_action=v_res->>'action',risk_reasons=v_res->'reasons',risk_evaluated_at=now() where id=p_order_id; end; $$;
comment on function public.evaluate_order_risk(uuid) is 'RISK-04/09/10 Adapter (callable, SECURITY DEFINER): collects same context as trigger, calls public.risk_calculate. Mirrors lib/domain/risk_engine.dart calculateRisk — keep identical. Data-driven extrinsic via is_extrinsic lives in risk_calculate.';
revoke all on function public.evaluate_order_risk(uuid) from public; grant execute on function public.evaluate_order_risk(uuid) to authenticated; grant execute on function public.evaluate_order_risk(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Preserve alphabetical BEFORE INSERT ordering + verify
-- ---------------------------------------------------------------------------
drop trigger if exists trg_00_assign_display_number on public.orders; drop trigger if exists trg_a_validate_order_pricing on public.orders; drop trigger if exists trg_b_evaluate_order_risk on public.orders; drop trigger if exists trg_c_enforce_order_rate_limit on public.orders; drop trigger if exists trg_d_enforce_order_dedup on public.orders;
create trigger trg_00_assign_display_number before insert on public.orders for each row execute function public.assign_order_display_number();
create trigger trg_a_validate_order_pricing before insert on public.orders for each row execute function public.validate_order_pricing();
create trigger trg_b_evaluate_order_risk before insert on public.orders for each row execute function public.evaluate_order_risk_trigger();
create trigger trg_c_enforce_order_rate_limit before insert on public.orders for each row execute function public.enforce_order_rate_limit();
create trigger trg_d_enforce_order_dedup before insert on public.orders for each row execute function public.enforce_order_dedup();
do $$ begin if not exists(select 1 from pg_proc where proname='risk_calculate') then raise exception '0028: risk_calculate missing'; end if; if not exists(select 1 from pg_trigger where tgname='trg_b_evaluate_order_risk') then raise exception '0028: trg_b missing'; end if; if not exists(select 1 from pg_trigger where tgname='trg_a_validate_order_pricing') then raise exception '0028: trg_a invariant violated'; end if; if not exists(select 1 from pg_trigger where tgname='trg_c_enforce_order_rate_limit') then raise exception '0028: trg_c invariant violated'; end if; end $$;
commit;
