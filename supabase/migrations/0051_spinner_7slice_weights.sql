begin;
-- 0051: update spinner_weights seed to 7-slice thorough distribution 30/25/15/10/5/15
update public.app_config set value='{"points5":30,"points10":25,"toppingVoucher":15,"doubleNext":10,"drinkVoucher":5,"nothing":15}'::jsonb where key='spinner_weights';
-- ensure prize_cogs for new drink handled (already exists)
-- also ensure v_spinner_ev will show new EV ~2.23 (30*0.4+25*0.8+15*8+10*0.6+5*18)/100 = 2.23
commit;
