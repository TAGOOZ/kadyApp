-- 0013_validate_redemption.sql — reject forged [REDEEMED:...] notes
-- Validates redeemed type/cost against app_config and that caller owns sufficient points.
-- Format: [REDEEMED:type:cost] where type in (free_drink, free_snack, free_topping)
-- Maps to app_config keys: free_drink->reward_drink, free_snack->reward_snack, free_topping->reward_topping.

create or replace function public.credit_new_order()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  ls_row   public.loyalty_state;
  ls       jsonb;
  redeemed int := 0;
  redeemed_type text := null;
  cost_expected int;
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

  -- [REDEEMED:type:cost] prefix parsed from notes — validate server-side
  if new.notes is not null and new.notes like '%[REDEEMED:%' then
    -- Extract type between [REDEEMED: and next :
    select (regexp_match(new.notes, '\[REDEEMED:([^:]+):(\d+)\]'))[1] into redeemed_type;
    select coalesce(nullif(split_part(split_part(new.notes, ':',3),']',1),'')::int,0) into redeemed;
    -- Lookup expected cost from app_config (keys: reward_drink/snack/topping)
    select case redeemed_type
      when 'free_drink' then (select value::text::int from public.app_config where key='reward_drink')
      when 'free_snack' then (select value::text::int from public.app_config where key='reward_snack')
      when 'free_topping' then (select value::text::int from public.app_config where key='reward_topping')
      else null end into cost_expected;
    if cost_expected is null then
      raise exception 'invalid redeemed type %', redeemed_type;
    end if;
    if redeemed != cost_expected then
      raise exception 'redeemed cost % does not match expected % for %', redeemed, cost_expected, redeemed_type;
    end if;
    -- Check caller has enough points
    if ls_row.points < redeemed then
      raise exception 'insufficient points % < %', ls_row.points, redeemed;
    end if;
    -- Also enforce global floor for drink redemption
    if redeemed_type = 'free_drink' then
      declare min_pts int;
      begin
        select value::text::int into min_pts from public.app_config where key='redeem_min_points';
        if redeemed < coalesce(min_pts, 200) then
          raise exception 'redeemed cost % below redeem_min_points %', redeemed, min_pts;
        end if;
      end;
    end if;
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
    double_next_order = false,
    vouchers          = coalesce(ls->'vouchers', '[]'::jsonb),
    processed_orders  = (jsonb_build_array(new.id::text) || l.processed_orders)[0:99],
    updated_at        = now()
  where l.phone = ls_row.phone;

  insert into order_events(order_id, status, actor, at)
  values (new.id, 'new', 'system:loyalty', now());

  return new;
end;
$$;
