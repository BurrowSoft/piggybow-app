-- Migration 001 on a bare Postgres (supabase/tests/stubs.sql first, then
-- the migration twice): the seed, what the API's roles can't touch, the
-- tips' and the reports' caps, and the clean-up's edges. CI's "server SQL"
-- job runs it; any failed assert stops the job.
\set ON_ERROR_STOP on
-- A zone far from UTC: the days must still be UTC days.
set timezone = 'Asia/Bangkok';

-- The seed: one settings row, everything off, after two runs.
do $$
begin
  assert (select count(*) from public.tip_settings) = 1, 'one settings row';
  assert (
    select not enabled and model = 'claude-sonnet-5-5' and effort = 'low'
      and daily_cap = 300 and per_person_daily = 1 and region is null
      and report_daily_cap = 200 and reports_per_person_daily = 5
    from public.tip_settings
  ), 'the seeded settings';
end $$;

-- Nothing for the API's roles: RLS on, no policies, no grants, no execute.
do $$
declare
  t text;
begin
  foreach t in array array['tip_settings', 'tip_usage', 'tip_day', 'tip_reports'] loop
    assert (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), t || ': RLS on';
    assert not exists (select from pg_policies where schemaname = 'public' and tablename = t), t || ': no policies';
    assert not has_table_privilege('anon', 'public.' || t, 'select, insert, update, delete'), t || ': nothing for anon';
    assert not has_table_privilege('authenticated', 'public.' || t, 'select, insert, update, delete'),
      t || ': nothing for authenticated';
  end loop;
  assert not has_function_privilege('anon', 'public.take_tip(uuid, date)', 'execute');
  assert not has_function_privilege('authenticated', 'public.take_tip(uuid, date)', 'execute');
  assert not has_function_privilege('anon', 'public.file_report(uuid, date, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.file_report(uuid, date, text, text, text)', 'execute');
  assert not has_function_privilege('anon', 'public.tips_clean_up(date)', 'execute');
  assert not has_function_privilege('authenticated', 'public.tips_new_day(date)', 'execute');
  assert has_function_privilege('service_role', 'public.take_tip(uuid, date)', 'execute');
  assert has_function_privilege('service_role', 'public.file_report(uuid, date, text, text, text)', 'execute');
end $$;

-- take_tip: off by default; then one a person a day, and the day's cap.
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  c uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (a), (b), (c);
  assert public.take_tip(a, '2026-12-01') = 'off', 'off by default';
  update public.tip_settings set enabled = true, daily_cap = 2 where id = 1;
  assert public.take_tip(a, '2026-12-01') = 'ok';
  assert public.take_tip(a, '2026-12-01') = 'used', 'one a person a day';
  assert public.take_tip(b, '2026-12-01') = 'ok';
  assert public.take_tip(c, '2026-12-01') = 'cap', 'the day''s cap';
  assert public.take_tip(a, '2026-12-02') = 'ok', 'a new day';
  assert (select count from public.tip_day where day = '2026-12-01') = 2;
  assert (select count from public.tip_usage where user_id = a and day = '2026-12-01') = 1;
end $$;

-- file_report: kept within the caps, tips on or off; never anyone's id.
do $$
declare
  d uuid := gen_random_uuid();
  e uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (d), (e);
  update public.tip_settings
    set enabled = false, reports_per_person_daily = 2, report_daily_cap = 3
    where id = 1;
  assert public.file_report(d, '2026-12-03', 'A tip.', 'unhelpful', 'claude-sonnet-5-5') = 'ok',
    'tips off: a report still comes in';
  assert public.file_report(d, '2026-12-03', 'A tip.', 'wrong', 'claude-sonnet-5-5') = 'ok';
  assert public.file_report(d, '2026-12-03', 'A tip.', 'other', 'claude-sonnet-5-5') = 'used', 'per person a day';
  assert public.file_report(e, '2026-12-03', 'Another.', 'advice', 'claude-haiku-5-5') = 'ok';
  assert public.file_report(e, '2026-12-03', 'Another.', 'advice', 'claude-haiku-5-5') = 'cap', 'the day''s cap';
  assert (select count(*) from public.tip_reports) = 3, 'three kept';
  assert (select reports from public.tip_day where day = '2026-12-03') = 3;
  assert (select reports from public.tip_usage where user_id = d and day = '2026-12-03') = 2;
  assert not exists (
    select from information_schema.columns
    where table_schema = 'public' and table_name = 'tip_reports'
      and column_name not in ('id', 'created_at', 'model', 'reason', 'tip')
  ), 'a report keeps the tip, its model and a reason: no one''s id';
