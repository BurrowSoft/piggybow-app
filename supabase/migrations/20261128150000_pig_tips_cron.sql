-- The daily clean-up, whatever the traffic: pg_cron runs tips_clean_up
-- every day at 03:17 (pg_cron's time, UTC unless set otherwise), with that
-- day's UTC date: never the database's time zone. Can run again without
-- changing anything: the job is unscheduled by name, then scheduled again,
-- so there's only ever one, whatever the installed pg_cron does with a
-- repeated name. The deploy checks it (supabase/checks/after-migrations.sql).
-- Supabase's own form; the platform grants the cron schema to postgres
-- with the extension.
create extension if not exists pg_cron with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname = 'pig-tips-clean-up';
select cron.schedule(
  'pig-tips-clean-up',
  '17 3 * * *',
  $$select public.tips_clean_up((now() at time zone 'utc')::date)$$
);
