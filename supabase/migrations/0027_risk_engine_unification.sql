-- 0027_risk_engine_unification.sql — Risk engine unification (RISK-09)
-- Deepen Risk scoring module: make extrinsic cap data-driven, collapse SQL duplication
-- via is_extrinsic catalog flag. Mirrors Dart lib/domain/risk_engine.dart: isExtrinsic.
--
-- Dart is master for threshold/constants, but SQL is server-authoritative for writes.
-- This migration makes SQL extrinsic logic data-driven so adding a signal is a row,
-- not two files. Full codegen (Dart → SQL function) deferred to 0028; this step
-- removes the hard-coded extrinsic set and introduces the seam.
--
-- Changes:
--   1. risk_rules.is_extrinsic boolean (signal-not-proof, Mahmoudia families share devices)
--   2. Backfill: NEW_DEVICE, MULTIPLE_ACCOUNTS_DEVICE/ADDRESS, ADDRESS_HIGH_FAILURE = true
--   3. Patch evaluate_order_risk_trigger and evaluate_order_risk RPC to use
--      `risk_rules.is_extrinsic` via join instead of hard-coded array['NEW_DEVICE',...]
--   4. Keep Dart/SQL identical invariant: Dart RiskRule.isExtrinsic ↔ SQL is_extrinsic
--   5. No trigger ordering change — keeps trg_a/b/c alphabetical (ADR-0013).

begin;

-- ---------------------------------------------------------------------------
-- 1. Catalog flag — data-driven extrinsic set
-- ---------------------------------------------------------------------------
alter table public.risk_rules
  add column if not exists is_extrinsic boolean not null default false;

comment on column public.risk_rules.is_extrinsic is
  'Signal-not-proof extrinsic signal (Mahmoudia: families share devices/addresses). '
  'When every contributing reason has is_extrinsic=true, score is clamped to mediumMax (59) — never high/rejected alone. '
  'Mirrors Dart RiskRule.isExtrinsic (lib/domain/risk_engine.dart) and kDefaultRiskRules; keep SQL/Dart identical.';

-- Backfill — idempotent (matches kDefaultRiskRules isExtrinsic: true for 4 codes)
update public.risk_rules
   set is_extrinsic = true
 where rule_code in ('NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE')
   and is_extrinsic = false;

-- Ensure others are false (in case manual edits flipped them)
update public.risk_rules
   set is_extrinsic = false
 where rule_code not in ('NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE')
   and is_extrinsic = true;

-- ---------------------------------------------------------------------------
-- 2. Patch BEFORE INSERT trigger — use catalog is_extrinsic instead of hard-coded set
-- ---------------------------------------------------------------------------
create or replace function public.evaluate_order_risk_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_low_max      int := 29;
  v_medium_max   int := 59;
  v_large_threshold int := 500;
  v_rapid_count  int := 3;
  v_rapid_window int := 30;
  v_val text;

  v_total_orders int := 0;
  v_successful   int := 0;
  v_cancelled    int := 0;
  v_failed       int := 0;
  v_rejected     int := 0;
  v_verified     bool := false;
  v_profile_found bool := false;

  v_is_new_device bool := false;
  v_device_distinct_before int := 0;
  v_device_customer_count int := 0;
  v_addr_distinct_before int := 0;
  v_addr_has_phone bool := false;
  v_address_customer_count int := 0;
  v_address_failed_count int := 0;

  v_recent_orders int := 0;
  v_is_rapid bool := false;

  v_score_NEW_CUSTOMER int := 20; v_en_NEW_CUSTOMER bool := true;
  v_score_NEW_DEVICE int := 10; v_en_NEW_DEVICE bool := true;
  v_score_PREV_FAILED int := 25; v_en_PREV_FAILED bool := true;
  v_score_PREV_REJECTED int := 30; v_en_PREV_REJECTED bool := true;
  v_score_THREE_PLUS_CANCEL int := 25; v_en_THREE_PLUS_CANCEL bool := true;
  v_score_LARGE_ORDER int := 15; v_en_LARGE_ORDER bool := true;
  v_score_RAPID_ORDERS int := 20; v_en_RAPID_ORDERS bool := true;
  v_score_THREE_PLUS_SUCCESS int := -20; v_en_THREE_PLUS_SUCCESS bool := true;
  v_score_FIVE_PLUS_SUCCESS int := -30; v_en_FIVE_PLUS_SUCCESS bool := true;
  v_score_VERIFIED_PHONE int := -15; v_en_VERIFIED_PHONE bool := true;
  v_score_MULTI_DEVICE int := 10; v_en_MULTI_DEVICE bool := true;
  v_score_MULTI_ADDRESS int := 10; v_en_MULTI_ADDRESS bool := false;
  v_score_ADDR_HIGH_FAIL int := 15; v_en_ADDR_HIGH_FAIL bool := false;

  v_score int := 0;
  v_reasons text[] := '{}';
  v_is_large bool := false;
  v_extrinsic_only bool := false;
  v_level text;
  v_action text;

  r record;
