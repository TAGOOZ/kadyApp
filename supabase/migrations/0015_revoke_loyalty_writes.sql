-- 0015_revoke_loyalty_writes.sql — SECURITY-01
-- Revoke client direct loyalty_state writes (loyalty_update_own) which
-- allowed any auth user to farm points/stamps via PostgREST UPDATE.
-- After this, loyalty_state is only writable via SECURITY DEFINER RPCs
-- or server triggers (credit_new_order, staff_apply_stamp).
-- Client must call persist_loyalty_state RPC or trigger-based credit.

-- 1) Drop the overly-permissive own-row UPDATE policy
drop policy if exists loyalty_update_own on public.loyalty_state;

-- Ensure staff/admin read remains (not write)
-- loyalty_select_own and loyalty_staff_admin_read remain

-- 2) RPC for client persist (games, token consume) — still validates ownership
--    within the function (auth.uid() must own the phone via customers).
--    This replaces the direct table UPDATE in LoyaltyController._persist
--    and creditProcessedOrder. The function is security definer so RLS
--    on loyalty_state is bypassed, but ownership is re-checked inside.

create or replace function public.persist_loyalty_state(
  p_phone text,
  p_points int,
  p_lifetime_points int,
  p_stamps int,
  p_completed_cards int,
  p_spinner_tokens int,
  p_match_tokens int,
  p_scratch_tokens int,
  p_double_next_order boolean,
  p_vouchers jsonb,
  p_processed_orders jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owned boolean;
begin
  -- Ownership check: caller must own the phone or be staff/admin (for tests)
  select exists (
    select 1 from public.customers c
    where c.phone = p_phone and c.google_user_id = auth.uid()
  ) or public.has_any_role(array['staff','admin']::text[])
  into v_owned;

  if not v_owned then
    raise exception 'persist_loyalty_state: not owned' using errcode = '42501';
  end if;

  update public.loyalty_state
     set points = p_points,
         lifetime_points = p_lifetime_points,
         stamps = p_stamps,
         completed_cards = p_completed_cards,
         spinner_tokens = p_spinner_tokens,
         match_tokens = p_match_tokens,
         scratch_tokens = p_scratch_tokens,
         double_next_order = p_double_next_order,
         vouchers = coalesce(p_vouchers, '[]'::jsonb),
         processed_orders = coalesce(p_processed_orders, '[]'::jsonb),
         updated_at = now()
   where phone = p_phone;

  if not found then
    -- If row missing (should exist via handle_new_customer), create it
    insert into public.loyalty_state(phone, points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, vouchers, processed_orders)
    values (p_phone, p_points, p_lifetime_points, p_stamps, p_completed_cards, p_spinner_tokens, p_match_tokens, p_scratch_tokens, p_double_next_order, coalesce(p_vouchers,'[]'::jsonb), coalesce(p_processed_orders,'[]'::jsonb));
  end if;
end;
$$;

comment on function public.persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) is 'SECURITY-01: RPC to persist loyalty_state after ownership check — replaces direct RLS UPDATE.';

revoke all on function public.persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) from public;
grant execute on function public.persist_loyalty_state(text,int,int,int,int,int,int,int,boolean,jsonb,jsonb) to authenticated;

-- 3) Optional narrower grant_points RPC for incremental adds (used by games)
create or replace function public.grant_loyalty_points(
  p_phone text,
  p_delta int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owned boolean;
begin
  if p_delta is null or p_delta <= 0 then return; end if;
  select exists (
    select 1 from public.customers c
    where c.phone = p_phone and c.google_user_id = auth.uid()
  ) into v_owned;
  if not v_owned then
    raise exception 'grant_loyalty_points: not owned' using errcode = '42501';
  end if;
  update public.loyalty_state
     set points = points + p_delta,
         lifetime_points = lifetime_points + p_delta,
         updated_at = now()
   where phone = p_phone;
end;
$$;

revoke all on function public.grant_loyalty_points(text,int) from public;
grant execute on function public.grant_loyalty_points(text,int) to authenticated;
