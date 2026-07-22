-- The ranked "Played" list and derived 0-10 scores.
--
-- Each user's list is ordered by (bucket, rank_position): all 'liked' courses
-- outrank all 'fine', which outrank all 'disliked'. rank_position is 1-based
-- and contiguous within (user, bucket). Writes go through the RPCs below so
-- the shift + insert is atomic; scores are pure views, never stored.

create type public.bucket as enum ('liked', 'fine', 'disliked');

create table public.user_course_rankings (
  user_id       uuid          not null references public.profiles on delete cascade,
  course_id     bigint        not null references public.courses on delete cascade,
  bucket        public.bucket not null,
  rank_position int           not null check (rank_position >= 1),
  note          text,
  played_at     date,
  created_at    timestamptz   not null default now(),
  primary key (user_id, course_id)
);

create unique index rankings_order_idx
  on public.user_course_rankings (user_id, bucket, rank_position);
create index rankings_course_idx on public.user_course_rankings (course_id);

alter table public.user_course_rankings enable row level security;

-- Beli-style public ratings: anyone signed in can read; nobody writes directly
-- (no insert/update/delete policies — only the SECURITY DEFINER RPCs below).
create policy "rankings_select" on public.user_course_rankings
  for select to authenticated using (true);

grant select on public.user_course_rankings to authenticated;

-- Remove a course from the caller's list, closing the position gap.
create or replace function public.remove_ranking(p_course_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_bucket public.bucket;
  v_pos    int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  delete from public.user_course_rankings
   where user_id = v_user and course_id = p_course_id
   returning bucket, rank_position into v_bucket, v_pos;

  if v_pos is not null then
    -- Two-step offset avoids transient unique-index collisions (UPDATE order
    -- within a statement is unspecified) while staying >= 1 for the check.
    update public.user_course_rankings
       set rank_position = rank_position + 1000000
     where user_id = v_user and bucket = v_bucket and rank_position > v_pos;
    update public.user_course_rankings
       set rank_position = rank_position - 1000001
     where user_id = v_user and bucket = v_bucket and rank_position > 1000000;
  end if;
end;
$$;

-- Insert (or move) a course at p_position within p_bucket for the caller.
create or replace function public.insert_ranking(
  p_course_id bigint, p_bucket public.bucket, p_position int
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_count int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- Re-logging: drop any existing entry first (also closes its gap).
  perform public.remove_ranking(p_course_id);

  select count(*) into v_count
    from public.user_course_rankings
   where user_id = v_user and bucket = p_bucket;

  if p_position < 1 or p_position > v_count + 1 then
    raise exception 'position % out of range 1..%', p_position, v_count + 1;
  end if;

  update public.user_course_rankings
     set rank_position = rank_position + 1000000
   where user_id = v_user and bucket = p_bucket and rank_position >= p_position;
  update public.user_course_rankings
     set rank_position = rank_position - 999999
   where user_id = v_user and bucket = p_bucket and rank_position > 1000000;

  insert into public.user_course_rankings (user_id, course_id, bucket, rank_position)
  values (v_user, p_course_id, p_bucket, p_position);
end;
$$;

-- Per-user 0-10 scores: linear interpolation within bucket score ranges.
--   liked    (6.7, 10.0]   fine (3.4, 6.6]   disliked (0.0, 3.3]
--   score = hi - width * (position - 0.5) / bucket_count
-- The identical formula lives in Swift (ScoreMath) for instant local display;
-- RankingEngineTests cross-checks both against shared fixtures.
create view public.user_course_scores
with (security_invoker = on) as
select
  r.user_id, r.course_id, r.bucket, r.rank_position, r.note, r.played_at, r.created_at,
  round((
    (case r.bucket when 'liked' then 10.0 when 'fine' then 6.6 else 3.3 end)
    - (case r.bucket when 'liked' then 3.3 when 'fine' then 3.2 else 3.3 end)
      * (r.rank_position - 0.5)
      / count(*) over (partition by r.user_id, r.bucket)
  )::numeric, 1) as score
from public.user_course_rankings r;

grant select on public.user_course_scores to authenticated;

create view public.course_community_ratings
with (security_invoker = on) as
select course_id, round(avg(score), 1) as avg_score, count(*)::bigint as rating_count
from public.user_course_scores
group by course_id;

grant select on public.course_community_ratings to authenticated;

-- The caller's full ranked list, best first, with course info for display.
create or replace function public.my_ranked_courses()
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
  where s.user_id = auth.uid()
  order by case s.bucket when 'liked' then 0 when 'fine' then 1 else 2 end,
           s.rank_position;
$$;

-- Search + map RPCs now surface real community averages.
create or replace function public.search_courses(p_query text)
returns table (
  id bigint, name text, city text, state text,
  latitude double precision, longitude double precision,
  holes int, course_type text,
  avg_score numeric, rating_count bigint
)
language sql stable
set search_path = ''
as $$
  select c.id, c.name, c.city, c.state, c.latitude, c.longitude,
         c.holes, c.course_type,
         r.avg_score, coalesce(r.rating_count, 0)
  from public.courses c
  left join public.course_community_ratings r on r.course_id = c.id
  where c.name ilike '%' || p_query || '%'
     or extensions.similarity(c.name, p_query) > 0.25
     or (c.city || ', ' || c.state) ilike '%' || p_query || '%'
  order by extensions.similarity(c.name, p_query) desc, c.name
  limit 25;
$$;

create or replace function public.courses_in_region(
  min_lat double precision, min_lng double precision,
  max_lat double precision, max_lng double precision
)
returns table (
  id bigint, name text, city text, state text,
  latitude double precision, longitude double precision,
  holes int, course_type text,
  avg_score numeric, rating_count bigint
)
language sql stable
set search_path = ''
as $$
  select c.id, c.name, c.city, c.state, c.latitude, c.longitude,
         c.holes, c.course_type,
         r.avg_score, coalesce(r.rating_count, 0)
  from public.courses c
  left join public.course_community_ratings r on r.course_id = c.id
  where extensions.st_intersects(
          c.geom,
          extensions.st_makeenvelope(min_lng, min_lat, max_lng, max_lat, 4326)::extensions.geography
        )
  limit 250;
$$;
