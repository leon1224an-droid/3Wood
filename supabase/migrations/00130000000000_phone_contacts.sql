-- Phone-number linking + find-friends-from-contacts.
--
-- Numbers live in their own owner-only table (NOT on public.profiles, which
-- any signed-in user can select) and are only ever compared inside the
-- security-definer RPC below — no way to browse other users' numbers.

create table public.profile_phones (
  user_id    uuid primary key references public.profiles on delete cascade,
  -- E.164, normalized client-side ("+14085551234").
  phone      text unique not null check (phone ~ '^\+[0-9]{8,15}$'),
  created_at timestamptz not null default now()
);

alter table public.profile_phones enable row level security;

create policy "phones_select_own" on public.profile_phones
  for select to authenticated using (user_id = auth.uid());
create policy "phones_insert_own" on public.profile_phones
  for insert to authenticated with check (user_id = auth.uid());
create policy "phones_update_own" on public.profile_phones
  for update to authenticated using (user_id = auth.uid());
create policy "phones_delete_own" on public.profile_phones
  for delete to authenticated using (user_id = auth.uid());

grant select, insert, update, delete on public.profile_phones to authenticated;

-- Link (upsert) or unlink (null) the caller's number.
create or replace function public.set_my_phone(p_phone text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_phone is null then
    delete from public.profile_phones where user_id = auth.uid();
  else
    insert into public.profile_phones (user_id, phone)
    values (auth.uid(), p_phone)
    on conflict (user_id) do update set phone = excluded.phone;
  end if;
end;
$$;

-- Which of the caller's contacts are on 3Wood. Security definer so it can
-- read other users' numbers for the comparison; it only returns numbers the
-- caller already sent in (their own contacts), joined to public profile
-- fields. Blocked users are filtered like every other social RPC.
create or replace function public.match_contacts(p_phones text[])
returns table (id uuid, username text, display_name text, is_following boolean, phone text)
language sql stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name,
         exists (select 1 from public.follows f
                  where f.follower_id = auth.uid() and f.followee_id = p.id),
         ph.phone
  from public.profile_phones ph
  join public.profiles p on p.id = ph.user_id
  where ph.phone = any (p_phones)
    and p.id <> auth.uid()
    and p.id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by p.username
  limit 500;
$$;

revoke execute on function public.match_contacts(text[]) from public, anon;
grant execute on function public.match_contacts(text[]) to authenticated;
revoke execute on function public.set_my_phone(text) from public, anon;
grant execute on function public.set_my_phone(text) to authenticated;
