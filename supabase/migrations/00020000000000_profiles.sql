-- User profiles, 1:1 with auth.users.
-- The row is created by the app during username setup (not a signup trigger),
-- because the username is chosen interactively and must satisfy the check below.
create table public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  username     text unique not null check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text,
  avatar_url   text,
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- RLS policies gate rows; these grants gate the table itself.
grant select, insert, update on public.profiles to authenticated;

-- Beli-style public profiles: any signed-in user can view anyone.
create policy "profiles_select" on public.profiles
  for select to authenticated using (true);

create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid());

create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid());