end $$;

-- A reason outside the list isn't kept, and nothing is counted for it.
do $$
declare
  f uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (f);
  begin
    perform public.file_report(f, '2026-12-04', 'A tip.', 'boring', 'claude-sonnet-5-5');
    raise exception 'a reason outside the list was kept';
  exception when check_violation then
    null;
  end;
  assert not exists (select from public.tip_usage where user_id = f), 'nothing counted';
end $$;

-- tips_clean_up: counters older than 30 days and reports older than 90 go,
-- by UTC days; the edges stay.
do $$
declare
  u uuid := gen_random_uuid();
  today date := '2026-12-10';
begin
  insert into auth.users (id) values (u);
  insert into public.tip_day (day, count) values (today - 31, 1), (today - 30, 1);
  insert into public.tip_usage (user_id, day, count) values (u, today - 31, 1), (u, today - 30, 1);
  insert into public.tip_reports (created_at, model, reason, tip) values
    ((today - 90)::timestamp at time zone 'utc' - interval '1 second', 'claude-sonnet-5-5', 'other', 'old'),
    ((today - 90)::timestamp at time zone 'utc', 'claude-sonnet-5-5', 'other', 'kept');
  perform public.tips_clean_up(today);
  assert not exists (select from public.tip_day where day = today - 31), 'a day 31 days back goes';
  assert exists (select from public.tip_day where day = today - 30), 'a day 30 days back stays';
  assert not exists (select from public.tip_usage where user_id = u and day = today - 31);
  assert exists (select from public.tip_usage where user_id = u and day = today - 30);
  assert not exists (select from public.tip_reports where tip = 'old'), 'a report past 90 days goes';
  assert exists (select from public.tip_reports where tip = 'kept'), 'one at 90 days stays';
end $$;

-- The day's first request cleans up, even with tips off.
do $$
declare
  u uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (u);
  update public.tip_settings set enabled = false where id = 1;
  insert into public.tip_day (day, count) values ('2026-10-01', 5);
  assert public.take_tip(u, '2027-01-15') = 'off';
  assert not exists (select from public.tip_day where day = '2026-10-01'),
    'the first request of a new day cleans up, tips off too';
end $$;

-- service_role, as the function uses it: SELECT on tip_settings and nothing
-- else, even where the project grants new tables to the API roles (as these
-- stubs do) or doesn't (as Piggybow's projects don't).
do $$
declare
  t text;
begin
  assert has_table_privilege('service_role', 'public.tip_settings', 'select'), 'service_role reads tip_settings';
  assert not has_table_privilege('service_role', 'public.tip_settings', 'insert, update, delete'),
    'service_role can''t change tip_settings';
  foreach t in array array['tip_usage', 'tip_day', 'tip_reports'] loop
    assert not has_table_privilege('service_role', 'public.' || t, 'select, insert, update, delete'),
      t || ': nothing for service_role';
  end loop;
end $$;

-- A forgotten user's counters go with them.
do $$
declare
  u uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (u);
  update public.tip_settings set enabled = true, daily_cap = 300 where id = 1;
  assert public.take_tip(u, '2027-01-15') = 'ok';
  delete from auth.users where id = u;
  assert not exists (select from public.tip_usage where user_id = u), 'gone with the user';
end $$;

\echo 'pig tips SQL: all asserts passed'
