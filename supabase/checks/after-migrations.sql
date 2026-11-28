-- After the deploy's migrations, which run twice to prove they can: one
-- settings row, the clean-up and the idle users' deletion each scheduled
-- exactly once, and that deletion able to do its work. Any failure fails
-- the deploy.
do $$
declare
  owner text := (
    select proowner::regrole::text from pg_proc
      where oid = 'public.tips_forget_idle(date)'::regprocedure
  );
begin
  if (select count(*) from public.tip_settings) <> 1 then
    raise exception 'tip_settings should have exactly one row';
  end if;
  -- The API roles on the tables, whatever the project's automatic grants:
  -- service_role reads tip_settings and nothing else; anon and authenticated
  -- have nothing.
  if not has_schema_privilege('service_role', 'public', 'usage') then
    raise exception 'service_role can''t use the public schema';
  end if;
  if not has_table_privilege('service_role', 'public.tip_settings', 'select') then
    raise exception 'service_role can''t read tip_settings';
  end if;
  if not has_function_privilege('service_role', 'public.take_tip(uuid, date)', 'execute')
     or not has_function_privilege('service_role', 'public.file_report(uuid, date, text, text, text)', 'execute') then
    raise exception 'service_role can''t call take_tip or file_report';
  end if;
  if has_table_privilege('service_role', 'public.tip_settings', 'insert, update, delete') then
    raise exception 'service_role can change tip_settings';
  end if;
  if exists (
    select from unnest(array['public.tip_usage', 'public.tip_day', 'public.tip_reports']) t
      where has_table_privilege('service_role', t, 'select, insert, update, delete')
  ) then
    raise exception 'service_role has a privilege on a pig tips table besides reading the settings';
  end if;
  if exists (
    select from unnest(array['public.tip_settings', 'public.tip_usage', 'public.tip_day', 'public.tip_reports']) t,
      unnest(array['anon', 'authenticated']) r
      where has_table_privilege(r, t, 'select, insert, update, delete')
  ) then
    raise exception 'anon or authenticated has a privilege on a pig tips table';
  end if;
  if (select count(*) from cron.job where jobname = 'pig-tips-clean-up') <> 1 then
    raise exception 'pig-tips-clean-up should be scheduled exactly once';
  end if;
  if (select count(*) from cron.job where jobname = 'pig-tips-forget-idle') <> 1 then
    raise exception 'pig-tips-forget-idle should be scheduled exactly once';
  end if;
  -- tips_forget_idle runs as its owner: it must be allowed to delete Auth
  -- users, row security included, or idle IDs would stay (then an admin
  -- deleteUser job takes over).
  if not has_table_privilege(owner, 'auth.users', 'delete') then
    raise exception 'tips_forget_idle''s owner (%) can''t delete from auth.users', owner;
  end if;
  if (select relrowsecurity from pg_class where oid = 'auth.users'::regclass)
     and not (select rolbypassrls or rolsuper from pg_roles where oid = owner::regrole) then
    raise exception 'auth.users has row security that tips_forget_idle''s owner (%) doesn''t bypass', owner;
  end if;
  -- And the job runs as a role that may call it.
  if not has_function_privilege(
    (select username from cron.job where jobname = 'pig-tips-forget-idle'),
    'public.tips_forget_idle(date)', 'execute'
  ) then
    raise exception 'the pig-tips-forget-idle job can''t call tips_forget_idle';
  end if;
  -- It runs, once, at the deploy: a number and no error (it deletes only
  -- what the daily job would).
  if public.tips_forget_idle((now() at time zone 'utc')::date) is null then
    raise exception 'tips_forget_idle returned no count';
  end if;
end $$;
