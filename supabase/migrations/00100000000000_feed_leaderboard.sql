-- Activity feed and leaderboard.

-- Recent activity from the people you follow (plus yourself, so the feed is
-- never empty): course rankings and want-to-play saves, newest first.
create or replace function public.activity_feed()
returns table (
  kind text,               -- 'ranked' | 'want'
  actor_id uuid,
  username text,
  course_id bigint,
  course_name text,
  city text,
  state text,
  score numeric,           -- null for 'want'
  bucket public.bucket,    -- null for 'want'
  created_at timestamptz
)
language sql stable
set search_path = ''
as $$
  with circle as (
    select auth.uid() as uid
    union
    select followee_id from public.follows where follower_id = auth.uid()
  )
  (
    select 'ranked', s.user_id, p.username, s.course_id, c.name, c.city, c.state,
           s.score, s.bucket, s.created_at
    from public.user_course_scores s
    join public.profiles p on p.id = s.user_id
    join public.courses c on c.id = s.course_id
    where s.user_id in (select uid from circle)
  )
  union all
  (
    select 'want', w.user_id, p.username, w.course_id, c.name, c.city, c.state,
           null, null, w.created_at
    from public.want_to_play w
    join public.profiles p on p.id = w.user_id
    join public.courses c on c.id = w.course_id
    where w.user_id in (select uid from circle)
  )
  order by created_at desc
  limit 60;
$$;

-- Leaderboard by number of courses ranked (the core "reviewed" metric).
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
  group by p.id, p.username, p.display_name
  order by played desc
  limit 100;
$$;
