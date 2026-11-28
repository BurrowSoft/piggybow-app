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
end $$;
