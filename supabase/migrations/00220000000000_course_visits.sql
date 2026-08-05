-- Rounds played: when you played a course, and playing it again.
--
-- Ranking a course said *that* you'd played it but never *when*, and there was
-- no way to record a second round without re-ranking — which overwrites rather
-- than accumulates. A visit is its own row so a course can carry many.
--
-- (user_course_rankings.played_at has existed since 00040 but was never read or
-- written by the app. It stays unused; a single nullable column can't hold a
-- history anyway.)

create table public.course_visits (
  id         bigint generated always as identity primary key,
  user_id    uuid   not null default auth.uid() references public.profiles on delete cascade,
  course_id  bigint not null references public.courses on delete cascade,
  played_on  date   not null default current_date,
  created_at timestamptz not null default now()
);

create index course_visits_user_idx on public.course_visits (user_id, course_id, played_on desc);

alter table public.course_visits enable row level security;

-- Readable like rankings are (profiles are public); own-row writes.
create policy "course_visits_select" on public.course_visits
  for select to authenticated using (true);
create policy "course_visits_write_own" on public.course_visits
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.course_visits to authenticated;

-- Backfill one visit per existing ranking, dated when the course was first
-- ranked — the closest thing to a play date we have.
insert into public.course_visits (user_id, course_id, played_on)
select user_id, course_id, first_ranked_at::date
from public.user_course_rankings
on conflict do nothing;

-- Logging a course for the FIRST time records a round. Re-ranking does not —
-- it's a change of opinion, not another round. A second round is an explicit
-- check-in via log_visit.
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

  select first_ranked_at into v_first
    from public.user_course_rankings
   where user_id = v_user and course_id = p_course_id;

  perform public.remove_ranking(p_course_id, false);
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

  insert into public.activities (actor_id, kind, course_id)
  values (v_user, 'ranked', p_course_id)
  on conflict (actor_id, kind, course_id) do nothing;

  -- v_first is null only when this course wasn't already on the list.
  if v_first is null then
    insert into public.course_visits (user_id, course_id)
    values (v_user, p_course_id);
  end if;
end;
$$;

-- Record another round. Defaults to today; a date is accepted so a round can
-- be logged after the fact.
create or replace function public.log_visit(
  p_course_id bigint, p_played_on date default null
)
returns bigint
language plpgsql security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  -- The picker caps at today, but the RPC is the real boundary: a future round
  -- would sort to the top of the history and show as "last played".
  if p_played_on is not null and p_played_on > current_date then
    raise exception 'cannot log a round in the future';
  end if;
  insert into public.course_visits (user_id, course_id, played_on)
  values (auth.uid(), p_course_id, coalesce(p_played_on, current_date))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.delete_visit(p_id bigint)
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.course_visits where id = p_id and user_id = auth.uid();
$$;

-- The caller's rounds at one course, most recent first.
-- played_on comes back as text, not date: the Supabase Swift decoder only
-- accepts full ISO-8601 timestamps, so a bare "2026-08-05" fails to decode.
-- Formatting here also avoids any timezone shifting the day.
create or replace function public.course_visits(p_course_id bigint)
returns table (id bigint, played_on text)
language sql stable
set search_path = ''
as $$
  select v.id, to_char(v.played_on, 'YYYY-MM-DD')
  from public.course_visits v
  where v.course_id = p_course_id and v.user_id = auth.uid()
  order by v.played_on desc, v.id desc;
$$;

-- Played list gains when it was last played and how many rounds. Return-table
-- changes need drop + recreate.
drop function if exists public.my_ranked_courses();

create or replace function public.my_ranked_courses()
returns table (
  course_id bigint, name text, city text, state text,
  bucket public.bucket, rank_position int, score numeric,
  created_at timestamptz,
  last_played_on text,   -- text for the same decoder reason as course_visits
  visit_count int
)
language sql stable
set search_path = ''
as $$
  select s.course_id, c.name, c.city, c.state, s.bucket, s.rank_position, s.score,
         s.created_at,
         (select to_char(max(v.played_on), 'YYYY-MM-DD') from public.course_visits v
           where v.user_id = s.user_id and v.course_id = s.course_id),
         (select count(*)::int from public.course_visits v
           where v.user_id = s.user_id and v.course_id = s.course_id)
  from public.user_course_scores s
  join public.courses c on c.id = s.course_id
  where s.user_id = auth.uid()
  order by case s.bucket when 'liked' then 0 when 'fine' then 1 else 2 end,
           s.rank_position;
$$;
