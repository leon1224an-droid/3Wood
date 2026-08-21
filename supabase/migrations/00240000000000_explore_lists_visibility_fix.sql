-- Bug fix: explore_lists() and profile_public_lists() (00230000000000) never
-- returned `visibility`, but the Swift CustomList.visibility field is
-- non-optional (every other list RPC — my_lists, list_detail, list_courses —
-- returns it, so there was no reason for the client to treat it as
-- sometimes-absent). Decoding threw on the missing key, which
-- ExploreListsView/the "Their lists" profile section surfaced as a bare
-- "Couldn't load" — found via manual QA, not caught by the automated suite
-- because nothing had exercised explore_lists() through the actual app
-- before now. Both RPCs only ever return public lists, so the value is
-- always 'public', but returning the real column keeps every CustomList-
-- shaped RPC identically shaped rather than special-casing two of them.

drop function if exists public.explore_lists(int, int);

create or replace function public.explore_lists(p_limit int default 30, p_offset int default 0)
returns table (
  id bigint, title text, description text, visibility text,
  owner_id uuid, owner_username text,
  course_count int, like_count int, comment_count int, liked_by_me boolean,
  updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  with counted as (
    select l.id, l.title, l.description, l.visibility, l.owner_id, p.username as owner_username,
           (select count(*)::int from public.list_items li
              join public.user_course_scores s
                on s.user_id = l.owner_id and s.course_id = li.course_id
             where li.list_id = l.id) as course_count,
           (select count(*)::int from public.list_likes where list_id = l.id) as like_count,
           (select count(*)::int from public.list_comments where list_id = l.id) as comment_count,
           exists (select 1 from public.list_likes where list_id = l.id and user_id = auth.uid()) as liked_by_me,
           l.updated_at
    from public.lists l
    join public.profiles p on p.id = l.owner_id
    where l.visibility = 'public'
      and l.owner_id <> auth.uid()
      and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  )
  select id, title, description, visibility, owner_id, owner_username,
         course_count, like_count, comment_count, liked_by_me, updated_at
  from counted
  where course_count > 0
  order by updated_at desc
  limit p_limit offset p_offset;
$$;

drop function if exists public.profile_public_lists(uuid);

create or replace function public.profile_public_lists(p_user_id uuid)
returns table (
  id bigint, title text, description text, visibility text,
  owner_id uuid, owner_username text,
  course_count int, like_count int, comment_count int, liked_by_me boolean,
  updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select l.id, l.title, l.description, l.visibility, l.owner_id, p.username,
         (select count(*)::int from public.list_items li
            join public.user_course_scores s
              on s.user_id = l.owner_id and s.course_id = li.course_id
           where li.list_id = l.id),
         (select count(*)::int from public.list_likes where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         exists (select 1 from public.list_likes where list_id = l.id and user_id = auth.uid()),
         l.updated_at
  from public.lists l
  join public.profiles p on p.id = l.owner_id
  where l.owner_id = p_user_id
    and l.visibility = 'public'
    and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by l.updated_at desc;
$$;
