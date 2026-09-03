begin;

-- 0042: Prize COGS model + liability views (FIX #4) + weight validation (FIX #5)

-- ---------------------------------------------------------------------------
-- FIX #4: COGS table
-- ---------------------------------------------------------------------------
create table if not exists public.prize_cogs (
  prize_type text primary key check (prize_type in ('points5','points10','free_topping','free_drink','free_snack','double_next','nothing')),
  cogs_egp numeric(10,2) not null check (cogs_egp >= 0),
  retail_egp numeric(10,2) check (retail_egp >= 0),
  notes text,
  updated_at timestamptz not null default now()
);
create or replace function public.set_prize_cogs_updated_at() returns trigger language plpgsql as $$ begin new.updated_at:=now(); return new; end; $$;
drop trigger if exists trg_prize_cogs_updated_at on public.prize_cogs;
create trigger trg_prize_cogs_updated_at before update on public.prize_cogs for each row execute function public.set_prize_cogs_updated_at();

alter table public.prize_cogs enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='prize_cogs' and policyname='cogs_select_all') then
    create policy cogs_select_all on public.prize_cogs for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='prize_cogs' and policyname='cogs_admin_write') then
    create policy cogs_admin_write on public.prize_cogs for all to authenticated using (public.is_admin()) with check (public.is_admin());
  end if;
end $$;

insert into public.prize_cogs(prize_type, cogs_egp, retail_egp, notes) values
  ('points5', 0.40, 0.40, '5pts * 0.08 (8cogs/100pts topping)'),
  ('points10', 0.80, 0.80, '10pts * 0.08'),
  ('free_topping', 8.00, 12.00, 'whipped_cream/caramel avg'),
  ('free_drink', 18.00, 60.00, 'drink COGS avg, retail cap 60'),
  ('free_snack', 15.00, 30.00, 'snack COGS'),
  ('double_next', 0.60, 0.60, 'avg extra 7.5pts *0.08 — capped'),
  ('nothing', 0, 0, 'no cost')
on conflict (prize_type) do update set cogs_egp=excluded.cogs_egp, retail_egp=excluded.retail_egp, notes=excluded.notes;

-- Breakage per type
create or replace view public.v_voucher_breakage as
 select
   type,
   count(*) filter (where status='issued') as issued,
   count(*) filter (where status='redeemed') as redeemed,
   count(*) filter (where status='expired') as expired,
   count(*) as total,
   case when count(*) >0 then round(100.0*count(*) filter (where status='expired') / count(*),2) else 0 end as breakage_pct,
   case when count(*) >0 then round(100.0*count(*) filter (where status='redeemed') / count(*),2) else 0 end as redemption_pct
 from public.voucher_ledger group by type;

create or replace view public.v_reward_liability as
 select
   date_trunc('month', vl.issued_at)::date as month,
   vl.type,
   count(*) as issued,
   sum(pc.cogs_egp) as gross_cogs,
   sum(case when vl.status='redeemed' then pc.cogs_egp else 0 end) as realized_cogs,
   sum(case when vl.status='issued' then pc.cogs_egp else 0 end) as outstanding_liability
 from public.voucher_ledger vl
 join public.prize_cogs pc on pc.prize_type = case vl.type when 'free_topping' then 'free_topping' when 'free_drink' then 'free_drink' when 'free_snack' then 'free_snack' else vl.type end
 group by 1,2 order by 1 desc, 2;

create or replace view public.v_spinner_ev as
 with w as (select public.get_spinner_weights() as j)
 select
   (j->>'points5')::int as w_points5,
   (j->>'points10')::int as w_points10,
   (j->>'toppingVoucher')::int as w_topping,
   (j->>'doubleNext')::int as w_double,
   (j->>'nothing')::int as w_nothing,
   ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + (j->>'doubleNext')::int + (j->>'nothing')::int) as total,
   round(
     ((j->>'points5')::numeric/100*0.40 +
      (j->>'points10')::numeric/100*0.80 +
      (j->>'toppingVoucher')::numeric/100*8.00 +
      (j->>'doubleNext')::numeric/100*0.60)::numeric,2) as ev_cogs_egp
 from w;

-- ---------------------------------------------------------------------------
-- FIX #5: Weight validation + audit
-- ---------------------------------------------------------------------------
create or replace function public.validate_weight_json(p_key text, p_val jsonb)
returns void language plpgsql as $$
declare total int; k text; v int;
begin
  if p_key not in ('spinner_weights','scratch_weights','match_weights') then return; end if;
  if jsonb_typeof(p_val) <> 'object' then raise exception 'weights must be JSON object for %', p_key using errcode='P0001'; end if;
  total := 0;
  for k, v in select key, (value::text::int) from jsonb_each_text(p_val)
  loop
    if v < 0 or v > 100 then raise exception 'weight % for % out of range 0..100', k, p_key using errcode='P0001'; end if;
    total := total + v;
  end loop;
  if total < 95 or total > 105 then
    raise exception 'weights for % sum to % — must be 95..105 (expected ~100)', p_key, total using errcode='P0001';
  end if;
  if p_key='spinner_weights' then
    if not (p_val ? 'points5' and p_val ? 'points10' and p_val ? 'toppingVoucher' and p_val ? 'doubleNext' and p_val ? 'nothing') then
      raise exception 'spinner_weights missing required keys' using errcode='P0001';
    end if;
  end if;
end;
$$;

create or replace function public.trg_app_config_validate_weights()
returns trigger language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if new.key in ('spinner_weights','scratch_weights','match_weights') then
    perform public.validate_weight_json(new.key, new.value);
  end if;
  insert into public.staff_log(actor, action, target_phone, detail)
  values (coalesce(auth.uid()::text,'system'), 'app_config_update', null, jsonb_build_object('key', new.key, 'old', old.value, 'new', new.value));
  return new;
end;
$$;
drop trigger if exists trg_app_config_validate on public.app_config;
create trigger trg_app_config_validate before update on public.app_config for each row execute function public.trg_app_config_validate_weights();
drop trigger if exists trg_app_config_validate_ins on public.app_config;
create trigger trg_app_config_validate_ins before insert on public.app_config for each row when (new.key in ('spinner_weights','scratch_weights','match_weights')) execute function public.trg_app_config_validate_weights();

commit;
