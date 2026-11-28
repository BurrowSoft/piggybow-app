-- What service_role may do on the pig tips tables, the same on any project:
-- SELECT on tip_settings, and nothing else. The pig-tip function reads its
-- settings through the API as service_role, and reaches the other tables only
-- through take_tip and file_report (security definer, which it may execute).
-- Bypassing row security doesn't give a role privileges, and a project made
-- with "Grant API access to new tables automatically" off gives the API roles
-- nothing on new tables, so the one it needs is granted here; whatever a
-- project granted by itself is taken back first. anon and authenticated keep
-- nothing. Can run again without changing anything.
revoke all on public.tip_settings, public.tip_usage, public.tip_day,
  public.tip_reports from service_role;
grant select on public.tip_settings to service_role;
