-- Bookmark replaces Like on lists (product decision, 2026-08-21): a list's
-- one engagement action is now "save this to find again," not a lightweight
-- nod. list_likes becomes list_bookmarks in place (same PK shape, same
-- race-safe toggle pattern toggle_reaction was fixed to in
-- 00210000000000_review_fixes.sql) rather than living alongside a second,
-- newly-built table — there's only ever one action on a list now.

alter table public.list_likes rename to list_bookmarks;
alter table public.list_bookmarks rename constraint list_likes_pkey to list_bookmarks_pkey;
alter index list_likes_user_idx rename to list_bookmarks_user_idx;
alter policy "list_likes_select" on public.list_bookmarks rename to "list_bookmarks_select";
alter policy "list_likes_write_own" on public.list_bookmarks rename to "list_bookmarks_write_own";

drop trigger list_likes_notify on public.list_bookmarks;
drop function if exists public.notify_on_list_like();
drop function if exists public.toggle_list_like(bigint);

create or replace function public.toggle_list_bookmark(p_list_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from public.list_bookmarks where list_id = p_list_id and user_id = auth.uid();
  if not found then
    if not exists (select 1 from public.lists l
                     where l.id = p_list_id and (l.owner_id = auth.uid() or l.visibility = 'public')) then
      raise exception 'list not found';
    end if;
    insert into public.list_bookmarks (list_id, user_id) values (p_list_id, auth.uid())
    on conflict do nothing;
  end if;
end;
$$;

-- Every list-returning RPC's shape changes (like_count/liked_by_me ->
-- bookmark_count/bookmarked_by_me), so all four need drop-then-recreate.

drop function if exists public.my_lists();
create or replace function public.my_lists()
returns table (
  id bigint, title text, description text, visibility text,
  course_count int, bookmark_count int, comment_count int,
  created_at timestamptz, updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select l.id, l.title, l.description, l.visibility,
         (select count(*)::int from public.list_items li
            join public.user_course_scores s
              on s.user_id = l.owner_id and s.course_id = li.course_id
           where li.list_id = l.id),
         (select count(*)::int from public.list_bookmarks where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         l.created_at, l.updated_at
  from public.lists l
  where l.owner_id = auth.uid()
  order by l.updated_at desc;
$$;

drop function if exists public.list_detail(bigint);
create or replace function public.list_detail(p_list_id bigint)
returns table (
  id bigint, title text, description text, visibility text,
  owner_id uuid, owner_username text, is_mine boolean, bookmarked_by_me boolean,
  course_count int, bookmark_count int, comment_count int,
  created_at timestamptz, updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select l.id, l.title, l.description, l.visibility,
         l.owner_id, p.username, l.owner_id = auth.uid(),
         exists (select 1 from public.list_bookmarks where list_id = l.id and user_id = auth.uid()),
         (select count(*)::int from public.list_items li
            join public.user_course_scores s
              on s.user_id = l.owner_id and s.course_id = li.course_id
           where li.list_id = l.id),
         (select count(*)::int from public.list_bookmarks where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         l.created_at, l.updated_at
  from public.lists l
  join public.profiles p on p.id = l.owner_id
  where l.id = p_list_id
    and (l.owner_id = auth.uid() or l.visibility = 'public')
    and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid());
$$;

drop function if exists public.explore_lists(int, int);
create or replace function public.explore_lists(p_limit int default 30, p_offset int default 0)
returns table (
  id bigint, title text, description text, visibility text,
  owner_id uuid, owner_username text,
  course_count int, bookmark_count int, comment_count int, bookmarked_by_me boolean,
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
           (select count(*)::int from public.list_bookmarks where list_id = l.id) as bookmark_count,
           (select count(*)::int from public.list_comments where list_id = l.id) as comment_count,
           exists (select 1 from public.list_bookmarks where list_id = l.id and user_id = auth.uid()) as bookmarked_by_me,
           l.updated_at
    from public.lists l
    join public.profiles p on p.id = l.owner_id
    where l.visibility = 'public'
      and l.owner_id <> auth.uid()
      and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  )
  select id, title, description, visibility, owner_id, owner_username,
         course_count, bookmark_count, comment_count, bookmarked_by_me, updated_at
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
  course_count int, bookmark_count int, comment_count int, bookmarked_by_me boolean,
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
         (select count(*)::int from public.list_bookmarks where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         exists (select 1 from public.list_bookmarks where list_id = l.id and user_id = auth.uid()),
         l.updated_at
  from public.lists l
  join public.profiles p on p.id = l.owner_id
  where l.owner_id = p_user_id
    and l.visibility = 'public'
    and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by l.updated_at desc;
$$;

-- The surface bookmarking exists to serve: "lists I've saved to find again."
-- Same visibility/blocked-user predicate as every other list read, so a list
-- that was made private or whose owner got blocked since bookmarking just
-- stops appearing here rather than erroring.
create or replace function public.my_bookmarked_lists()
returns table (
  id bigint, title text, description text, visibility text,
  owner_id uuid, owner_username text,
  course_count int, bookmark_count int, comment_count int, bookmarked_by_me boolean,
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
         (select count(*)::int from public.list_bookmarks where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         true,
         l.updated_at
  from public.list_bookmarks b
  join public.lists l on l.id = b.list_id
  join public.profiles p on p.id = l.owner_id
  where b.user_id = auth.uid()
    and (l.owner_id = auth.uid() or l.visibility = 'public')
    and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by b.created_at desc;
$$;

create or replace function public.notify_on_list_bookmark()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner from public.lists where id = new.list_id;
  perform public.notify(v_owner, new.user_id, 'list_bookmark', null, null, null, new.list_id);
  return new;
end;
$$;

create trigger list_bookmarks_notify after insert on public.list_bookmarks
  for each row execute function public.notify_on_list_bookmark();

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (kind in ('follow', 'comment', 'reaction', 'tag', 'mention', 'list_bookmark', 'list_comment'));
