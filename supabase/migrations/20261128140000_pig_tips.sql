-- Pig tips, the server side. The server keeps nothing but
-- counters, its own settings and reported tips: no request and no tip that
-- was sent is stored. RLS is on with no policies, so no client reads or
-- writes these tables; only the pig-tip function does, as the service role.
-- Every statement can run again without changing anything. Days are UTC
-- days, whatever the database's time zone.

-- The switches, changed with one SQL update and no build or deploy.
create table if not exists public.tip_settings (
  id smallint primary key default 1 check (id = 1),
  -- The kill switch: off, every request gets no tip (the app's own tip).
  enabled boolean not null default false,
  -- Sonnet 5.5; Haiku 5.5 is the cheaper fallback, one update away.
  model text not null default 'claude-sonnet-5-5'
    check (model in ('claude-haiku-5-5', 'claude-sonnet-5-5')),
  effort text not null default 'low'
    check (effort in ('low', 'medium', 'high')),
  -- Tips a UTC day across everyone: bounds the cost.
  daily_cap integer not null default 300
    check (daily_cap between 0 and 100000),
  -- Tips a UTC day for one person (one anonymous id).
  per_person_daily integer not null default 1
    check (per_person_daily between 0 and 100),
  -- Reports kept a UTC day, across everyone and for one person: they bound
  -- what anyone can make the server store.
  report_daily_cap integer not null default 200
    check (report_daily_cap between 0 and 100000),
  reports_per_person_daily integer not null default 5
    check (reports_per_person_daily between 0 and 100),
  -- The one region tips are made in, as the function's runtime reports it
  -- (SB_REGION); a call run anywhere else gets no tip. Null: anywhere.
  -- Prod names its own with one update.
  region text check (region is null or region ~ '^[a-z0-9-]{1,40}$'),
  updated_at timestamptz not null default now()
);
insert into public.tip_settings (id) values (1) on conflict (id) do nothing;

-- How many tips and reports each person had on a day. Gone with the person
-- (turning tips off deletes the anonymous user), and after 30 days.
create table if not exists public.tip_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  reports integer not null default 0 check (reports >= 0),
  primary key (user_id, day)
);

-- How many tips and reports everyone had on a day, for the daily caps.
create table if not exists public.tip_day (
  day date primary key,
  count integer not null default 0 check (count >= 0),
  reports integer not null default 0 check (reports >= 0)
);

-- "Report this tip": the tip's text (the model's words, never the person's
-- data, and only a tip this server signed) and a reason, kept 90 days to
-- improve the filter. No one's id.
create table if not exists public.tip_reports (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  model text not null,
  reason text not null
    check (reason in ('unhelpful', 'wrong', 'upsetting', 'advice', 'other')),
  tip text not null check (char_length(tip) between 1 and 400)
);

alter table public.tip_settings enable row level security;
alter table public.tip_usage enable row level security;
alter table public.tip_day enable row level security;
alter table public.tip_reports enable row level security;

revoke all on public.tip_settings, public.tip_usage, public.tip_day,
  public.tip_reports from anon, authenticated;

-- Counters after 30 days, reports after 90, by UTC days. pg_cron runs it
-- daily (the next migration), and so does each day's first tip or report.
create or replace function public.tips_clean_up(today date)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.tip_usage where day < today - 30;
  delete from public.tip_day where day < today - 30;
  delete from public.tip_reports
    where created_at < (today - 90)::timestamp at time zone 'utc';
$$;

-- A UTC day's row, made by its first tip or report request, which cleans
-- up: tips on or off.
create or replace function public.tips_new_day(today date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_day date;
begin
  insert into public.tip_day (day) values (today)
    on conflict (day) do nothing
    returning day into new_day;
  if new_day is not null then
    perform public.tips_clean_up(today);
  end if;
end;
$$;

-- One tip for [uid] on [today] (UTC): 'off' when switched off, 'cap' when
-- everyone's tips for the day are used, 'used' when this person's are,
-- else 'ok', counted. One transaction, with the day's row locked, so two
-- requests at once can't both pass a cap.
create or replace function public.take_tip(uid uuid, today date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.tip_settings;
  total integer;
  used integer;
begin
  perform public.tips_new_day(today);

  select * into s from public.tip_settings where id = 1;
  if not found or not s.enabled then
    return 'off';
  end if;

  select count into total from public.tip_day where day = today for update;
  if total >= s.daily_cap then
    return 'cap';
  end if;

  select count into used from public.tip_usage
    where user_id = uid and day = today for update;
  if coalesce(used, 0) >= s.per_person_daily then
    return 'used';
  end if;

  insert into public.tip_usage (user_id, day, count) values (uid, today, 1)
    on conflict (user_id, day)
    do update set count = public.tip_usage.count + 1;
  update public.tip_day set count = count + 1 where day = today;
  return 'ok';
end;
$$;

-- One report from [uid] on [today] (UTC), counted and kept in one
-- transaction: 'cap' when everyone's reports for the day are kept, 'used'
-- when this person's are, else 'ok' and the report is kept. Tips on or off:
-- a report of a tip shown earlier still comes in. The function has checked
-- the tip's signature; the report keeps no one's id.
create or replace function public.file_report(
  uid uuid, today date, tip text, reason text, model text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.tip_settings;
  total integer;
  used integer;
begin
  perform public.tips_new_day(today);

  select * into s from public.tip_settings where id = 1;
  if not found then
    return 'cap';
  end if;

  select reports into total from public.tip_day where day = today for update;
  if total >= s.report_daily_cap then
    return 'cap';
  end if;

  select reports into used from public.tip_usage
    where user_id = uid and day = today for update;
  if coalesce(used, 0) >= s.reports_per_person_daily then
    return 'used';
  end if;

  insert into public.tip_usage (user_id, day, reports) values (uid, today, 1)
    on conflict (user_id, day)
    do update set reports = public.tip_usage.reports + 1;
  update public.tip_day set reports = reports + 1 where day = today;
  insert into public.tip_reports (model, reason, tip)
    values (file_report.model, file_report.reason, file_report.tip);
  return 'ok';
end;
$$;

revoke all on function public.tips_clean_up(date) from public, anon, authenticated;
revoke all on function public.tips_new_day(date) from public, anon, authenticated;
revoke all on function public.take_tip(uuid, date) from public, anon, authenticated;
revoke all on function public.file_report(uuid, date, text, text, text)
  from public, anon, authenticated;
grant execute on function public.tips_clean_up(date) to service_role;
grant execute on function public.take_tip(uuid, date) to service_role;
grant execute on function public.file_report(uuid, date, text, text, text) to service_role;
