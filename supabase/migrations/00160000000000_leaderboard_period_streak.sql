-- Weekly leaderboard + "weeks in a row" streak.
--
-- Both features are about *adding* courses, and created_at can't answer that:
-- insert_ranking re-logs by deleting and re-inserting (see 00050), so
-- re-ranking a course you first played in 2019 stamps it with today. Left as
-- is, the weekly board would count re-logs as new courses and a streak would
-- survive on re-ranking the same course every week — which is the opposite of
-- what "streak of adding courses" is supposed to reward.
--
-- first_ranked_at records when a course first entered the user's list and is
-- carried across re-ranks. created_at keeps its existing meaning ("last
-- logged"), which the Played list's "Recently logged" sort depends on.

alter table public.user_course_rankings
  add column first_ranked_at timestamptz not null default now();

-- Backfill: for every existing row the first log is the only log we know of.
update public.user_course_rankings set first_ranked_at = created_at;

create index rankings_first_ranked_idx
  on public.user_course_rankings (user_id, first_ranked_at);

-- Re-declare insert_ranking so re-ranking preserves the original add date.
-- Based on the 00050 definition (the live one — it also clears want_to_play),
-- not the original in 00040.
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
  v_first timestamptz;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- Read the original add date before remove_ranking deletes the row.
  select first_ranked_at into v_first
    from public.user_course_rankings
   where user_id = v_user and course_id = p_course_id;

  perform public.remove_ranking(p_course_id);
  delete from public.want_to_play
   where user_id = v_user and course_id = p_course_id;

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

  insert into public.user_course_rankings
    (user_id, course_id, bucket, rank_position, first_ranked_at)
  values (v_user, p_course_id, p_bucket, p_position, coalesce(v_first, now()));
end;
$$;

-- Leaderboard, now filterable to the current week. Adding a parameter changes
-- the signature, which create or replace can't do — drop first. The parameter
-- is defaulted so the zero-argument call from TestFlight build 2 keeps working
-- against a migrated database.
--
-- 'week' means the current calendar week, Monday-based, in the server's
-- timezone (UTC). A Sunday-evening round on the US west coast therefore counts
-- toward the following week. Not worth timezone plumbing at this scale, but
-- it is a real edge.
drop function if exists public.leaderboard();

create or replace function public.leaderboard(p_period text default 'all')
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
  where p_period <> 'week'
     or r.first_ranked_at >= date_trunc('week', now())
  group by p.id, p.username, p.display_name
  order by played desc
  limit 100;
$$;

-- Consecutive weeks in which the user added at least one new course.
--
-- The current week counts once it has a log; if it doesn't yet, the streak is
-- still considered live through last week, so it doesn't collapse to zero
-- every Monday morning. A two-week gap ends it.
create or replace function public.streak_weeks(p_user uuid default null)
returns int
language sql stable
set search_path = ''
as $$
  with weeks as (
    select distinct date_trunc('week', first_ranked_at)::date as wk
    from public.user_course_rankings
    where user_id = coalesce(p_user, auth.uid())
  ),
  islands as (
    -- Walking back from the newest week, consecutive weeks share a constant
    -- (wk + n*7); any gap shifts it, which separates the islands.
    select wk,
           wk + ((row_number() over (order by wk desc))::int * 7) as grp
    from weeks
  ),
  anchor as (
    select grp
    from islands
    where wk >= date_trunc('week', now())::date - 7
    order by wk desc
    limit 1
  )
  select coalesce(
    (select count(*) from islands i join anchor a on i.grp = a.grp),
    0
  )::int;
$$;
