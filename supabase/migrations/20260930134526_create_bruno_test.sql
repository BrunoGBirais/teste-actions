-- Throwaway table to verify the deploy pipeline applies migrations.
create table if not exists public.bruno_test (
  id bigint generated always as identity primary key,
  name text not null,
  created_at timestamptz not null default now()
);

-- Tables in public are exposed through the Supabase API; with RLS on and no
-- policies, only the service role and direct DB connections can access it.
alter table public.bruno_test enable row level security;
