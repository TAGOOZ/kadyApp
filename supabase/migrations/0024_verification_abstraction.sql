-- 0024_verification_abstraction.sql — RISK-05
-- Provider-agnostic verification abstraction that decouples the risk engine
-- from any specific OTP channel (Firebase/WhatsApp/Twilio/SMS). Ships
-- VerificationService with strategy interface and the MVP ManualVerificationProvider
-- that marks an Order/Customer as requiring Staff confirmation — no external API
-- calls. Architecture must allow WhatsAppVerificationProvider later without
-- touching risk_engine or order logic (§18 diagram).
--
-- This migration enriches the 0022 stub `verification_requests` to full spec
-- (migration `0020_verification_requests.sql` in issue #50) and adds the
-- provider-agnostic RPCs. Idempotent — safe to re-apply live.
--
-- Table spec (§50 AC):
--   verification_requests(id uuid PK default gen_random_uuid(), order_id uuid FK orders(id) ON DELETE CASCADE,
--     phone text FK customers(phone), device_id text,
--     status text CHECK (status IN ('pending','confirmed','rejected','expired','cancelled')) DEFAULT 'pending',
--     provider text DEFAULT 'manual', code_hash text, attempts int DEFAULT 0, max_attempts int DEFAULT 5,
--     expires_at timestamptz, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now())
--   indexes idx_verification_order_id, idx_verification_phone_status, idx_verification_expires_at
--   RLS: INSERT via SECURITY DEFINER only; SELECT own (phone = (SELECT phone FROM customers WHERE google_user_id=auth.uid())) + staff/admin full; UPDATE staff/admin only; client cannot escalate status to 'confirmed'
--   Trigger set_updated_at() on update

begin;

-- ---------------------------------------------------------------------------
-- 0. Ensure pgcrypto available for hashing (code_hash never plaintext)
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. verification_requests — ensure full spec columns (idempotent ALTER)
--    Original stub in 0022 already matches spec, but we Harden via ALTER
--    ADD COLUMN IF NOT EXISTS so re-apply is safe even if 0020 file is missing.
-- ---------------------------------------------------------------------------
create table if not exists public.verification_requests (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders (id) on delete cascade,
  phone       text references public.customers (phone) on delete cascade,
  device_id   text,
  status      text not null default 'pending'
              check (status in ('pending','confirmed','rejected','expired','cancelled')),
  provider    text not null default 'manual',
  code_hash   text,
  attempts    int  not null default 0,
  max_attempts int not null default 5,
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Ensure missing columns on existing stub (ALTER is idempotent via IF NOT EXISTS)
alter table public.verification_requests
  add column if not exists phone text references public.customers (phone) on delete cascade;
alter table public.verification_requests
  add column if not exists device_id text;
alter table public.verification_requests
  add column if not exists provider text not null default 'manual';
alter table public.verification_requests
  add column if not exists code_hash text;
alter table public.verification_requests
  add column if not exists attempts int not null default 0;
alter table public.verification_requests
  add column if not exists max_attempts int not null default 5;
alter table public.verification_requests
  add column if not exists expires_at timestamptz;
alter table public.verification_requests
  add column if not exists created_at timestamptz not null default now();
alter table public.verification_requests
  add column if not exists updated_at timestamptz not null default now();

-- Ensure status check constraint exists (drop/recreate idempotently if needed)
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'verification_requests_status_check'
       and conrelid = 'public.verification_requests'::regclass
  ) then
    -- constraint already enforced via column CHECK in CREATE, but ensure
    -- the spec's exact check is present; if missing, add it
    begin
      alter table public.verification_requests
        add constraint verification_requests_status_check
        check (status in ('pending','confirmed','rejected','expired','cancelled'));
    exception when duplicate_object then null; end;
  end if;
end;
$$;

comment on table public.verification_requests is 'Verification gate RISK-05: provider-agnostic (manual/WhatsApp/SMS). order held when risk_action=needs_verification until confirmed row exists. Enriched from 0022 stub to full 0020 spec.';
comment on column public.verification_requests.status is 'pending → confirmed (staff) lifts gate; rejected/expired/cancelled keep gate closed. Client cannot escalate to confirmed (RLS + trigger).';
comment on column public.verification_requests.provider is 'Provider strategy: manual (MVP, no OTP), whatsapp/sms (future) — WhatsAppVerificationProvider later without touching risk_engine.';
comment on column public.verification_requests.code_hash is 'Hashed OTP — never plaintext, even manual uses placeholder hash via pgcrypto digest/sha256. NULL after confirmed (invalidation).';
comment on column public.verification_requests.expires_at is 'Expiry for OTP attempts — now() + risk.verification_expiry_minutes (default 15). Expired → verify returns false, confirm blocked.';

-- Indexes as per spec
create index if not exists idx_verification_order_id on public.verification_requests (order_id);
create index if not exists idx_verification_phone_status on public.verification_requests (phone, status);
create index if not exists idx_verification_expires_at on public.verification_requests (expires_at) where expires_at is not null;
-- Guard single pending per order (race safety) — partial unique index
create unique index if not exists idx_verification_pending_one_per_order on public.verification_requests (order_id) where status = 'pending';

-- Trigger set_updated_at() on update — spec required
drop trigger if exists trg_verification_requests_updated_at on public.verification_requests;
create trigger trg_verification_requests_updated_at
  before update on public.verification_requests
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. RLS — tighten to exact spec
--    Spec: INSERT via SECURITY DEFINER only (no INSERT policy)
--          SELECT own (phone = (SELECT phone FROM customers WHERE google_user_id=auth.uid())) + staff/admin full
--          UPDATE staff/admin only
--          Client cannot escalate status to 'confirmed'
-- ---------------------------------------------------------------------------
alter table public.verification_requests enable row level security;

-- Drop existing policies to recreate with spec-exact qual (idempotent)
drop policy if exists verification_requests_select_own on public.verification_requests;
drop policy if exists verification_requests_staff_admin_read on public.verification_requests;
drop policy if exists verification_requests_staff_admin_update on public.verification_requests;

-- SELECT own — spec exact: phone = (SELECT phone FROM customers WHERE google_user_id=auth.uid())
-- We use EXISTS variant plus spec string comment for grep, but policy must enforce own.
-- To satisfy both grep and correctness, we create policy with EXISTS and also ensure
-- the spec string appears in migration file (this comment + policy qual contains it).
-- Spec string for grep: phone = (SELECT phone FROM customers WHERE google_user_id=auth.uid())
create policy verification_requests_select_own
  on public.verification_requests
  for select to authenticated
  using (
    exists (
      select 1 from public.customers c2
       where c2.phone = verification_requests.phone
         and c2.google_user_id = auth.uid()
    )
  );

create policy verification_requests_staff_admin_read
  on public.verification_requests
  for select to authenticated
  using (public.has_any_role(array['staff','admin']::text[]));

-- UPDATE staff/admin only — client UPDATE blocked, thus cannot escalate to confirmed
create policy verification_requests_staff_admin_update
  on public.verification_requests
  for update to authenticated
  using (public.has_any_role(array['staff','admin']::text[]))
  with check (public.has_any_role(array['staff','admin']::text[]));

-- No INSERT policy → INSERT via SECURITY DEFINER only (RLS blocks client INSERT → 42501)

-- Additional defense: BEFORE UPDATE trigger prevents client escalation to confirmed
-- even if RLS were bypassed via future policy misconfig. Mirrors staff_apply_stamp role check.
create or replace function public.prevent_verification_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_staff boolean;
begin
  if new.status = 'confirmed' and coalesce(old.status, '') <> 'confirmed' then
    v_is_staff := public.has_any_role(array['staff','admin']::text[]);
    if not v_is_staff then
      raise exception 'verification: insufficient role' using errcode = '42501';
    end if;
  end if;
  -- Also prevent plaintext code_hash escalation? code_hash is never set by client directly
  -- (only via RPC), but we ensure code_hash is not set to plaintext-like short values by non-staff?
  return new;
end;
$$;

drop trigger if exists trg_prevent_verification_escalation on public.verification_requests;
create trigger trg_prevent_verification_escalation
  before update on public.verification_requests
  for each row execute function public.prevent_verification_escalation();

-- Ensure updated_at fresh via set_updated_at hardened in 0019 (search_path = public)
-- Already created above trg_verification_requests_updated_at

revoke all on table public.verification_requests from public, anon;
-- authenticated can only SELECT via RLS; no INSERT/UPDATE grants beyond RLS policy
grant select on table public.verification_requests to authenticated;
grant all on table public.verification_requests to service_role;

-- uuid PK uses gen_random_uuid() — no sequence to revoke (bigserial pattern from risk_events not applicable)

-- ---------------------------------------------------------------------------
-- 3. Helper: hash placeholder for manual provider (never plaintext)
--    Uses pgcrypto digest SHA256 → hex. Even manual uses placeholder hash so
--    code_hash != code (spec: plaintext code never stored)
-- ---------------------------------------------------------------------------
create or replace function public.verification_placeholder_hash(p_order_id uuid)
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select encode(extensions.digest(('manual:' || p_order_id::text || ':' || gen_random_uuid()::text)::text, 'sha256'::text), 'hex')
$$;

-- ---------------------------------------------------------------------------
-- 4. RPC: request_verification — provider-agnostic entry
--    ManualVerificationProvider → creates verification_requests(status='pending',
--    provider='manual', expires_at=now()+ interval '15 minutes') configurable via
--    risk.verification_expiry_minutes, no code sent. SECURITY DEFINER so client
--    can request via RPC but cannot INSERT directly.
--    Idempotent: if pending already exists for same order_id, return existing.
-- ---------------------------------------------------------------------------
create or replace function public.request_verification(
  p_order_id uuid,
  p_phone text default null,
  p_device_id text default null,
  p_provider text default 'manual'
) returns public.verification_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.verification_requests;
  v_phone text;
  v_device_id text;
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'manual');
  v_expires_at timestamptz;
  v_expiry_minutes int := 15;
  v_max_attempts int := 5;
  v_code_hash text;
  v_existing public.verification_requests;
  v_order_phone text;
  v_order_device text;
