-- Played-list "Recently logged" sort: expose when each course was ranked.
-- Return-table changes require drop + recreate (create or replace can't
-- alter the OUT column list).

drop function if exists public.my_ranked_courses();

create or replace function public.my_ranked_courses()
returns table (
  course_id bigint, name text, city text, state text,
  bucket public.bucket, rank_position int, score numeric,
  created_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select s.course_id, c.name, c.city, c.state, s.bucket, s.rank_position, s.score,
         s.created_at
  from public.user_course_scores s
  join public.courses c on c.id = s.course_id
  where s.user_id = auth.uid()
  order by case s.bucket when 'liked' then 0 when 'fine' then 1 else 2 end,
           s.rank_position;
$$;
