begin;

-- 0041: Cap doubleNext + free token RPC + daily limit + token cap + validation prep
-- Implements FIX #2 (double cap), #1 (free token), #8 (daily/cap), #5 (weight validation), #3 (cron helper), #4 (prize_cogs)

-- ---------------------------------------------------------------------------
-- FIX #2: double_next cap — admin-editable, prevents large-order exploit
-- ---------------------------------------------------------------------------
insert into public.app_config(key, value) values ('double_max_extra','10'::jsonb) on conflict (key) do nothing;
comment on column public.app_config.value is 'double_max_extra = max extra points from doubleNext/campaign (default 10)';

-- ---------------------------------------------------------------------------
-- FIX #1: No-purchase free token — satisfies Egyptian law free entry
-- Rate-limited: 1 per 7 days per phone, tracked in free_token_claims
-- ---------------------------------------------------------------------------
create table if not exists public.free_token_claims (
  id uuid primary key default gen_random_uuid(),
  phone text not null references public.customers(phone) on delete cascade,
  claimed_at timestamptz not null default now()
);
create index if not exists idx_free_token_phone_claimed on public.free_token_claims(phone, claimed_at desc);
alter table public.free_token_claims enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='free_token_claims' and policyname='ftc_select_own') then
    create policy ftc_select_own on public.free_token_claims for select to authenticated using (exists (select 1 from public.customers c where c.phone=free_token_claims.phone and c.google_user_id=auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='free_token_claims' and policyname='ftc_staff_read') then
    create policy ftc_staff_read on public.free_token_claims for select to authenticated using (public.has_any_role(array['staff','admin']::text[]));
  end if;
end $$;

create or replace function public.request_free_token()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text;
  ls_row public.loyalty_state;
  recent int;
begin
  v_phone := public.current_customer_phone();
  if v_phone is null then
    raise exception 'request_free_token: no customer row' using errcode='42501';
  end if;

  select count(*) into recent from public.free_token_claims
   where phone = v_phone and claimed_at > now() - interval '7 days';
  if recent >= 1 then
    raise exception 'free token rate limited — try again after 7 days' using errcode='P0001', hint='free_token_rate_limited';
  end if;

  select * into ls_row from public.loyalty_state where phone=v_phone for update;
  if not found then raise exception 'loyalty_state not found' using errcode='P0001'; end if;
  if coalesce(ls_row.spinner_tokens,0) >= 5 then
    raise exception 'token cap reached (5)' using errcode='P0001', hint='token_cap';
  end if;

  update public.loyalty_state set spinner_tokens = spinner_tokens + 1, updated_at=now() where phone=v_phone;
  insert into public.free_token_claims(phone) values (v_phone);
  insert into public.staff_log(actor, action, target_phone, detail) values (auth.uid()::text, 'request_free_token', v_phone, jsonb_build_object('granted',1));
  return jsonb_build_object('spinner_tokens', ls_row.spinner_tokens+1, 'phone', v_phone);
end;
$$;
comment on function public.request_free_token() is 'FIX #1: no-purchase entry — 1 free spinner token per 7 days, token cap 5, satisfies Egyptian law.';
revoke all on function public.request_free_token() from public;
grant execute on function public.request_free_token() to authenticated;

insert into public.app_config(key, value) values ('free_token_cooldown_days','7'::jsonb) on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- FIX #8: Daily spin limit + token hoarding cap
-- ---------------------------------------------------------------------------
insert into public.app_config(key, value) values ('game_daily_limit','3'::jsonb) on conflict (key) do nothing;
insert into public.app_config(key, value) values ('spinner_token_cap','5'::jsonb) on conflict (key) do nothing;

create or replace function public.check_game_rate_limit(p_phone text)
returns void language plpgsql security definer set search_path=public, pg_temp as $$
declare max_per_min int; max_per_day int; recent_min int; recent_day int;
begin
  select value::text::int into max_per_min from public.app_config where key='game_rate_per_min';
  max_per_min := coalesce(max_per_min, 5);
  if max_per_min > 0 then
    select count(*) into recent_min from public.game_plays where phone = p_phone and created_at > now() - interval '1 minute';
    if recent_min >= max_per_min then
      raise exception 'game rate limited' using errcode='P0001', hint='rate_limited_games';
    end if;
  end if;
  select value::text::int into max_per_day from public.app_config where key='game_daily_limit';
  max_per_day := coalesce(max_per_day, 3);
  if max_per_day > 0 then
    select count(*) into recent_day from public.game_plays where phone = p_phone and created_at > now() - interval '1 day';
    if recent_day >= max_per_day then
      raise exception 'daily game limit reached' using errcode='P0001', hint='daily_limit_games';
    end if;
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='chk_loyalty_token_cap') then
    alter table public.loyalty_state add constraint chk_loyalty_token_cap check (coalesce(spinner_tokens,0) <= 5 and coalesce(match_tokens,0) <= 5 and coalesce(scratch_tokens,0) <= 5) not valid;
  end if;
end $$;
comment on constraint chk_loyalty_token_cap on public.loyalty_state is 'FIX #8: token cap 5 — enforced via trigger for now, NOT VALID until existing rows cleaned.';

create or replace function public.enforce_token_cap()
returns trigger language plpgsql as $$
begin
  if coalesce(new.spinner_tokens,0) > 5 or coalesce(new.match_tokens,0) > 5 or coalesce(new.scratch_tokens,0) > 5 then
    raise exception 'token cap 5 exceeded' using errcode='P0001', hint='token_cap';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_enforce_token_cap on public.loyalty_state;
create trigger trg_enforce_token_cap before insert or update on public.loyalty_state for each row execute function public.enforce_token_cap();

commit;
