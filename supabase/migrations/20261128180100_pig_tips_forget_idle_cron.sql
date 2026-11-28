-- The idle anonymous users' deletion (tips_forget_idle), daily at 03:47
-- (pg_cron's time, UTC unless set otherwise) with that day's UTC date: its
-- own job, half an hour after the clean-up's, so a failure of one never
-- stops the other. Unscheduled by name, then scheduled again: only ever
-- one. The deploy checks it, and that the function may delete Auth users
-- (supabase/checks/after-migrations.sql).
select cron.unschedule(jobid) from cron.job where jobname = 'pig-tips-forget-idle';
select cron.schedule(
  'pig-tips-forget-idle',
  '47 3 * * *',
  $$select public.tips_forget_idle((now() at time zone 'utc')::date)$$
);
