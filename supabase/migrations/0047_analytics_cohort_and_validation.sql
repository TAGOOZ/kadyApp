begin;

-- 0047: analytics fixes + cohort A/B + nothing churn + constraint validation prep

-- ---------------------------------------------------------------------------
-- 1) Cohort table for A/B testing (deterministic assignment via hash)
-- ---------------------------------------------------------------------------
create table if not exists public.customer_cohorts (
  phone text primary key references public.customers(phone) on delete cascade,
  variant text not null check (variant in ('control','variant_a','variant_b','variant_c')),
  assigned_at timestamptz not null default now(),
  assigned_by text
);
comment on table public.customer_cohorts is '0047 A/B cohort assignment — deterministic hash, admin editable.';

alter table public.customer_cohorts enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where tablename='customer_cohorts' and policyname='cc_select_own') then
    create policy cc_select_own on public.customer_cohorts for select to authenticated using (exists (select 1 from customers c where c.phone=customer_cohorts.phone and c.google_user_id=auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where tablename='customer_cohorts' and policyname='cc_staff_read') then
    create policy cc_staff_read on public.customer_cohorts for select to authenticated using (public.has_any_role(array['staff','admin']::text[]));
  end if;
  if not exists (select 1 from pg_policies where tablename='customer_cohorts' and policyname='cc_admin_write') then
    create policy cc_admin_write on public.customer_cohorts for all to authenticated using (public.is_admin()) with check (public.is_admin());
  end if;
end $$;

-- deterministic helper: assign based on md5(phone) mod 4 -> control/A/B/C (stable)
create or replace function public.assign_cohort_deterministic(p_phone text)
returns text language sql stable as $$
  select case (('x' || substr(md5(p_phone),1,8))::bit(32)::int % 4)
    when 0 then 'control'
    when 1 then 'variant_a'
    when 2 then 'variant_b'
    else 'variant_c' end;
$$;

create or replace function public.ensure_cohort(p_phone text)
returns text language plpgsql security definer set search_path=public, pg_temp as $$
declare v text;
begin
  select variant into v from public.customer_cohorts where phone=p_phone;
  if found then return v; end if;
  v := public.assign_cohort_deterministic(p_phone);
  insert into public.customer_cohorts(phone, variant) values (p_phone, v) on conflict (phone) do nothing;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Fix v_reward_repeat_rate to include 'nothing' + add nothing churn view
-- ---------------------------------------------------------------------------
create or replace view public.v_reward_repeat_rate as
 with rewards as (
    select phone, prize, created_at from public.game_plays
 )
 select
    r.prize,
    count(*) as times_won,
    count(*) filter (where exists (select 1 from public.orders o where o.phone=r.phone and o.created_at > r.created_at and o.created_at < r.created_at + interval '7 days')) as followed_by_order_7d,
    round(100.0* count(*) filter (where exists (select 1 from public.orders o where o.phone=r.phone and o.created_at > r.created_at and o.created_at < r.created_at + interval '7 days')) / nullif(count(*),0),2) as repeat_rate_7d_pct
 from rewards r group by r.prize order by repeat_rate_7d_pct desc;
comment on view public.v_reward_repeat_rate is '0047 fix: includes nothing (was excluded) to measure try-again churn.';

create or replace view public.v_nothing_churn as
  select
    gp.phone,
    gp.created_at as spin_at,
    gp.prize,
    exists (select 1 from public.orders o where o.phone=gp.phone and o.created_at > gp.created_at and o.created_at < gp.created_at + interval '7 days') as ordered_within_7d,
    exists (select 1 from public.orders o where o.phone=gp.phone and o.created_at > gp.created_at and o.created_at < gp.created_at + interval '30 days') as ordered_within_30d
  from public.game_plays gp where gp.game='spinner';
comment on view public.v_nothing_churn is '0047: churn after nothing vs win.';

-- ---------------------------------------------------------------------------
-- 3) Prepare constraint validation (do not block, just manual)
-- ---------------------------------------------------------------------------
-- Provide helper to validate existing rows before final VALIDATE
create or replace function public.validate_loyalty_constraints()
returns table(constraint_name text, invalid_count bigint) language plpgsql security definer set search_path=public, pg_temp as $$
begin
  return query select 'chk_loyalty_points'::text, count(*)::bigint from public.loyalty_state where points < 0
  union all select 'chk_loyalty_lifetime', count(*) from public.loyalty_state where lifetime_points < 0
  union all select 'chk_loyalty_stamps', count(*) from public.loyalty_state where stamps < 0 or stamps >=10
  union all select 'chk_loyalty_cards', count(*) from public.loyalty_state where completed_cards < 0
  union all select 'chk_loyalty_tokens', count(*) from public.loyalty_state where spinner_tokens <0 or match_tokens <0 or scratch_tokens <0
  union all select 'chk_loyalty_token_cap', count(*) from public.loyalty_state where coalesce(spinner_tokens,0) >5 or coalesce(match_tokens,0) >5 or coalesce(scratch_tokens,0) >5;
end;
$$;

-- Attempt to validate if clean — will fail if invalid rows exist, but we try
do $$
begin
  -- only validate if helper reports 0 invalid
  if (select sum(invalid_count) from public.validate_loyalty_constraints()) = 0 then
    execute 'alter table public.loyalty_state validate constraint chk_loyalty_points';
    execute 'alter table public.loyalty_state validate constraint chk_loyalty_lifetime';
    execute 'alter table public.loyalty_state validate constraint chk_loyalty_stamps';
    execute 'alter table public.loyalty_state validate constraint chk_loyalty_cards';
    execute 'alter table public.loyalty_state validate constraint chk_loyalty_tokens';
    execute 'alter table public.loyalty_state validate constraint chk_loyalty_token_cap';
  end if;
exception when others then
  -- leave as NOT VALID if existing dirty rows; admin must clean
  null;
end $$;

commit;
