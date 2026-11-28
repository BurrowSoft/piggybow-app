-- What the migrations need of a Supabase database, for CI's bare Postgres
-- only: the auth.users table the counters point at (with its creation time
-- and anonymous flag, as Supabase Auth keeps them), the sessions that go
-- with a user (each keeps the IP address it last came from), the API's three
-- roles, and Supabase's default grants to them on what's made in public (so
-- the migrations' revokes are really tested).
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  created_at timestamptz not null default now(),
  is_anonymous boolean not null default false
);
create table if not exists auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  ip inet
);

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
