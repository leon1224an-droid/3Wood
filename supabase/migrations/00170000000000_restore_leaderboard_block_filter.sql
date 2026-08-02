-- Regression fix: 00160 rebuilt leaderboard() from the 00100 version and lost
-- the blocked-user filter that 00120 had added, so people you've blocked
-- reappeared on the board. Moderation is an App Store requirement (1.2), so
-- this restores it.
--
-- Note the parentheses: the period test is an OR, and AND binds tighter, so
-- without them the block filter would only apply to the week branch.

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
  where (p_period <> 'week' or r.first_ranked_at >= date_trunc('week', now()))
    and p.id not in (select blocked from public.blocked_users where blocker = auth.uid())
  group by p.id, p.username, p.display_name
  order by played desc
  limit 100;
$$;