begin
  begin select value::text::int into v_low_max from public.app_config where key='risk.low_max_score'; exception when others then null; end; v_low_max := coalesce(v_low_max, 29);
  begin select value::text::int into v_medium_max from public.app_config where key='risk.medium_max_score'; exception when others then null; end; v_medium_max := coalesce(v_medium_max, 59);
  begin select value::text::int into v_large_threshold from public.app_config where key='risk.large_order_threshold'; exception when others then null; end; v_large_threshold := coalesce(v_large_threshold, 500);
  begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count := coalesce(v_rapid_count, 3);
  begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window := coalesce(v_rapid_window, 30);

  if v_low_max >= v_medium_max then declare tmp int := v_low_max; begin v_low_max := v_medium_max; v_medium_max := tmp; end; end if;
  if v_low_max < 0 then v_low_max := 0; end if;
  if v_medium_max > 100 then v_medium_max := 100; end if;

  for r in select rule_code, score, enabled from public.risk_rules loop
    case r.rule_code
      when 'NEW_CUSTOMER' then v_score_NEW_CUSTOMER := r.score; v_en_NEW_CUSTOMER := r.enabled;
      when 'NEW_DEVICE' then v_score_NEW_DEVICE := r.score; v_en_NEW_DEVICE := r.enabled;
      when 'PREVIOUS_FAILED_DELIVERY' then v_score_PREV_FAILED := r.score; v_en_PREV_FAILED := r.enabled;
      when 'PREVIOUS_REJECTED_ORDER' then v_score_PREV_REJECTED := r.score; v_en_PREV_REJECTED := r.enabled;
      when 'THREE_PLUS_CANCELLATIONS' then v_score_THREE_PLUS_CANCEL := r.score; v_en_THREE_PLUS_CANCEL := r.enabled;
      when 'LARGE_ORDER' then v_score_LARGE_ORDER := r.score; v_en_LARGE_ORDER := r.enabled;
      when 'RAPID_ORDERS' then v_score_RAPID_ORDERS := r.score; v_en_RAPID_ORDERS := r.enabled;
      when 'THREE_PLUS_SUCCESSFUL' then v_score_THREE_PLUS_SUCCESS := r.score; v_en_THREE_PLUS_SUCCESS := r.enabled;
      when 'FIVE_PLUS_SUCCESSFUL' then v_score_FIVE_PLUS_SUCCESS := r.score; v_en_FIVE_PLUS_SUCCESS := r.enabled;
      when 'VERIFIED_PHONE' then v_score_VERIFIED_PHONE := r.score; v_en_VERIFIED_PHONE := r.enabled;
      when 'MULTIPLE_ACCOUNTS_DEVICE' then v_score_MULTI_DEVICE := r.score; v_en_MULTI_DEVICE := r.enabled;
      when 'MULTIPLE_ACCOUNTS_ADDRESS' then v_score_MULTI_ADDRESS := r.score; v_en_MULTI_ADDRESS := r.enabled;
      when 'ADDRESS_HIGH_FAILURE' then v_score_ADDR_HIGH_FAIL := r.score; v_en_ADDR_HIGH_FAIL := r.enabled;
      else null;
    end case;
  end loop;

  if new.phone is not null then
    select total_orders, successful_orders, cancelled_orders, failed_deliveries, rejected_orders, phone_verified
      into v_total_orders, v_successful, v_cancelled, v_failed, v_rejected, v_verified
      from public.customer_risk_profiles where phone = new.phone;
    if not found then v_total_orders := 0; v_successful := 0; v_cancelled := 0; v_failed := 0; v_rejected := 0; v_verified := false; v_profile_found := false;
    else v_profile_found := true; end if;
  else v_total_orders := 0; v_successful := 0; v_cancelled := 0; v_failed := 0; v_rejected := 0; v_verified := false; end if;

  if new.device_id is not null and new.device_id <> '' then
    select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id = new.device_id;
    if new.phone is not null then
      select not exists (select 1 from public.customer_devices where phone = new.phone and device_id = new.device_id) into v_is_new_device;
    else v_is_new_device := true; end if;
    if v_is_new_device then v_device_customer_count := v_device_distinct_before + 1; else v_device_customer_count := v_device_distinct_before; end if;
  else v_is_new_device := false; v_device_customer_count := 0; v_device_distinct_before := 0; end if;

  if new.address_id is not null then
    select count(distinct phone) into v_addr_distinct_before from public.orders where address_id = new.address_id;
    if new.phone is not null then
      select exists (select 1 from public.orders where address_id = new.address_id and phone = new.phone) into v_addr_has_phone;
      if v_addr_has_phone then v_address_customer_count := v_addr_distinct_before; else v_address_customer_count := v_addr_distinct_before + 1; end if;
    else v_address_customer_count := v_addr_distinct_before; end if;
    select count(*) into v_address_failed_count from public.orders where address_id = new.address_id and status = 'cancelled';
  else v_address_customer_count := 0; v_address_failed_count := 0; end if;

  if new.phone is not null and v_rapid_window > 0 and v_rapid_count > 0 then
    select count(*) into v_recent_orders from public.orders where phone = new.phone and created_at > now() - (v_rapid_window || ' minutes')::interval;
    if (v_recent_orders + 1) >= v_rapid_count then v_is_rapid := true; else v_is_rapid := false; end if;
  else v_is_rapid := false; end if;

  v_score := 0; v_reasons := '{}';

  if new.phone is not null and v_total_orders = 0 and v_en_NEW_CUSTOMER then v_score := v_score + v_score_NEW_CUSTOMER; v_reasons := array_append(v_reasons, 'NEW_CUSTOMER'); end if;
  if v_is_new_device and v_en_NEW_DEVICE then v_score := v_score + v_score_NEW_DEVICE; v_reasons := array_append(v_reasons, 'NEW_DEVICE'); end if;
  if v_failed > 0 and v_en_PREV_FAILED then v_score := v_score + v_score_PREV_FAILED; v_reasons := array_append(v_reasons, 'PREVIOUS_FAILED_DELIVERY'); end if;
  if v_rejected > 0 and v_en_PREV_REJECTED then v_score := v_score + v_score_PREV_REJECTED; v_reasons := array_append(v_reasons, 'PREVIOUS_REJECTED_ORDER'); end if;
  if v_cancelled >= 3 and v_en_THREE_PLUS_CANCEL then v_score := v_score + v_score_THREE_PLUS_CANCEL; v_reasons := array_append(v_reasons, 'THREE_PLUS_CANCELLATIONS'); end if;
  v_is_large := coalesce(new.subtotal, 0) >= v_large_threshold;
  if v_is_large and v_en_LARGE_ORDER then v_score := v_score + v_score_LARGE_ORDER; v_reasons := array_append(v_reasons, 'LARGE_ORDER'); end if;
  if v_is_rapid and v_en_RAPID_ORDERS then v_score := v_score + v_score_RAPID_ORDERS; v_reasons := array_append(v_reasons, 'RAPID_ORDERS'); end if;
  if v_successful >= 5 and v_en_FIVE_PLUS_SUCCESS then v_score := v_score + v_score_FIVE_PLUS_SUCCESS; v_reasons := array_append(v_reasons, 'FIVE_PLUS_SUCCESSFUL');
  elsif v_successful >= 3 and v_en_THREE_PLUS_SUCCESS then v_score := v_score + v_score_THREE_PLUS_SUCCESS; v_reasons := array_append(v_reasons, 'THREE_PLUS_SUCCESSFUL'); end if;
  if v_verified and v_en_VERIFIED_PHONE then v_score := v_score + v_score_VERIFIED_PHONE; v_reasons := array_append(v_reasons, 'VERIFIED_PHONE'); end if;
  if v_device_customer_count >= 2 and v_en_MULTI_DEVICE then v_score := v_score + v_score_MULTI_DEVICE; v_reasons := array_append(v_reasons, 'MULTIPLE_ACCOUNTS_DEVICE'); end if;
  if v_address_customer_count >= 2 and v_en_MULTI_ADDRESS then v_score := v_score + v_score_MULTI_ADDRESS; v_reasons := array_append(v_reasons, 'MULTIPLE_ACCOUNTS_ADDRESS'); end if;
  if v_address_failed_count >= 3 and v_en_ADDR_HIGH_FAIL then v_score := v_score + v_score_ADDR_HIGH_FAIL; v_reasons := array_append(v_reasons, 'ADDRESS_HIGH_FAILURE'); end if;

  -- Extrinsic-only cap — data-driven via risk_rules.is_extrinsic (Mahmoudia: never high on extrinsic alone)
  -- Mirrors Dart: reasons.every((c) => byCode[c]?.isExtrinsic ?? _legacyExtrinsicCodes.contains(c))
  if array_length(v_reasons, 1) is not null then
    select bool_and(coalesce(rr.is_extrinsic, false)) into v_extrinsic_only
      from unnest(v_reasons) as elem
      left join public.risk_rules rr on rr.rule_code = elem;
    -- Fallback for rows missing is_extrinsic (old DB without column): use hard-coded legacy set
    if v_extrinsic_only is null then
      select bool_and(elem = any(array['NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE']))
        into v_extrinsic_only from unnest(v_reasons) as elem;
    end if;
    if coalesce(v_extrinsic_only, false) and v_score > v_medium_max then v_score := v_medium_max; end if;
  end if;

  if v_score < 0 then v_score := 0; end if;
  if v_score > 100 then v_score := 100; end if;

  if v_score <= v_low_max then v_level := 'low'; v_action := 'approved';
  elsif v_score <= v_medium_max then v_level := 'medium'; v_action := 'needs_verification';
  else v_level := 'high'; v_action := 'rejected'; end if;

  new.risk_score := v_score;
  new.risk_level := v_level;
  new.risk_action := v_action;
  new.risk_reasons := to_jsonb(v_reasons);
  new.risk_evaluated_at := now();

  return new;
