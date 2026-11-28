-- What migration 001 needs of a Supabase database, for CI's bare Postgres
-- only: the auth.users table its counters point at, the API's three roles,
-- and Supabase's default grants to them on what's made in public (so the
-- migration's revokes are really tested).
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);

do $$
begin
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
