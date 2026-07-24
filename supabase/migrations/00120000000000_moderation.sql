-- UGC moderation (App Store Guideline 1.2): report content/users, block users.
-- Blocked users' content is filtered server-side in the social RPCs.

create table public.reports (
  id               bigint generated always as identity primary key,
  reporter         uuid   not null default auth.uid() references public.profiles on delete cascade,
  reported_user    uuid   references public.profiles on delete cascade,
  review_course_id bigint,  -- set when reporting a review (author + course identifies it)
  reason           text   not null check (char_length(reason) between 1 and 500),
  created_at       timestamptz not null default now()
);

alter table public.reports enable row level security;

-- Write-only for users; reports are read via the dashboard/service role.
create policy "reports_insert_own" on public.reports
  for insert to authenticated with check (reporter = auth.uid());

grant insert on public.reports to authenticated;

create table public.blocked_users (
  blocker    uuid not null default auth.uid() references public.profiles on delete cascade,
  blocked    uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

alter table public.blocked_users enable row level security;

create policy "blocked_select_own" on public.blocked_users
  for select to authenticated using (blocker = auth.uid());
create policy "blocked_insert_own" on public.blocked_users
  for insert to authenticated with check (blocker = auth.uid());
create policy "blocked_delete_own" on public.blocked_users
  for delete to authenticated using (blocker = auth.uid());

grant select, insert, delete on public.blocked_users to authenticated;

-- Recreate the social read RPCs with blocked-author filtering.

create or replace function public.activity_feed()
returns table (
  kind text,
  actor_id uuid,
  username text,
  course_id bigint,
  course_name text,
  city text,
  state text,
  score numeric,
  bucket public.bucket,
  created_at timestamptz
)
language sql stable
set search_path = ''
as $$
  with circle as (
    select auth.uid() as uid
    union
    select followee_id from public.follows where follower_id = auth.uid()
  ),
  visible as (
    select uid from circle
    where uid not in (select blocked from public.blocked_users where blocker = auth.uid())
  )
  (
    select 'ranked', s.user_id, p.username, s.course_id, c.name, c.city, c.state,
           s.score, s.bucket, s.created_at
    from public.user_course_scores s
    join public.profiles p on p.id = s.user_id
    join public.courses c on c.id = s.course_id
    where s.user_id in (select uid from visible)
  )
  union all
  (
    select 'want', w.user_id, p.username, w.course_id, c.name, c.city, c.state,
           null, null, w.created_at
    from public.want_to_play w
    join public.profiles p on p.id = w.user_id
    join public.courses c on c.id = w.course_id
    where w.user_id in (select uid from visible)
  )
  order by created_at desc
  limit 60;
$$;

create or replace function public.leaderboard()
returns table (
  rank bigint,
  id uuid,
  username text,
  display_name text,
  played bigint,
  is_me boolean
)
language sql stable
set search_path = ''
as $$
  select rank() over (order by count(*) desc) as rank,
         p.id, p.username, p.display_name, count(*) as played,
         p.id = auth.uid() as is_me
  from public.user_course_rankings r
  join public.profiles p on p.id = r.user_id
  where p.id not in (select blocked from public.blocked_users where blocker = auth.uid())
  group by p.id, p.username, p.display_name
  order by played desc
  limit 100;
$$;

create or replace function public.course_reviews(p_course_id bigint)
returns table (
  id bigint, user_id uuid, username text, body text,
  created_at timestamptz, is_mine boolean
)
language sql stable
set search_path = ''
as $$
  select r.id, r.user_id, p.username, r.body, r.created_at,
         r.user_id = auth.uid()
  from public.reviews r
  join public.profiles p on p.id = r.user_id
  where r.course_id = p_course_id
    and r.user_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by (r.user_id = auth.uid()) desc, r.created_at desc;
$$;

create or replace function public.search_profiles(p_query text)
returns table (id uuid, username text, display_name text, is_following boolean)
language sql stable
set search_path = ''
as $$
  select p.id, p.username, p.display_name,
         exists (select 1 from public.follows f
                  where f.follower_id = auth.uid() and f.followee_id = p.id)
  from public.profiles p
  where p.id <> auth.uid()
    and p.id not in (select blocked from public.blocked_users where blocker = auth.uid())
    and (p.username ilike '%' || p_query || '%'
         or p.display_name ilike '%' || p_query || '%')
  order by p.username
  limit 25;
$$;