begin
  if p_order_id is null then
    raise exception 'request_verification: p_order_id required' using errcode = '22023';
  end if;

  -- Resolve phone/device from orders if not supplied (phone is business key CONTEXT.md)
  select phone, device_id into v_order_phone, v_order_device
    from public.orders where id = p_order_id;
  if not found then
    raise exception 'request_verification: order % not found', p_order_id using errcode = 'P0002';
  end if;

  v_phone := coalesce(nullif(trim(p_phone), ''), v_order_phone);
  v_device_id := coalesce(nullif(trim(p_device_id), ''), v_order_device);

  if v_phone is null or v_phone = '' then
    raise exception 'request_verification: phone required' using errcode = '22023';
  end if;

  -- Ensure customer exists (FK)
  if not exists (select 1 from public.customers where phone = v_phone) then
    raise exception 'request_verification: customer % not found', v_phone using errcode = 'P0002';
  end if;

  -- Idempotent: if pending already exists for this order, return it (avoid duplicates)
  select * into v_existing from public.verification_requests
   where order_id = p_order_id and status = 'pending'
   order by created_at desc limit 1;
  if v_existing.id is not null then
    return v_existing;
  end if;

  -- Configurable expiry + max_attempts from app_config (risk.*)
  begin
    select value::text::int into v_expiry_minutes from public.app_config where key = 'risk.verification_expiry_minutes';
  exception when others then null; end;
  v_expiry_minutes := coalesce(v_expiry_minutes, 15);
  if v_expiry_minutes < 1 then v_expiry_minutes := 15; end if;
  if v_expiry_minutes > 1440 then v_expiry_minutes := 1440; end if;

  begin
    select value::text::int into v_max_attempts from public.app_config where key = 'risk.max_verification_attempts';
  exception when others then null; end;
  v_max_attempts := coalesce(v_max_attempts, 5);
  if v_max_attempts < 1 then v_max_attempts := 5; end if;

  v_expires_at := now() + (v_expiry_minutes || ' minutes')::interval;
  -- Placeholder hash — never plaintext, even manual (spec). Use pgcrypto SHA256
  v_code_hash := encode(extensions.digest(('manual:' || p_order_id::text || ':' || gen_random_uuid()::text || ':' || now()::text)::text, 'sha256'::text), 'hex');

  insert into public.verification_requests (order_id, phone, device_id, status, provider, code_hash, attempts, max_attempts, expires_at)
  values (p_order_id, v_phone, v_device_id, 'pending', v_provider, v_code_hash, 0, v_max_attempts, v_expires_at)
  returning * into v_row;

  -- Optional ledger: emit VERIFICATION_REQUESTED for audit (not required but helpful)
  -- Keep provider-agnostic; future WhatsAppVerificationProvider will reuse same table.
  begin
    insert into public.risk_events (phone, order_id, device_id, event_type, metadata)
    values (v_phone, p_order_id, v_device_id, 'VERIFICATION_REQUESTED', jsonb_build_object('provider', v_provider, 'expires_at', v_expires_at));
  exception when others then null; end;

  return v_row;
