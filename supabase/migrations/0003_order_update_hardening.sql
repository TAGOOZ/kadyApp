-- 0003_order_update_hardening.sql — finding #8 (improve audit):
-- staff/driver/admin UPDATE policy currently exposes every column of every
-- order. Harden with a BEFORE UPDATE guard trigger:
--   * nobody may alter money/items/identity columns after insert (admin may)
--   * driver: only status 'out_for_delivery' -> 'done', only own assigned rows
--     once assignment lands (assigned_driver null-stub means any delivery row
--     until admin assignment ships)
--   * staff/admin: free status transitions within the check-constraint set,
--     plus reject_reason maintenance
-- Run in Supabase SQL editor after 0002_driver_rls.sql.

create or replace function orders_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
begin
  select p.role into actor_role from profiles p where p.user_id = auth.uid();

  if actor_role is null then
    raise exception 'orders: no profile for caller' using errcode = '42501';
  end if;

  -- Money/items/identity are immutable post-insert except to admins.
  if actor_role <> 'admin' then
    if new.subtotal      is distinct from old.subtotal
    or new.delivery_fee  is distinct from old.delivery_fee
    or new.total         is distinct from old.total
    or new.items         is distinct from old.items
    or new.phone         is distinct from old.phone
    or new.google_user_id is distinct from old.google_user_id then
      raise exception 'orders: immutable columns changed' using errcode = '42501';
    end if;
  end if;

  if actor_role = 'driver' then
    if new.status <> 'done'
    or old.status <> 'out_for_delivery'
    or tg_n_cols_changed('status') = false then
      raise exception 'orders: driver may only mark out_for_delivery -> done'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- staff / admin fall through: full status vocabulary allowed.
  return new;
end;
$$;

drop trigger if exists trg_orders_guard on orders;
create trigger trg_orders_guard
  before update on orders
  for each row execute function orders_guard_update();

-- Helper: did the UPDATE statement set a specific column?
create or replace function tg_n_cols_changed(col text)
returns boolean
language plpgsql
as $$
declare
  changed boolean := false;
  col_name text := col;
begin
  case col_name
    when 'status' then changed := new.status is distinct from old.status;
    else changed := true;
  end case;
  return changed;
end;
$$;
