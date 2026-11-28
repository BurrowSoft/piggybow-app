-- tips_forget_idle on a bare Postgres (supabase/tests/stubs.sql, then the
-- migrations without pg_cron, twice): anonymous users 30 days without tips
-- go, with their sessions (and the IP address each keeps) and their
-- counters; "30 days" on both edges, for tips and for a new user; a report
-- counts as activity; a signed-up user is never touched; and no API role
-- can call it. CI's "server SQL" job runs it; any failed assert stops the job.
\set ON_ERROR_STOP on
-- A zone far from UTC: the days must still be UTC days.
set timezone = 'Asia/Bangkok';

-- Only pg_cron calls it: nothing for the API's roles, the service role too.
do $$
begin
  assert not has_function_privilege('anon', 'public.tips_forget_idle(date)', 'execute'), 'anon';
  assert not has_function_privilege('authenticated', 'public.tips_forget_idle(date)', 'execute'), 'authenticated';
  assert not has_function_privilege('service_role', 'public.tips_forget_idle(date)', 'execute'), 'service_role';
end $$;

do $$
declare
  today date := '2027-03-01';
  -- Made long ago, never a tip: goes.
  idle uuid := gen_random_uuid();
  -- A tip on today - 29: 29 days without one, stays.
  tip29 uuid := gen_random_uuid();
  -- Its last tip on today - 30: 30 days without one, goes.
  tip30 uuid := gen_random_uuid();
  -- Only a report, on today - 10: stays.
  report10 uuid := gen_random_uuid();
  -- Made at the very start of today - 29, never a tip: stays.
  new29 uuid := gen_random_uuid();
  -- Made at the very end of today - 30, never a tip: goes.
  new30 uuid := gen_random_uuid();
  -- Signed up, not anonymous, long idle: never touched.
  member uuid := gen_random_uuid();
begin
  insert into auth.users (id, created_at, is_anonymous) values
    (idle, (today - 400)::timestamp at time zone 'utc', true),
    (tip29, (today - 100)::timestamp at time zone 'utc', true),
    (tip30, (today - 100)::timestamp at time zone 'utc', true),
    (report10, (today - 100)::timestamp at time zone 'utc', true),
    (new29, (today - 29)::timestamp at time zone 'utc', true),
    (new30, ((today - 30)::timestamp + interval '23:59:59') at time zone 'utc', true),
    (member, (today - 400)::timestamp at time zone 'utc', false);
  -- Documentation addresses (RFC 5737), not anyone's.
  insert into auth.sessions (user_id, ip) values
    (idle, '203.0.113.7'), (tip29, '203.0.113.8'), (member, '203.0.113.9');
  insert into public.tip_usage (user_id, day, count) values
    (tip29, today - 29, 1), (tip30, today - 30, 1), (tip30, today - 45, 1);
  insert into public.tip_usage (user_id, day, reports) values (report10, today - 10, 1);

  assert public.tips_forget_idle(today) = 3, 'three anonymous users 30 days without tips';
  assert not exists (select from auth.users where id in (idle, tip30, new30)), 'they are gone';
  assert (select count(*) from auth.users where id in (tip29, report10, new29, member)) = 4,
    'a tip on today - 29, a report, a user made 29 days ago and a signed-up user stay';
  assert not exists (select from auth.sessions where user_id = idle), 'the session and its IP go with the user';
  assert (select count(*) from auth.sessions where user_id in (tip29, member)) = 2, 'the others'' sessions stay';
  assert not exists (select from public.tip_usage where user_id = tip30), 'the counters go with the user';
  assert (select count(*) from public.tip_usage where user_id in (tip29, report10)) = 2, 'the others'' counters stay';
  assert public.tips_forget_idle(today) = 0, 'a second run the same day deletes nothing more';
end $$;

\echo 'pig tips forget idle SQL: all asserts passed'
