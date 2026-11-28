-- The function's counting works as it calls it, as service_role: take_tip and
-- file_report for a made-up user, each in a block that is always rolled back,
-- so nothing is kept. "off", or the made-up user's missing row (23503), means
-- the call reached the tables; a permission error fails the deploy.
do $$
declare
  nobody constant uuid := '00000000-0000-4000-8000-000000000000';
  today constant date := (now() at time zone 'utc')::date;
begin
  begin
    set local role service_role;
    perform public.take_tip(nobody, today);
    raise exception 'pig tips deploy check: rolled back' using errcode = 'P0001';
  exception
    when foreign_key_violation then null;
    when raise_exception then
      if sqlerrm <> 'pig tips deploy check: rolled back' then raise; end if;
  end;
  begin
    set local role service_role;
    perform public.file_report(nobody, today, 'A deploy check.', 'other', 'claude-sonnet-5-5');
    raise exception 'pig tips deploy check: rolled back' using errcode = 'P0001';
  exception
    when foreign_key_violation then null;
    when raise_exception then
      if sqlerrm <> 'pig tips deploy check: rolled back' then raise; end if;
  end;
end $$;
