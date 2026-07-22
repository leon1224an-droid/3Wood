-- "Want to Play" bookmarks.
create table public.want_to_play (
  user_id    uuid   not null references public.profiles on delete cascade,
  course_id  bigint not null references public.courses on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, course_id)
);

alter table public.want_to_play enable row level security;

-- Public read (profiles show want-to-play lists); own-row writes.
create policy "want_to_play_select" on public.want_to_play
  for select to authenticated using (true);
create policy "want_to_play_insert_own" on public.want_to_play
  for insert to authenticated with check (user_id = auth.uid());
create policy "want_to_play_delete_own" on public.want_to_play
  for delete to authenticated using (user_id = auth.uid());

grant select, insert, delete on public.want_to_play to authenticated;

-- The caller's bookmarks with course info + community rating,
-- newest first. Same row shape as the course search RPCs.
create or replace function public.my_want_to_play()
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
  from public.want_to_play w
  join public.courses c on c.id = w.course_id
  left join public.course_community_ratings r on r.course_id = c.id
  where w.user_id = auth.uid()
  order by w.created_at desc;
$$;

-- Logging a course means you've played it: drop it from Want to Play.
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

  insert into public.user_course_rankings (user_id, course_id, bucket, rank_position)
  values (v_user, p_course_id, p_bucket, p_position);
end;
$$;
