-- 0045_schedule_purge_cron.sql — schedules purge_expired_vouchers every 5 min via pg_cron
-- Depends on 0039 purge_expired_vouchers() and pg_cron extension
begin;
create extension if not exists pg_cron with schema extensions;
select cron.schedule('purge_expired_vouchers_5m', '*/5 * * * *', $$select public.purge_expired_vouchers();$$)
where not exists (select 1 from cron.job where jobname='purge_expired_vouchers_5m');
commit;
