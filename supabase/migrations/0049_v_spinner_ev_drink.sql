begin;
-- 0049: v_spinner_ev include rare drinkVoucher (5% when enabled) in EV
create or replace view public.v_spinner_ev as
 with w as (select public.get_spinner_weights() as j)
 select
   (j->>'points5')::int as w_points5,
   (j->>'points10')::int as w_points10,
   (j->>'toppingVoucher')::int as w_topping,
   (j->>'doubleNext')::int as w_double,
   coalesce((j->>'drinkVoucher')::int,0) as w_drink,
   (j->>'nothing')::int as w_nothing,
   ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int) as total,
   case when ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int) > 0 then
     round(
       ((j->>'points5')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 0.40 +
        (j->>'points10')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 0.80 +
        (j->>'toppingVoucher')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 8.00 +
        coalesce((j->>'drinkVoucher')::numeric,0) / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 18.00 +
        (j->>'doubleNext')::numeric / ((j->>'points5')::int + (j->>'points10')::int + (j->>'toppingVoucher')::int + coalesce((j->>'drinkVoucher')::int,0) + (j->>'doubleNext')::int + (j->>'nothing')::int)::numeric * 0.60)::numeric,2)
   else 0 end as ev_cogs_egp,
   round(
     ((j->>'points5')::numeric/100*0.40 +
      (j->>'points10')::numeric/100*0.80 +
      (j->>'toppingVoucher')::numeric/100*8.00 +
      coalesce((j->>'drinkVoucher')::numeric,0)/100*18.00 +
      (j->>'doubleNext')::numeric/100*0.60)::numeric,2) as ev_cogs_egp_legacy_100
 from w;
comment on view public.v_spinner_ev is '0049: includes rare drinkVoucher 18 COGS in EV.';
commit;