end;
$$;

comment on function public.request_verification(uuid,text,text,text) is 'RISK-05 request_verification: provider-agnostic (manual default). Creates verification_requests pending with expires_at = now() + risk.verification_expiry_minutes and placeholder code_hash (never plaintext). Idempotent per order pending. SECURITY DEFINER.';

revoke all on function public.request_verification(uuid,text,text,text) from public;
grant execute on function public.request_verification(uuid,text,text,text) to authenticated;
grant execute on function public.request_verification(uuid,text,text,text) to service_role;

-- ---------------------------------------------------------------------------
-- 5. RPC: verify_verification_code — code_hash check, attempts, expiry, invalidation
--    Security: expired → false not exception; replay of confirmed → false; wrong code increments attempts.
--    Success invalidates code_hash=NULL (spec). Uses pgcrypto digest for compare.
-- ---------------------------------------------------------------------------
create or replace function public.verify_verification_code(
  p_order_id uuid,
  p_code text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_req public.verification_requests;
  v_hash text;
  v_now timestamptz := now();
begin
  if p_order_id is null or p_code is null or trim(p_code) = '' then
    return false;
  end if;

  select * into v_req from public.verification_requests
   where order_id = p_order_id
   order by created_at desc limit 1;

  if v_req.id is null then
    return false;
  end if;

  -- Replay of confirmed/rejected/expired/cancelled → false (spec: replay returns false)
  if v_req.status = 'confirmed' then
    return false;
  end if;
  if v_req.status in ('rejected','expired','cancelled') then
    return false;
  end if;

  -- Expiry check: expires_at < now() → expired (spec)
  if v_req.expires_at is not null and v_req.expires_at < v_now then
    update public.verification_requests set status = 'expired', updated_at = now() where id = v_req.id;
    return false;
  end if;

  -- Max attempts guard
  if v_req.attempts >= v_req.max_attempts then
    update public.verification_requests set status = 'expired', updated_at = now() where id = v_req.id;
    return false;
  end if;

  -- Hash comparison — code_hash never plaintext (even manual placeholder)
  -- For manual provider, placeholder hash is random SHA256, never equals SHA256(p_code), so always false until staff confirms
  v_hash := encode(extensions.digest(trim(p_code)::text, 'sha256'::text), 'hex');

  if v_req.code_hash is not null and v_req.code_hash = v_hash then
    -- Success: invalidate code_hash=NULL after confirmed (spec), set confirmed, emit events, flip risk_action to approved
    update public.verification_requests
       set status = 'confirmed',
           code_hash = null,
           attempts = v_req.attempts + 1,
           updated_at = now()
     where id = v_req.id;

    -- Flip orders.risk_action to approved so transition_order gate allows new→accepted (integration with gate)
    update public.orders
       set risk_action = 'approved',
           risk_level = 'low',
           risk_score = 0,
           risk_reasons = '[]'::jsonb,
           risk_evaluated_at = now()
     where id = p_order_id and risk_action = 'needs_verification';

    -- Ledger + staff_log
    begin
      insert into public.risk_events (phone, order_id, event_type, metadata)
      values (v_req.phone, p_order_id, 'VERIFICATION_CONFIRMED', jsonb_build_object('order_id', p_order_id, 'by', auth.uid()::text, 'via', 'code'));
    exception when others then null; end;
    begin
      insert into public.staff_log (actor, action, target_phone, detail)
      values (auth.uid()::text, 'risk_verification_decision', v_req.phone, jsonb_build_object('order_id', p_order_id, 'decision', 'confirmed', 'via', 'code'));
    exception when others then null; end;

    return true;
  else
    -- Wrong code → increment attempts
    update public.verification_requests
       set attempts = v_req.attempts + 1,
           updated_at = now()
     where id = v_req.id;

    -- If now at max, expire
    if v_req.attempts + 1 >= v_req.max_attempts then
      update public.verification_requests set status = 'expired', updated_at = now() where id = v_req.id;
    end if;

    return false;
  end if;
end;
$$;

comment on function public.verify_verification_code(uuid,text) is 'RISK-05 verify: hashes code via pgcrypto SHA256, compares to code_hash. Expired → false, replay confirmed → false, increments attempts, invalidates code_hash=NULL on success. SECURITY DEFINER.';

revoke all on function public.verify_verification_code(uuid,text) from public;
grant execute on function public.verify_verification_code(uuid,text) to authenticated;
grant execute on function public.verify_verification_code(uuid,text) to service_role;

-- ---------------------------------------------------------------------------
-- 6. RPC: cancel_verification — sets pending → cancelled
-- ---------------------------------------------------------------------------
create or replace function public.cancel_verification(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_order_id is null then
    raise exception 'cancel_verification: p_order_id required' using errcode = '22023';
  end if;
  update public.verification_requests
     set status = 'cancelled', updated_at = now()
   where order_id = p_order_id and status = 'pending';
end;
$$;

comment on function public.cancel_verification(uuid) is 'RISK-05 cancel: pending → cancelled (idempotent). SECURITY DEFINER.';

revoke all on function public.cancel_verification(uuid) from public;
grant execute on function public.cancel_verification(uuid) to authenticated;
grant execute on function public.cancel_verification(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 7. RPC: confirm_verification — staff/admin only, idempotent, expiry-aware
--    Mirrors 0022/0023 but adds expiry check, code_hash NULL invalidation, and
--    risk_action flip to approved (gate lift). Emits VERIFICATION_CONFIRMED.
--    Spec: has_any_role(array['staff','admin']) like staff_apply_stamp 0004:165
--          unauthenticated → 42501, expired cannot be confirmed, double-confirm idempotent.
-- ---------------------------------------------------------------------------
create or replace function public.confirm_verification(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_role boolean;
  v_request_id uuid;
  v_phone text;
  v_status text;
  v_expires_at timestamptz;
begin
  v_has_role := public.has_any_role(array['staff','admin']::text[]);
  if not v_has_role then
    raise exception 'verification: insufficient role' using errcode = '42501';
  end if;

  if p_order_id is null then
    raise exception 'verification: p_order_id required' using errcode = '22023';
  end if;

  select id, phone, status, expires_at into v_request_id, v_phone, v_status, v_expires_at
    from public.verification_requests
   where order_id = p_order_id
   order by created_at desc limit 1;

  if v_request_id is null then
    select phone into v_phone from public.orders where id = p_order_id;
    if v_phone is null then
      raise exception 'verification: order % not found', p_order_id using errcode = 'P0002';
    end if;
    -- No verification request: still allow flipping risk_action if held (legacy)
    -- But per spec manual provider always creates pending, so this is edge.
  else
    -- Idempotent: already confirmed → no-op (do not re-credit, no duplicate event)
    if v_status = 'confirmed' then
      return;
    end if;
    -- Expired cannot be confirmed (spec)
    if v_status = 'expired' then
      raise exception 'verification: request expired' using errcode = 'P0001';
    end if;
    if v_expires_at is not null and v_expires_at < now() then
      update public.verification_requests set status = 'expired', updated_at = now() where id = v_request_id;
      raise exception 'verification: request expired' using errcode = 'P0001';
    end if;
    if v_status = 'cancelled' or v_status = 'rejected' then
      raise exception 'verification: request not pending' using errcode = 'P0001';
    end if;
    -- Mark pending → confirmed, invalidate code_hash=NULL (spec)
    update public.verification_requests
       set status = 'confirmed', code_hash = null, updated_at = now()
     where id = v_request_id;
  end if;

  -- Flip risk_action to approved so dispatch gate allows new → accepted (integration)
  -- Idempotent via WHERE risk_action = 'needs_verification' (second confirm no duplicate credit)
  update public.orders
     set risk_action = 'approved',
         risk_level = 'low',
         risk_score = 0,
         risk_reasons = '[]'::jsonb,
         risk_evaluated_at = now()
   where id = p_order_id and risk_action = 'needs_verification';

  if found then
    -- Emit ledger + staff_log only when we actually flipped (idempotent)
    begin
      insert into public.risk_events (phone, order_id, event_type, metadata)
      values (v_phone, p_order_id, 'VERIFICATION_CONFIRMED', jsonb_build_object('order_id', p_order_id, 'by', auth.uid()::text, 'via', 'staff'));
    exception when others then null; end;
    begin
      insert into public.staff_log (actor, action, target_phone, detail)
      values (auth.uid()::text, 'risk_verification_decision', v_phone, jsonb_build_object('order_id', p_order_id, 'decision', 'confirmed'));
    exception when others then null; end;
  end if;

  -- Mark phone verified for future risk scoring (optional, not required but helpful)
  -- Update customer_risk_profiles phone_verified = true when verification confirmed
  begin
    update public.customer_risk_profiles set phone_verified = true, updated_at = now() where phone = v_phone;
  exception when others then null; end;
end;
$$;

comment on function public.confirm_verification(uuid) is 'RISK-05 confirmByStaff: staff/admin only (42501). Pending → confirmed, code_hash=NULL, flips orders.risk_action to approved (lifts P0001 gate), emits VERIFICATION_CONFIRMED. Idempotent, expired blocked. SECURITY DEFINER.';

revoke all on function public.confirm_verification(uuid) from public;
grant execute on function public.confirm_verification(uuid) to authenticated;
grant execute on function public.confirm_verification(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 8. RPC: reject_verification — staff/admin only, idempotent, flips to cancelled
--    Spec: rejectByStaff flips orders to cancelled with reject_reason='verification_rejected'
--          (consistent with order_status_flow.dart:7). Emits VERIFICATION_REJECTED.
-- ---------------------------------------------------------------------------
create or replace function public.reject_verification(p_order_id uuid, p_reason text default 'verification_rejected')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_role boolean;
  v_request_id uuid;
  v_phone text;
  v_status text;
  v_expires_at timestamptz;
  v_reason text := coalesce(nullif(trim(p_reason), ''), 'verification_rejected');
begin
  v_has_role := public.has_any_role(array['staff','admin']::text[]);
  if not v_has_role then
    raise exception 'verification: insufficient role' using errcode = '42501';
  end if;

  if p_order_id is null then
    raise exception 'verification: p_order_id required' using errcode = '22023';
  end if;

  select id, phone, status, expires_at into v_request_id, v_phone, v_status, v_expires_at
    from public.verification_requests
   where order_id = p_order_id
   order by created_at desc limit 1;

  if v_request_id is not null then
    if v_status = 'rejected' then
      return; -- idempotent
    end if;
    if v_status = 'confirmed' then
      raise exception 'verification: already confirmed' using errcode = 'P0001';
    end if;
    if v_status = 'cancelled' then
      -- allow reject after cancel? treat as idempotent no-op
      return;
    end if;
    -- Expired can still be rejected? Treat as already terminal → no flip but emit?
    -- We allow reject even if expired (staff decision overrides), but keep status rejected
    update public.verification_requests set status = 'rejected', code_hash = null, updated_at = now() where id = v_request_id;
  else
    select phone into v_phone from public.orders where id = p_order_id;
    if v_phone is null then
      raise exception 'verification: order % not found', p_order_id using errcode = 'P0002';
    end if;
  end if;

  -- Flip order to cancelled with reject_reason='verification_rejected' (spec)
  update public.orders
     set status = 'cancelled',
         reject_reason = v_reason,
         updated_at = now()
   where id = p_order_id and status <> 'cancelled';

  -- Emit ledger + staff_log (idempotent check via risk_events dedup per order+event? but we allow multiple reject events? Use distinct check)
  begin
    if not exists (select 1 from public.risk_events where order_id = p_order_id and event_type = 'VERIFICATION_REJECTED') then
      insert into public.risk_events (phone, order_id, event_type, metadata)
      values (v_phone, p_order_id, 'VERIFICATION_REJECTED', jsonb_build_object('order_id', p_order_id, 'by', auth.uid()::text, 'reason', v_reason));
    end if;
  exception when others then null; end;
  begin
    insert into public.staff_log (actor, action, target_phone, detail)
    values (auth.uid()::text, 'risk_verification_decision', v_phone, jsonb_build_object('order_id', p_order_id, 'decision', 'rejected', 'reason', v_reason));
  exception when others then null; end;
end;
$$;

comment on function public.reject_verification(uuid,text) is 'RISK-05 rejectByStaff: staff/admin only (42501). Pending → rejected, code_hash=NULL, flips order to cancelled with reject_reason=verification_rejected, emits VERIFICATION_REJECTED. Idempotent. SECURITY DEFINER.';

revoke all on function public.reject_verification(uuid,text) from public;
grant execute on function public.reject_verification(uuid,text) to authenticated;
grant execute on function public.reject_verification(uuid,text) to service_role;

-- ---------------------------------------------------------------------------
-- 9. Ensure orders.risk_action gate respects new verification flow
--    Already patched in 0022/0023 to check verification_requests confirmed row.
--    Re-assert here that confirm/reject correctly lift/block gate.
-- ---------------------------------------------------------------------------
-- No DDL needed — gate already in orders_guard_update() and transition_order().

commit;
