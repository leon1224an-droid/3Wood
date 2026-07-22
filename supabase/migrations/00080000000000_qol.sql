-- Quality-of-life RPCs: single-course lookup, follower/following lists,
-- and per-state map bounds.

-- One course by id, with community rating (same row shape as search_courses).
create or replace function public.course_by_id(p_id bigint)
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
  where c.id = p_id;
$$;

-- Users who follow p_user_id (with the caller's follow state on each).
create or replace function public.followers(p_user_id uuid)
returns table (id uuid, username text, display_name text, is_following boolean)
language sql stable
set search_path = ''
as $$
  select p.id, p.username, p.display_name,
         exists (select 1 from public.follows f
                  where f.follower_id = auth.uid() and f.followee_id = p.id)
  from public.follows fr
  join public.profiles p on p.id = fr.follower_id
  where fr.followee_id = p_user_id
  order by p.username;
$$;

-- Users p_user_id follows (with the caller's follow state on each).
create or replace function public.following(p_user_id uuid)
returns table (id uuid, username text, display_name text, is_following boolean)
language sql stable
set search_path = ''
as $$
  select p.id, p.username, p.display_name,
         exists (select 1 from public.follows f
                  where f.follower_id = auth.uid() and f.followee_id = p.id)
  from public.follows fr
  join public.profiles p on p.id = fr.followee_id
  where fr.follower_id = p_user_id
  order by p.username;
$$;

-- Bounding box of all courses in a state, for recentering the map.
create or replace function public.state_region(p_state text)
returns table (
  min_lat double precision, min_lng double precision,
  max_lat double precision, max_lng double precision
)
language sql stable
set search_path = ''
as $$
  select min(latitude), min(longitude), max(latitude), max(longitude)
  from public.courses
  where state = upper(p_state);
$$;
