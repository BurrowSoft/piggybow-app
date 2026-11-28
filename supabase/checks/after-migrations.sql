-- After the deploy's migrations, which run twice to prove they can: one
-- settings row, and the clean-up scheduled exactly once. Any failure fails
-- the deploy.
do $$
begin
  if (select count(*) from public.tip_settings) <> 1 then
    raise exception 'tip_settings should have exactly one row';
  end if;
  if (select count(*) from cron.job where jobname = 'pig-tips-clean-up') <> 1 then
    raise exception 'pig-tips-clean-up should be scheduled exactly once';
  end if;
end $$;
