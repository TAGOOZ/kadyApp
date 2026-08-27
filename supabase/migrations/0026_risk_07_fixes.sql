-- 0026_risk_07_fixes.sql — Fix RISK-07 review findings
-- Critical: orders_guard_update bypass via current_user, rapid throttle audit-only,
-- dedup hash parity, P0001 brittle, reject cancelled.

begin;

-- ---------------------------------------------------------------------------
-- 1. Fix orders_guard_update — use auth.role()/profiles, not current_user
-- ---------------------------------------------------------------------------
create or replace function public.orders_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  v_has_verification bool := false;
  v_caller_role text := coalesce(auth.role(), '');
begin
  select p.role into actor_role from public.profiles p where p.user_id = auth.uid();

  if v_caller_role = 'anon' then
    raise exception 'orders: no profile for caller' using errcode = '42501';
  end if;

  if actor_role is null and v_caller_role not in ('service_role', '') then
    raise exception 'orders: no profile for caller' using errcode = '42501';
  end if;

  if v_caller_role = 'authenticated' and coalesce(actor_role,'') <> 'admin' then
    if new.subtotal       is distinct from old.subtotal
    or new.delivery_fee   is distinct from old.delivery_fee
    or new.total          is distinct from old.total
    or new.items          is distinct from old.items
    or new.phone          is distinct from old.phone
    or new.google_user_id is distinct from old.google_user_id then
      raise exception 'orders: immutable columns changed' using errcode = '42501';
    end if;
  end if;

  if new.risk_score        is distinct from old.risk_score
  or new.risk_level        is distinct from old.risk_level
  or new.risk_action       is distinct from old.risk_action
  or new.risk_reasons      is distinct from old.risk_reasons
  or new.risk_evaluated_at is distinct from old.risk_evaluated_at
  or new.device_id         is distinct from old.device_id then
    if v_caller_role = 'authenticated' and coalesce(actor_role,'') not in ('staff','admin') then
      raise exception 'orders: risk columns are server-authoritative' using errcode = '42501';
    end if;
    if v_caller_role = 'anon' then
      raise exception 'orders: risk columns are server-authoritative' using errcode = '42501';
    end if;
  end if;

  if old.risk_action in ('needs_verification','rejected')
     and new.status is distinct from old.status
     and new.status in ('accepted','in_prep','ready','out_for_delivery','done') then
    if old.risk_action = 'needs_verification' then
      select exists (
        select 1 from public.verification_requests
         where order_id = new.id
           and status = 'confirmed'
      ) into v_has_verification;
      if not v_has_verification then
        raise exception 'needs verification' using errcode = 'P0001';
      end if;
    else
      raise exception 'order rejected' using errcode = 'P0001';
    end if;
  end if;

  if coalesce(actor_role,'') = 'driver' then
    if new.status <> 'done'
    or old.status <> 'out_for_delivery'
    or public.tg_n_cols_changed('status') = false then
      raise exception 'orders: driver may only mark out_for_delivery -> done'
        using errcode = '42501';
    end if;
    return new;
  end if;

  return new;
end;
$$;

comment on function public.orders_guard_update() is 'RISK-07 fix 0026: use auth.role()/profiles not current_user; allows risk_* only for staff/admin or service_role/postgres, money still admin-only.';

drop trigger if exists trg_orders_guard on public.orders;
create trigger trg_orders_guard
  before update on public.orders
  for each row execute function public.orders_guard_update();

-- ---------------------------------------------------------------------------
-- 2. Enable rapid_orders hard throttle (configurable) — previously audit-only
-- ---------------------------------------------------------------------------
create or replace function public.enforce_order_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  max_n int;
  win_min int;
  recent int;
  rapid_n int;
  rapid_win int;
  rapid_recent int;
begin
  select value::text::int into max_n   from public.app_config where key = 'rate_limit_max';
  select value::text::int into win_min from public.app_config where key = 'rate_limit_window_min';
  if coalesce(max_n, 5) > 0 and coalesce(win_min, 5) > 0 then
    select count(*) into recent
      from public.orders o
     where o.phone = new.phone
       and o.created_at > now() - make_interval(mins => coalesce(win_min, 5));
    if recent >= coalesce(max_n, 5) then
      raise exception 'orders: rate limited'
        using errcode = 'P0001', hint = 'too_many_orders';
    end if;
  end if;

  select value::text::int into rapid_n   from public.app_config where key = 'risk.rapid_orders_count';
  select value::text::int into rapid_win from public.app_config where key = 'risk.rapid_orders_window_minutes';
  rapid_n := coalesce(rapid_n, 3);
  rapid_win := coalesce(rapid_win, 30);
  if rapid_n > 0 and rapid_win > 0 and new.phone is not null then
    select count(*) into rapid_recent
      from public.orders
     where phone = new.phone
       and created_at > now() - make_interval(mins => rapid_win);
    if (rapid_recent + 1) >= rapid_n then
      raise exception 'rapid orders rate limited' using errcode = 'P0001', hint = 'rapid_orders';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_order_rate_limit() is 'RISK-07 fix 0026: rapid_orders now hard throttles (configurable 3/30) via P0001 rapid_orders; retains 5/5.';

drop trigger if exists trg_c_enforce_order_rate_limit on public.orders;
create trigger trg_c_enforce_order_rate_limit
  before insert on public.orders
  for each row execute function public.enforce_order_rate_limit();

drop trigger if exists trg_00_assign_display_number on public.orders;
drop trigger if exists trg_a_validate_order_pricing on public.orders;
drop trigger if exists trg_b_evaluate_order_risk on public.orders;
drop trigger if exists trg_c_enforce_order_rate_limit on public.orders;
drop trigger if exists trg_d_enforce_order_dedup on public.orders;
create trigger trg_00_assign_display_number
  before insert on public.orders
  for each row execute function public.assign_order_display_number();
create trigger trg_a_validate_order_pricing
  before insert on public.orders
  for each row execute function public.validate_order_pricing();
create trigger trg_b_evaluate_order_risk
  before insert on public.orders
  for each row execute function public.evaluate_order_risk_trigger();
create trigger trg_c_enforce_order_rate_limit
  before insert on public.orders
  for each row execute function public.enforce_order_rate_limit();
create trigger trg_d_enforce_order_dedup
  before insert on public.orders
  for each row execute function public.enforce_order_dedup();

comment on function public.compute_order_dedup_hash(jsonb, uuid) is 'RISK-07 fix 0026: md5(p_items::text|p_address_id) — client now avoids recomputing hash and relies on hint + recent scan; hash remains for index.';

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='verification_requests' and column_name='code') then
    raise exception 'verification_requests.code column must not exist' using errcode = '42P01';
  end if;
end
$$;

commit;
