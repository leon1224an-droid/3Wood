-- Following: one-directional, Beli-style.
create table public.follows (
  follower_id uuid not null references public.profiles on delete cascade,
  followee_id uuid not null references public.profiles on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee_idx on public.follows (followee_id);

alter table public.follows enable row level security;

create policy "follows_select" on public.follows
  for select to authenticated using (true);
create policy "follows_insert_own" on public.follows
  for insert to authenticated with check (follower_id = auth.uid());
create policy "follows_delete_own" on public.follows
  for delete to authenticated using (follower_id = auth.uid());

grant select, insert, delete on public.follows to authenticated;

-- Find people by username, with the caller's follow state baked in.
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
    and (p.username ilike '%' || p_query || '%'
         or p.display_name ilike '%' || p_query || '%')
  order by p.username
  limit 25;
$$;

-- Any user's ranked list (ratings are public), same shape as my_ranked_courses.
create or replace function public.user_ranked_courses(p_user_id uuid)
returns table (
  course_id bigint, name text, city text, state text,
  bucket public.bucket, rank_position int, score numeric
)
language sql stable
set search_path = ''
as $$
  select s.course_id, c.name, c.city, c.state, s.bucket, s.rank_position, s.score
  from public.user_course_scores s
  join public.courses c on c.id = s.course_id
  where s.user_id = p_user_id
  order by case s.bucket when 'liked' then 0 when 'fine' then 1 else 2 end,
           s.rank_position;
$$;

-- Scores for one course from the people the caller follows.
create or replace function public.friend_scores(p_course_id bigint)
returns table (user_id uuid, username text, score numeric)
language sql stable
set search_path = ''
as $$
  select s.user_id, p.username, s.score
  from public.user_course_scores s
  join public.follows f
    on f.followee_id = s.user_id and f.follower_id = auth.uid()
  join public.profiles p on p.id = s.user_id
  where s.course_id = p_course_id
  order by s.score desc;
$$;

-- Profile header numbers.
create or replace function public.profile_stats(p_user_id uuid)
returns table (played bigint, followers bigint, following bigint)
language sql stable
set search_path = ''
as $$
  select
    (select count(*) from public.user_course_rankings where user_id = p_user_id),
    (select count(*) from public.follows where followee_id = p_user_id),
    (select count(*) from public.follows where follower_id = p_user_id);
$$;
