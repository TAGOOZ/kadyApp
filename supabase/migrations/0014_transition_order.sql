-- 0014_transition_order.sql — atomic status transition + audit event
-- Wraps the two PostgREST calls in StaffOrdersRepo.transition and
-- DriverOrdersRepo.markDelivered into one transaction (CORRECTNESS-03).
-- Staff/driver previously did: update orders → insert order_events,
-- leaving a window where status advanced but event was missing if the
-- second call failed. Now a single SECURITY DEFINER RPC guarantees
-- both or neither.

create or replace function public.transition_order(
  p_order_id uuid,
  p_status text,
  p_reject_reason text default null,
  p_assigned_driver uuid default null,
  p_actor text default 'staff'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_role boolean;
begin
  -- Must be staff/driver/admin to transition orders
  v_has_role := public.has_any_role(array['staff','driver','admin']::text[]);
  if not v_has_role then
    raise exception 'transition_order: insufficient role' using errcode = '42501';
  end if;

  -- Validate status vocabulary (mirrors orders.status check)
  if p_status not in ('new','accepted','in_prep','ready','out_for_delivery','done','cancelled') then
    raise exception 'transition_order: invalid status %', p_status using errcode = '22023';
  end if;

  -- Atomically update order and insert event
  update public.orders
     set status = p_status,
         reject_reason = case when p_status = 'cancelled' then coalesce(p_reject_reason, reject_reason) else reject_reason end,
         assigned_driver = coalesce(p_assigned_driver, assigned_driver),
         updated_at = now()
   where id = p_order_id;

  if not found then
    raise exception 'transition_order: order % not found', p_order_id using errcode = 'P0002';
  end if;

  insert into public.order_events(order_id, status, actor, at)
  values (p_order_id, p_status, coalesce(p_actor, 'staff'), now());
end;
$$;

comment on function public.transition_order(uuid,text,text,uuid,text) is 'Atomic orders.status update + order_events insert for staff/driver (CORRECTNESS-03).';

-- Grant to authenticated (RLS still enforced via has_any_role check inside)
revoke all on function public.transition_order(uuid,text,text,uuid,text) from public;
grant execute on function public.transition_order(uuid,text,text,uuid,text) to authenticated;
