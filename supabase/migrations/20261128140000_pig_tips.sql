-- Pig tips, the server side. The server keeps nothing but
-- counters, its own settings and reported tips: no request and no tip that
-- was sent is stored. RLS is on with no policies, so no client reads or
-- writes these tables; only the pig-tip function does, as the service role.
-- Every statement can run again without changing anything.

-- The switches, changed with one SQL update and no build or deploy.
create table if not exists public.tip_settings (
  id smallint primary key default 1 check (id = 1),
  -- The kill switch: off, every request gets no tip (the app's own tip).
  enabled boolean not null default false,
  model text not null default 'claude-haiku-5-5'
    check (model in ('claude-haiku-5-5', 'claude-sonnet-5-5')),
  effort text not null default 'low'
    check (effort in ('low', 'medium', 'high')),
  -- Tips a UTC day across everyone: bounds the cost.
  daily_cap integer not null default 300
    check (daily_cap between 0 and 100000),
  -- Tips a UTC day for one person (one anonymous id).
  per_person_daily integer not null default 1
    check (per_person_daily between 0 and 100),
  updated_at timestamptz not null default now()
);
insert into public.tip_settings (id) values (1) on conflict (id) do nothing;

-- How many tips each person had on a day. Gone with the person (turning
-- tips off deletes the anonymous user), and after 30 days.
create table if not exists public.tip_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

-- How many tips everyone had on a day, for the daily cap.
create table if not exists public.tip_day (
  day date primary key,
  count integer not null default 0 check (count >= 0)
);

-- "Report this tip": the tip's text (the model's words, never the person's
-- data) and a reason, kept 90 days to improve the filter.
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

-- Counters after 30 days, reports after 90. take_tip calls it with the
-- first request of a day; nothing else is scheduled.
create or replace function public.tips_clean_up(today date)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.tip_usage where day < today - 30;
  delete from public.tip_day where day < today - 30;
  delete from public.tip_reports where created_at < (today - 90)::timestamptz;
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
  new_day date;
  total integer;
  used integer;
begin
  select * into s from public.tip_settings where id = 1;
  if not found or not s.enabled then
    return 'off';
  end if;

  insert into public.tip_day (day, count) values (today, 0)
    on conflict (day) do nothing
    returning day into new_day;
  if new_day is not null then
    perform public.tips_clean_up(today);
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

revoke all on function public.tips_clean_up(date) from public, anon, authenticated;
revoke all on function public.take_tip(uuid, date) from public, anon, authenticated;
grant execute on function public.tips_clean_up(date) to service_role;
grant execute on function public.take_tip(uuid, date) to service_role;
