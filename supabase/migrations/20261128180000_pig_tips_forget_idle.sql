-- Anonymous users (the app's random IDs) 30 days without tips are deleted,
-- and with each one its sessions (Supabase Auth keeps there the IP address
-- each session last came from) and its counters. "30 days without tips":
-- no tip or report counted on a UTC day after today - 30, the counters the
-- daily clean-up keeps; and the user made on a UTC day 30 or more days
-- before today. Someone who comes back after that finds tips off (the app
-- turns them off when its session is refused). Only pg_cron calls it (the
-- next migration), never a request. Can run again without changing
-- anything; returns how many users went.
create or replace function public.tips_forget_idle(today date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  gone integer;
begin
  delete from auth.users u
    where u.is_anonymous
      and u.created_at < (today - 29)::timestamp at time zone 'utc'
      and not exists (
        select from public.tip_usage t
          where t.user_id = u.id and t.day > today - 30
      );
  get diagnostics gone = row_count;
  return gone;
end;
$$;

-- No API role may call it, the service role included: only the job.
revoke all on function public.tips_forget_idle(date)
  from public, anon, authenticated, service_role;