end;
$$;

comment on function public.evaluate_order_risk_trigger() is
  'RISK-04/09 BEFORE INSERT gate: mirrors Dart calculateRisk (lib/domain/risk_engine.dart). '
  'Extrinsic cap is data-driven via risk_rules.is_extrinsic (true for NEW_DEVICE/MULTIPLE_* /ADDRESS_HIGH). '
  'Reads corrected subtotal after trg_a_validate_order_pricing, collects profiles/device/address/rapid window, writes orders.risk_* server-authoritatively. '
  'SECURITY DEFINER.';

-- ---------------------------------------------------------------------------
-- 3. Patch callable re-evaluation RPC — same data-driven extrinsic logic
-- ---------------------------------------------------------------------------
create or replace function public.evaluate_order_risk(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.orders%rowtype;
begin
  select * into r from public.orders where id = p_order_id;
  if not found then raise exception 'evaluate_order_risk: order % not found', p_order_id using errcode='P0002'; end if;
  declare
    v_low_max int := 29; v_medium_max int := 59; v_large_threshold int := 500; v_rapid_count int := 3; v_rapid_window int := 30;
    v_total_orders int :=0; v_successful int:=0; v_cancelled int:=0; v_failed int:=0; v_rejected int:=0; v_verified bool:=false;
    v_is_new_device bool:=false; v_device_distinct_before int:=0; v_device_customer_count int:=0;
    v_addr_distinct_before int:=0; v_addr_has_phone bool:=false; v_address_customer_count int:=0; v_address_failed_count int:=0;
    v_recent_orders int:=0; v_is_rapid bool:=false;
    v_score_NEW_CUSTOMER int:=20; v_en_NEW_CUSTOMER bool:=true;
    v_score_NEW_DEVICE int:=10; v_en_NEW_DEVICE bool:=true;
    v_score_PREV_FAILED int:=25; v_en_PREV_FAILED bool:=true;
    v_score_PREV_REJECTED int:=30; v_en_PREV_REJECTED bool:=true;
    v_score_THREE_PLUS_CANCEL int:=25; v_en_THREE_PLUS_CANCEL bool:=true;
    v_score_LARGE_ORDER int:=15; v_en_LARGE_ORDER bool:=true;
    v_score_RAPID_ORDERS int:=20; v_en_RAPID_ORDERS bool:=true;
    v_score_THREE_PLUS_SUCCESS int:=-20; v_en_THREE_PLUS_SUCCESS bool:=true;
    v_score_FIVE_PLUS_SUCCESS int:=-30; v_en_FIVE_PLUS_SUCCESS bool:=true;
    v_score_VERIFIED_PHONE int:=-15; v_en_VERIFIED_PHONE bool:=true;
    v_score_MULTI_DEVICE int:=10; v_en_MULTI_DEVICE bool:=true;
    v_score_MULTI_ADDRESS int:=10; v_en_MULTI_ADDRESS bool:=false;
    v_score_ADDR_HIGH_FAIL int:=15; v_en_ADDR_HIGH_FAIL bool:=false;
    v_score int:=0; v_reasons text[]:='{}'; v_is_large bool:=false; v_extrinsic_only bool:=false; v_level text; v_action text;
    rr record; new_row public.orders%rowtype;
  begin
    new_row := r;
    begin select value::text::int into v_low_max from public.app_config where key='risk.low_max_score'; exception when others then null; end; v_low_max:=coalesce(v_low_max,29);
    begin select value::text::int into v_medium_max from public.app_config where key='risk.medium_max_score'; exception when others then null; end; v_medium_max:=coalesce(v_medium_max,59);
    begin select value::text::int into v_large_threshold from public.app_config where key='risk.large_order_threshold'; exception when others then null; end; v_large_threshold:=coalesce(v_large_threshold,500);
    begin select value::text::int into v_rapid_count from public.app_config where key='risk.rapid_orders_count'; exception when others then null; end; v_rapid_count:=coalesce(v_rapid_count,3);
    begin select value::text::int into v_rapid_window from public.app_config where key='risk.rapid_orders_window_minutes'; exception when others then null; end; v_rapid_window:=coalesce(v_rapid_window,30);
    if v_low_max >= v_medium_max then declare tmp int:=v_low_max; begin v_low_max:=v_medium_max; v_medium_max:=tmp; end; end if;
    if v_low_max<0 then v_low_max:=0; end if;
    if v_medium_max>100 then v_medium_max:=100; end if;
    for rr in select rule_code, score, enabled from public.risk_rules loop
      case rr.rule_code
        when 'NEW_CUSTOMER' then v_score_NEW_CUSTOMER:=rr.score; v_en_NEW_CUSTOMER:=rr.enabled;
        when 'NEW_DEVICE' then v_score_NEW_DEVICE:=rr.score; v_en_NEW_DEVICE:=rr.enabled;
        when 'PREVIOUS_FAILED_DELIVERY' then v_score_PREV_FAILED:=rr.score; v_en_PREV_FAILED:=rr.enabled;
        when 'PREVIOUS_REJECTED_ORDER' then v_score_PREV_REJECTED:=rr.score; v_en_PREV_REJECTED:=rr.enabled;
        when 'THREE_PLUS_CANCELLATIONS' then v_score_THREE_PLUS_CANCEL:=rr.score; v_en_THREE_PLUS_CANCEL:=rr.enabled;
        when 'LARGE_ORDER' then v_score_LARGE_ORDER:=rr.score; v_en_LARGE_ORDER:=rr.enabled;
        when 'RAPID_ORDERS' then v_score_RAPID_ORDERS:=rr.score; v_en_RAPID_ORDERS:=rr.enabled;
        when 'THREE_PLUS_SUCCESSFUL' then v_score_THREE_PLUS_SUCCESS:=rr.score; v_en_THREE_PLUS_SUCCESS:=rr.enabled;
        when 'FIVE_PLUS_SUCCESSFUL' then v_score_FIVE_PLUS_SUCCESS:=rr.score; v_en_FIVE_PLUS_SUCCESS:=rr.enabled;
        when 'VERIFIED_PHONE' then v_score_VERIFIED_PHONE:=rr.score; v_en_VERIFIED_PHONE:=rr.enabled;
        when 'MULTIPLE_ACCOUNTS_DEVICE' then v_score_MULTI_DEVICE:=rr.score; v_en_MULTI_DEVICE:=rr.enabled;
        when 'MULTIPLE_ACCOUNTS_ADDRESS' then v_score_MULTI_ADDRESS:=rr.score; v_en_MULTI_ADDRESS:=rr.enabled;
        when 'ADDRESS_HIGH_FAILURE' then v_score_ADDR_HIGH_FAIL:=rr.score; v_en_ADDR_HIGH_FAIL:=rr.enabled;
        else null;
      end case;
    end loop;
    if new_row.phone is not null then
      select total_orders, successful_orders, cancelled_orders, failed_deliveries, rejected_orders, phone_verified
        into v_total_orders, v_successful, v_cancelled, v_failed, v_rejected, v_verified
        from public.customer_risk_profiles where phone=new_row.phone;
      if not found then v_total_orders:=0; v_successful:=0; v_cancelled:=0; v_failed:=0; v_rejected:=0; v_verified:=false; end if;
    end if;
    if new_row.device_id is not null and new_row.device_id<>'' then
      select count(distinct phone) into v_device_distinct_before from public.customer_devices where device_id=new_row.device_id;
      if new_row.phone is not null then
        select not exists (select 1 from public.customer_devices where phone=new_row.phone and device_id=new_row.device_id) into v_is_new_device;
      else v_is_new_device:=true; end if;
      if v_is_new_device then v_device_customer_count:=v_device_distinct_before+1; else v_device_customer_count:=v_device_distinct_before; end if;
    else v_is_new_device:=false; v_device_customer_count:=0; end if;
    if new_row.address_id is not null then
      select count(distinct phone) into v_addr_distinct_before from public.orders where address_id=new_row.address_id;
      if new_row.phone is not null then
        select exists (select 1 from public.orders where address_id=new_row.address_id and phone=new_row.phone) into v_addr_has_phone;
        if v_addr_has_phone then v_address_customer_count:=v_addr_distinct_before; else v_address_customer_count:=v_addr_distinct_before+1; end if;
      else v_address_customer_count:=v_addr_distinct_before; end if;
      select count(*) into v_address_failed_count from public.orders where address_id=new_row.address_id and status='cancelled';
    else v_address_customer_count:=0; v_address_failed_count:=0; end if;
    if new_row.phone is not null and v_rapid_window>0 and v_rapid_count>0 then
      select count(*) into v_recent_orders from public.orders where phone=new_row.phone and created_at > now() - (v_rapid_window || ' minutes')::interval and id <> new_row.id;
      if (v_recent_orders+1) >= v_rapid_count then v_is_rapid:=true; else v_is_rapid:=false; end if;
    end if;
    v_score:=0; v_reasons:='{}';
    if new_row.phone is not null and v_total_orders=0 and v_en_NEW_CUSTOMER then v_score:=v_score+v_score_NEW_CUSTOMER; v_reasons:=array_append(v_reasons,'NEW_CUSTOMER'); end if;
    if v_is_new_device and v_en_NEW_DEVICE then v_score:=v_score+v_score_NEW_DEVICE; v_reasons:=array_append(v_reasons,'NEW_DEVICE'); end if;
    if v_failed>0 and v_en_PREV_FAILED then v_score:=v_score+v_score_PREV_FAILED; v_reasons:=array_append(v_reasons,'PREVIOUS_FAILED_DELIVERY'); end if;
    if v_rejected>0 and v_en_PREV_REJECTED then v_score:=v_score+v_score_PREV_REJECTED; v_reasons:=array_append(v_reasons,'PREVIOUS_REJECTED_ORDER'); end if;
    if v_cancelled>=3 and v_en_THREE_PLUS_CANCEL then v_score:=v_score+v_score_THREE_PLUS_CANCEL; v_reasons:=array_append(v_reasons,'THREE_PLUS_CANCELLATIONS'); end if;
    v_is_large:=coalesce(new_row.subtotal,0) >= v_large_threshold;
    if v_is_large and v_en_LARGE_ORDER then v_score:=v_score+v_score_LARGE_ORDER; v_reasons:=array_append(v_reasons,'LARGE_ORDER'); end if;
    if v_is_rapid and v_en_RAPID_ORDERS then v_score:=v_score+v_score_RAPID_ORDERS; v_reasons:=array_append(v_reasons,'RAPID_ORDERS'); end if;
    if v_successful>=5 and v_en_FIVE_PLUS_SUCCESS then v_score:=v_score+v_score_FIVE_PLUS_SUCCESS; v_reasons:=array_append(v_reasons,'FIVE_PLUS_SUCCESSFUL');
    elsif v_successful>=3 and v_en_THREE_PLUS_SUCCESS then v_score:=v_score+v_score_THREE_PLUS_SUCCESS; v_reasons:=array_append(v_reasons,'THREE_PLUS_SUCCESSFUL'); end if;
    if v_verified and v_en_VERIFIED_PHONE then v_score:=v_score+v_score_VERIFIED_PHONE; v_reasons:=array_append(v_reasons,'VERIFIED_PHONE'); end if;
    if v_device_customer_count>=2 and v_en_MULTI_DEVICE then v_score:=v_score+v_score_MULTI_DEVICE; v_reasons:=array_append(v_reasons,'MULTIPLE_ACCOUNTS_DEVICE'); end if;
    if v_address_customer_count>=2 and v_en_MULTI_ADDRESS then v_score:=v_score+v_score_MULTI_ADDRESS; v_reasons:=array_append(v_reasons,'MULTIPLE_ACCOUNTS_ADDRESS'); end if;
    if v_address_failed_count>=3 and v_en_ADDR_HIGH_FAIL then v_score:=v_score+v_score_ADDR_HIGH_FAIL; v_reasons:=array_append(v_reasons,'ADDRESS_HIGH_FAILURE'); end if;
    if array_length(v_reasons,1) is not null then
      select bool_and(coalesce(rr.is_extrinsic, false)) into v_extrinsic_only
        from unnest(v_reasons) as elem
        left join public.risk_rules rr on rr.rule_code = elem;
      if v_extrinsic_only is null then
        select bool_and(elem = any(array['NEW_DEVICE','MULTIPLE_ACCOUNTS_DEVICE','MULTIPLE_ACCOUNTS_ADDRESS','ADDRESS_HIGH_FAILURE'])) into v_extrinsic_only from unnest(v_reasons) as elem;
      end if;
      if coalesce(v_extrinsic_only, false) and v_score > v_medium_max then v_score:=v_medium_max; end if;
    end if;
    if v_score<0 then v_score:=0; end if;
    if v_score>100 then v_score:=100; end if;
    if v_score <= v_low_max then v_level:='low'; v_action:='approved';
    elsif v_score <= v_medium_max then v_level:='medium'; v_action:='needs_verification';
    else v_level:='high'; v_action:='rejected'; end if;
    update public.orders set risk_score=v_score, risk_level=v_level, risk_action=v_action, risk_reasons=to_jsonb(v_reasons), risk_evaluated_at=now() where id=p_order_id;
  end;
end;
$$;

comment on function public.evaluate_order_risk(uuid) is
  'RISK-04/09 callable re-evaluation (SECURITY DEFINER). Data-driven extrinsic via risk_rules.is_extrinsic. Mirrors evaluate_order_risk_trigger; keep SQL/Dart identical (lib/domain/risk_engine.dart).';

revoke all on function public.evaluate_order_risk(uuid) from public;
grant execute on function public.evaluate_order_risk(uuid) to authenticated;
grant execute on function public.evaluate_order_risk(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Ensure triggers remain alphabetical (no ordering change in this migration)
-- ---------------------------------------------------------------------------
-- Validate trigger existence (idempotent)
do $$ begin
  if not exists (select 1 from pg_trigger where tgname='trg_b_evaluate_order_risk') then
    raise exception '0027: trg_b_evaluate_order_risk missing — run 0022 first';
  end if;
end $$;

commit;
