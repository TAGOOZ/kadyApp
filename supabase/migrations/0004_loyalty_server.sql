-- ============================================================================
-- 0004_loyalty_server.sql — server-authoritative loyalty.
--   trg_enforce_order_rate_limit : BEFORE INSERT, enforces app_config limits
--   trg_credit_new_order         : AFTER INSERT, idempotent crediting incl.
--                                  [REDEEMED:type:cost] deduction from notes
--   apply_stamps(jsonb,n)        : canonical stamp wrap (complete+reset at 10,
--                                  every-3rd spinner token)
--   staff_apply_stamp(phone,spend): staff check-in stamping (RLS-safe)
-- ============================================================================

create or replace function public.round_half_up(n numeric)
returns int language sql immutable as $$
  select floor(n + 0.5)::int;
$$;

create or replace function public.now_utc_iso()
returns text language sql stable as $$
  select to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
$$;

-- st carries at least {stamps, completed_cards, spinner_tokens, vouchers}.
create or replace function public.apply_stamps(st jsonb, n int)
returns jsonb language plpgsql stable as $$
declare
  s jsonb := st;
begin
  if n <= 0 then return s; end if;
  for i in 1..n loop
    declare
      ns       int := coalesce((s->>'stamps')::int, 0) + 1;
      stamps   int := ns;
      cards    int := coalesce((s->>'completed_cards')::int, 0);
      tokens   int := coalesce((s->>'spinner_tokens')::int, 0);
      vouchers jsonb := coalesce(s->'vouchers', '[]'::jsonb);
    begin
      if ns >= 10 then
        cards := cards + 1;
        vouchers := vouchers || jsonb_build_array(
          jsonb_build_object('type', 'free_snack', 'at', now_utc_iso()));
        stamps := ns - 10;
      end if;
      if stamps > 0 and stamps % 3 = 0 then
        tokens := tokens + 1;
      end if;
      s := jsonb_set(s, '{stamps}', to_jsonb(stamps));
      s := jsonb_set(s, '{completed_cards}', to_jsonb(cards));
      s := jsonb_set(s, '{spinner_tokens}', to_jsonb(tokens));
      s := jsonb_set(s, '{vouchers}', vouchers);
    end;
  end loop;
  return s;
end;
$$;

-- BEFORE INSERT: reject when over the per-customer order rate limit.
create or replace function public.enforce_order_rate_limit()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  max_n int;
  win_min int;
  recent int;
begin
  select value::text::int into max_n   from app_config where key = 'rate_limit_max';
  select value::text::int into win_min from app_config where key = 'rate_limit_window_min';
  if coalesce(max_n, 5) > 0 then
    select count(*) into recent
      from orders o
     where o.phone = new.phone
       and o.created_at > now() - make_interval(mins => coalesce(win_min, 5));
    if recent >= coalesce(max_n, 5) then
      raise exception 'orders: rate limited'
        using errcode = 'P0001', hint = 'too_many_orders';
    end if;
  end if;
  return new;
end;
$$;

-- AFTER INSERT: idempotent loyalty credit (earn − redemption, stamps, tokens).
create or replace function public.credit_new_order()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  ls_row   public.loyalty_state;
  ls       jsonb;
  redeemed int := 0;
  mult     numeric := 1.0;
  dbl      boolean := false;
  earned   int;
begin
  select ls2.* into ls_row
    from loyalty_state ls2
    join customers c on c.phone = ls2.phone
   where c.google_user_id = new.google_user_id
   for update of ls2;

  if ls_row is null then return new; end if;
  if ls_row.processed_orders ? new.id::text then return new; end if;

  -- [REDEEMED:type:cost] prefix parsed from notes
  if new.notes like '[REDEEMED:%' then
    redeemed := split_part(split_part(new.notes, ':', 3), ']', 1)::int;
  end if;

  mult := coalesce(
    (select value::text::numeric from app_config where key = 'dine_in_multiplier'),
    1.0);
  if new.mode <> 'dine_in' then mult := 1.0; end if;

  dbl := ls_row.double_next_order
      or exists (select 1 from campaigns
                  where kind = 'double_points' and active
                    and (starts_at is null or starts_at <= now())
                    and (ends_at   is null or ends_at   >= now()));

  earned := public.round_half_up(
    coalesce(new.subtotal, 0)::numeric / 10.0 * mult * case when dbl then 2 else 1 end);

  ls := to_jsonb(ls_row);
  if coalesce(new.subtotal, 0) >= coalesce(
       (select value::text::int from app_config where key = 'stamp_min_spend'), 50) then
    ls := public.apply_stamps(ls, 1);
  end if;

  update loyalty_state l set
    points            = greatest(l.points + earned - redeemed, 0),
    lifetime_points   = l.lifetime_points + earned,
    stamps            = (ls->>'stamps')::int,
    completed_cards   = (ls->>'completed_cards')::int,
    spinner_tokens    = (ls->>'spinner_tokens')::int,
    double_next_order = false,               -- flag/window consumed
    vouchers          = coalesce(ls->'vouchers', '[]'::jsonb),
    processed_orders  = (jsonb_build_array(new.id::text) || l.processed_orders)[0:99],
    updated_at        = now()
  where l.phone = ls_row.phone;

  insert into order_events(order_id, status, actor, at)
  values (new.id, 'new', 'system:loyalty', now());

  return new;
end;
$$;

drop trigger if exists trg_enforce_order_rate_limit on public.orders;
create trigger trg_enforce_order_rate_limit
  before insert on public.orders
  for each row execute function public.enforce_order_rate_limit();

drop trigger if exists trg_credit_new_order on public.orders;
create trigger trg_credit_new_order
  after insert on public.orders
  for each row when (new.status = 'new')
  execute function public.credit_new_order();

-- Staff check-in / manual visit stamping (RLS-safe via security definer).
create or replace function public.staff_apply_stamp(p_phone text, p_spend int)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  ls_row public.loyalty_state;
  ls jsonb;
  min_spend int;
begin
  if not public.has_any_role(array['staff','admin']::text[]) then
    raise exception 'visits: insufficient role' using errcode = '42501';
  end if;

  select ls2.* into ls_row
    from loyalty_state ls2 where ls2.phone = p_phone for update of ls2;
  if ls_row is null then return false; end if;

  select value::text::int into min_spend from app_config where key = 'stamp_min_spend';
  if coalesce(p_spend, 0) < coalesce(min_spend, 50) then
    return false; -- recorded by caller; below qualifying threshold
  end if;

  ls := public.apply_stamps(to_jsonb(ls_row), 1);

  update loyalty_state l set
    stamps          = (ls->>'stamps')::int,
    completed_cards = (ls->>'completed_cards')::int,
    spinner_tokens  = (ls->>'spinner_tokens')::int,
    vouchers        = coalesce(ls->'vouchers', '[]'::jsonb),
    updated_at      = now()
  where l.phone = p_phone;

  insert into staff_log(actor, action, target_phone, detail)
  values (auth.uid()::text, 'checkin_stamp', p_phone,
          jsonb_build_object('spend', p_spend));
  return true;
end;
$$;