-- The daily clean-up, whatever the traffic: pg_cron runs tips_clean_up
-- every day at 03:17 (pg_cron's time, UTC unless set otherwise), with that
-- day's UTC date: never the database's time zone. Can run again without
-- changing anything: the job is unscheduled by name, then scheduled again,
-- so there's only ever one, whatever the installed pg_cron does with a
-- repeated name. The deploy checks it (supabase/checks/after-migrations.sql).
--
-- pg_cron as Supabase's install guide has it (docs/guides/cron/install),
-- without the guide's two manual grants, on purpose. Since supabase/postgres'
-- migration 20260730000000_revoke_trigger_on_cron_tables_from_postgres, the
-- platform's grant_pg_cron_access() event trigger grants postgres the cron
-- schema when the extension is created, with cron.job SELECT-only and no
-- TRIGGER on cron.job_run_details. A manual `grant all privileges on all
-- tables in schema cron to postgres` would give back what that migration
-- took away.
create extension if not exists pg_cron with schema pg_catalog;

select cron.unschedule(jobid) from cron.job where jobname = 'pig-tips-clean-up';
select cron.schedule(
  'pig-tips-clean-up',
  '17 3 * * *',
  $$select public.tips_clean_up((now() at time zone 'utc')::date)$$
);
