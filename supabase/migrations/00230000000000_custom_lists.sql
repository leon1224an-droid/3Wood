-- Custom Lists: named, curated sub-lists of courses a user has already
-- played and ranked (e.g. "Best Pacific Northwest Courses"), with
-- public/private visibility, likes, comments, and an Explore feed of other
-- users' public lists.
--
-- Guideline 1.2 note: list_comments is a new UGC surface, added with the
-- same report/block moderation coverage every other UGC surface has — see
-- the reports/notifications sections below. This is not an afterthought;
-- App Review just rejected the app once for insufficient UGC moderation.
--
-- Design note — no manual position, no cleanup trigger: list_items has no
-- position column, and nothing deletes a list_items row when its course is
-- un-ranked. insert_ranking calls remove_ranking(p_course_id, false) on
-- EVERY re-rank (00220000000000_course_visits.sql:61), so any trigger tied
-- to ranking removal would also fire — and wipe list membership — on a
-- routine re-rank, not just when a course is actually dropped. Instead,
-- every read RPC below inner-joins list_items against the OWNER's live
-- user_course_scores: a course that's no longer ranked simply stops
-- appearing (and its list's course_count drops), and reappears with zero
-- write-path coupling if it's re-ranked. Order is always the owner's
-- current score, never stored.

create table public.lists (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  title       text not null check (char_length(title) between 1 and 80),
  -- Nullable, unused by any editor yet — reserved so a future blog-post-style
  -- expansion doesn't need a migration to add it.
  description text check (description is null or char_length(description) <= 5000),
  visibility  text not null default 'private' check (visibility in ('private', 'public')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index lists_owner_idx on public.lists (owner_id, updated_at desc);
create index lists_public_idx on public.lists (visibility, updated_at desc) where visibility = 'public';

alter table public.lists enable row level security;

create policy "lists_select" on public.lists
  for select to authenticated using (owner_id = auth.uid() or visibility = 'public');
create policy "lists_write_own" on public.lists
  for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

grant select, insert, update, delete on public.lists to authenticated;

create table public.list_items (
  list_id    bigint not null references public.lists on delete cascade,
  course_id  bigint not null references public.courses on delete cascade,
  added_at   timestamptz not null default now(),
  primary key (list_id, course_id)
);

create index list_items_course_idx on public.list_items (course_id);

alter table public.list_items enable row level security;

create policy "list_items_select" on public.list_items
  for select to authenticated using (
    exists (select 1 from public.lists l
             where l.id = list_id and (l.owner_id = auth.uid() or l.visibility = 'public'))
  );
create policy "list_items_write_own" on public.list_items
  for all to authenticated using (
    exists (select 1 from public.lists l where l.id = list_id and l.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.lists l where l.id = list_id and l.owner_id = auth.uid())
  );

grant select, insert, delete on public.list_items to authenticated;

create table public.list_likes (
  list_id    bigint not null references public.lists on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create index list_likes_user_idx on public.list_likes (user_id);

alter table public.list_likes enable row level security;

create policy "list_likes_select" on public.list_likes
  for select to authenticated using (
    exists (select 1 from public.lists l
             where l.id = list_id and (l.owner_id = auth.uid() or l.visibility = 'public'))
  );
create policy "list_likes_write_own" on public.list_likes
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.list_likes to authenticated;

create table public.list_comments (
  id         bigint generated always as identity primary key,
  list_id    bigint not null references public.lists on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);

create index list_comments_list_idx on public.list_comments (list_id, created_at);

alter table public.list_comments enable row level security;

create policy "list_comments_select" on public.list_comments
  for select to authenticated using (
    exists (select 1 from public.lists l
             where l.id = list_id and (l.owner_id = auth.uid() or l.visibility = 'public'))
  );
create policy "list_comments_write_own" on public.list_comments
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.list_comments to authenticated;

-- Guideline 1.2: same report path reviews/comments/photos already have.
-- Bare nullable target columns, matching the pattern in
-- 00180000000000_activities_reactions_comments.sql and
-- 00190000000000_course_photos.sql — no exactly-one-target constraint, this
-- table has never had one. list_id on its own (not just list_comment_id)
-- matters: a list's title/description is itself user-authored text on a
-- public surface, reportable independent of any one comment.
alter table public.reports add column list_id bigint references public.lists on delete cascade;
alter table public.reports add column list_comment_id bigint references public.list_comments on delete cascade;

-- ---------------------------------------------------------------------------
-- course_type on my_ranked_courses() — the list picker filters by it, and it
-- was never on this RPC (only state was). Return-shape change needs the
-- drop-then-recreate my_ranked_courses/notifications both already required
-- once before, in 00220000000000.
-- ---------------------------------------------------------------------------

drop function if exists public.my_ranked_courses();

create or replace function public.my_ranked_courses()
returns table (
  course_id bigint, name text, city text, state text, course_type text,
  bucket public.bucket, rank_position int, score numeric,
  created_at timestamptz,
  last_played_on text,
  visit_count int
)
language sql stable
set search_path = ''
as $$
  select s.course_id, c.name, c.city, c.state, c.course_type, s.bucket, s.rank_position, s.score,
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

-- ---------------------------------------------------------------------------
-- Write RPCs
-- ---------------------------------------------------------------------------

create or replace function public.create_list(
  p_title text, p_description text default null, p_visibility text default 'private'
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
  if p_visibility not in ('private', 'public') then
    raise exception 'invalid visibility %', p_visibility;
  end if;
  insert into public.lists (owner_id, title, description, visibility)
  values (auth.uid(), p_title, nullif(trim(coalesce(p_description, '')), ''), p_visibility)
  returning id into v_id;
  return v_id;
end;
$$;

-- Rename/edit/visibility in one call. p_description = null means "leave it
-- alone"; an empty/whitespace string clears it back to null. Callers that
-- want an unconditional overwrite (the edit sheet) should always pass the
-- full current-or-new value, never omit it.
create or replace function public.update_list(
  p_list_id bigint, p_title text default null, p_description text default null,
  p_visibility text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_visibility is not null and p_visibility not in ('private', 'public') then
    raise exception 'invalid visibility %', p_visibility;
  end if;
  update public.lists
     set title = coalesce(p_title, title),
         description = case when p_description is null then description
                             else nullif(trim(p_description), '') end,
         visibility = coalesce(p_visibility, visibility),
         updated_at = now()
   where id = p_list_id and owner_id = auth.uid();
  if not found then
    raise exception 'list not found or not yours';
  end if;
end;
$$;

create or replace function public.delete_list(p_list_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from public.lists where id = p_list_id and owner_id = auth.uid();
  if not found then
    raise exception 'list not found or not yours';
  end if;
end;
$$;

-- The enforcement point for "a list can only contain courses you've played
-- and ranked": only inserts course_ids present in the caller's OWN
-- user_course_scores, silently skipping the rest — the UI only ever offers
-- ranked courses, so a mismatch here is a stale-client race, not a user
-- error. Returns how many were actually inserted.
create or replace function public.add_courses_to_list(p_list_id bigint, p_course_ids bigint[])
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not exists (select 1 from public.lists where id = p_list_id and owner_id = auth.uid()) then
    raise exception 'list not found or not yours';
  end if;

  insert into public.list_items (list_id, course_id)
  select p_list_id, cid
    from unnest(p_course_ids) as cid
   where exists (select 1 from public.user_course_scores s
                  where s.user_id = auth.uid() and s.course_id = cid)
  on conflict do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Backs both swipe-to-remove on the list detail screen and deselecting a
-- course in the add/remove sheet.
create or replace function public.remove_course_from_list(p_list_id bigint, p_course_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from public.list_items
   where list_id = p_list_id and course_id = p_course_id
     and exists (select 1 from public.lists where id = p_list_id and owner_id = auth.uid());
end;
$$;

-- ---------------------------------------------------------------------------
-- Read RPCs — every one applies the standard blocked-user filter, and
-- course_count uses the identical inner-join-against-live-scores expression
-- everywhere it appears so a list can't say "12 courses" in one place and
-- show 11 in another.
-- ---------------------------------------------------------------------------

create or replace function public.my_lists()
returns table (
  id bigint, title text, description text, visibility text,
  course_count int, like_count int, comment_count int,
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
         (select count(*)::int from public.list_likes where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         l.created_at, l.updated_at
  from public.lists l
  where l.owner_id = auth.uid()
  order by l.updated_at desc;
$$;

-- Ranked courses for one list, ordered by the OWNER's live score — this is
-- the read-time join described at the top of this file. Deliberately
-- returns only the fields a viewer needs (not full RankedCourse — bucket/
-- rank_position are per-owner bookkeeping, meaningless to someone else).
create or replace function public.list_courses(p_list_id bigint)
returns table (
  course_id bigint, name text, city text, state text, score numeric, added_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select c.id, c.name, c.city, c.state, s.score, li.added_at
  from public.list_items li
  join public.lists l on l.id = li.list_id
  join public.courses c on c.id = li.course_id
  join public.user_course_scores s on s.user_id = l.owner_id and s.course_id = li.course_id
  where li.list_id = p_list_id
    and (l.owner_id = auth.uid() or l.visibility = 'public')
    and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by s.score desc, c.name;
$$;

-- Card-shaped hydration for a single list, for deep links (Destination
-- .listID) that arrive without a CustomList value already in hand — mirrors
-- activity(p_activity_id).
create or replace function public.list_detail(p_list_id bigint)
returns table (
  id bigint, title text, description text, visibility text,
  owner_id uuid, owner_username text, is_mine boolean, liked_by_me boolean,
  course_count int, like_count int, comment_count int,
  created_at timestamptz, updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select l.id, l.title, l.description, l.visibility,
         l.owner_id, p.username, l.owner_id = auth.uid(),
         exists (select 1 from public.list_likes where list_id = l.id and user_id = auth.uid()),
         (select count(*)::int from public.list_items li
            join public.user_course_scores s
              on s.user_id = l.owner_id and s.course_id = li.course_id
           where li.list_id = l.id),
         (select count(*)::int from public.list_likes where list_id = l.id),
         (select count(*)::int from public.list_comments where list_id = l.id),
         l.created_at, l.updated_at
  from public.lists l
  join public.profiles p on p.id = l.owner_id
  where l.id = p_list_id
    and (l.owner_id = auth.uid() or l.visibility = 'public')
    and l.owner_id not in (select blocked from public.blocked_users where blocker = auth.uid());
$$;

-- Global public feed (not following-only, per product decision), newest
-- edited first. Excludes the caller's own lists (those live in My Lists),
-- blocked owners, and lists with zero currently-ranked courses (a public
-- list with nothing in it is noise, not content). The CTE materializes
-- course_count so the outer query can filter/order on it — a raw HAVING
-- without GROUP BY can't reference a per-row correlated subquery here.
create or replace function public.explore_lists(p_limit int default 30, p_offset int default 0)
returns table (
  id bigint, title text, description text, owner_id uuid, owner_username text,
  course_count int, like_count int, comment_count int, liked_by_me boolean,
  updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  with counted as (
    select l.id, l.title, l.description, l.owner_id, p.username as owner_username,
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
  select id, title, description, owner_id, owner_username,
         course_count, like_count, comment_count, liked_by_me, updated_at
  from counted
  where course_count > 0
  order by updated_at desc
  limit p_limit offset p_offset;
$$;

-- A user's public lists, for their profile page. Unlike explore_lists, does
-- NOT hide empty lists — this is "what's on their profile," not a discovery
-- feed, so it should match what the owner sees when building it out.
create or replace function public.profile_public_lists(p_user_id uuid)
returns table (
  id bigint, title text, description text, owner_id uuid, owner_username text,
  course_count int, like_count int, comment_count int, liked_by_me boolean,
  updated_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select l.id, l.title, l.description, l.owner_id, p.username,
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

-- ---------------------------------------------------------------------------
-- Engagement
-- ---------------------------------------------------------------------------

-- Delete-first, insert-only-if-nothing-was-there — the race-safe form
-- toggle_reaction was fixed to in 00210000000000_review_fixes.sql, not the
-- original check-then-act version two fast taps could double-fire.
create or replace function public.toggle_list_like(p_list_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from public.list_likes where list_id = p_list_id and user_id = auth.uid();
  if not found then
    if not exists (select 1 from public.lists l
                     where l.id = p_list_id and (l.owner_id = auth.uid() or l.visibility = 'public')) then
      raise exception 'list not found';
    end if;
    insert into public.list_likes (list_id, user_id) values (p_list_id, auth.uid())
    on conflict do nothing;
  end if;
end;
$$;

-- security definer bypasses RLS, so list visibility must be checked
-- explicitly here — without this, anyone could comment on a private list
-- they have no business seeing.
create or replace function public.add_list_comment(p_list_id bigint, p_body text)
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
  if not exists (select 1 from public.lists l
                   where l.id = p_list_id and (l.owner_id = auth.uid() or l.visibility = 'public')) then
    raise exception 'list not found';
  end if;
  insert into public.list_comments (list_id, user_id, body)
  values (p_list_id, auth.uid(), p_body)
  returning id into v_id;
  return v_id;
end;
$$;

-- Byte-for-byte the shape of activity_comments(p_activity_id) so the
-- existing ActivityComment Swift model is reused unchanged.
create or replace function public.list_comments(p_list_id bigint)
returns table (
  id bigint, user_id uuid, username text, body text, created_at timestamptz, is_mine boolean
)
language sql stable
set search_path = ''
as $$
  select cm.id, cm.user_id, p.username, cm.body, cm.created_at, cm.user_id = auth.uid()
  from public.list_comments cm
  join public.profiles p on p.id = cm.user_id
  join public.lists l on l.id = cm.list_id
  where cm.list_id = p_list_id
    and (l.owner_id = auth.uid() or l.visibility = 'public')
    and cm.user_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by cm.created_at;
$$;

-- ---------------------------------------------------------------------------
-- Notifications — two new kinds, most cross-cutting and least load-bearing
-- part of this migration. Likes/comments work fully without this section;
-- it just makes them silent rather than notified.
-- ---------------------------------------------------------------------------

alter table public.notifications add column list_id bigint references public.lists on delete cascade;
alter table public.notifications add column list_comment_id bigint references public.list_comments on delete cascade;

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (kind in ('follow', 'comment', 'reaction', 'tag', 'mention', 'list_like', 'list_comment'));

-- Two new trailing defaulted params. CREATE OR REPLACE matches on the
-- declared parameter list, not the "effective" signature after defaults —
-- adding params here is the exact same overload trap remove_ranking hit
-- once already (see the handoff doc): without the drop, the 6-arg and 8-arg
-- versions coexist, and any call relying on defaults to fill the gap becomes
-- ambiguous ("function is not unique"). Drop the old signature first.
drop function if exists public.notify(uuid, uuid, text, bigint, bigint, text);

create or replace function public.notify(
  p_user uuid, p_actor uuid, p_kind text,
  p_activity bigint default null, p_comment bigint default null, p_emoji text default null,
  p_list bigint default null, p_list_comment bigint default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if p_user is null or p_actor is null or p_user = p_actor then
    return;
  end if;
  if exists (select 1 from public.blocked_users
              where blocker = p_user and blocked = p_actor) then
    return;
  end if;
  insert into public.notifications
    (user_id, actor_id, kind, activity_id, comment_id, emoji, list_id, list_comment_id)
  values (p_user, p_actor, p_kind, p_activity, p_comment, p_emoji, p_list, p_list_comment);
end;
$$;

create or replace function public.notify_on_list_like()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner from public.lists where id = new.list_id;
  perform public.notify(v_owner, new.user_id, 'list_like', null, null, null, new.list_id);
  return new;
end;
$$;

create trigger list_likes_notify after insert on public.list_likes
  for each row execute function public.notify_on_list_like();

create or replace function public.notify_on_list_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner from public.lists where id = new.list_id;
  perform public.notify(v_owner, new.user_id, 'list_comment', null, null, null, new.list_id, new.id);
  return new;
end;
$$;

create trigger list_comments_notify after insert on public.list_comments
  for each row execute function public.notify_on_list_comment();

-- Return-shape change (two new columns) needs drop-then-recreate, same as
-- my_ranked_courses above and my_ranked_courses in 00220000000000.
drop function if exists public.notifications(int);

create or replace function public.notifications(p_limit int default 50)
returns table (
  id bigint,
  kind text,
  actor_id uuid,
  actor_username text,
  activity_id bigint,
  course_id bigint,
  course_name text,
  emoji text,
  comment_body text,
  list_id bigint,
  list_title text,
  read_at timestamptz,
  created_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select n.id, n.kind, n.actor_id, p.username, n.activity_id,
         a.course_id, c.name, n.emoji, coalesce(cm.body, lc.body),
         n.list_id, l.title,
         n.read_at, n.created_at
  from public.notifications n
  join public.profiles p on p.id = n.actor_id
  left join public.activities a on a.id = n.activity_id
  left join public.courses c on c.id = a.course_id
  left join public.activity_comments cm on cm.id = n.comment_id
  left join public.lists l on l.id = n.list_id
  left join public.list_comments lc on lc.id = n.list_comment_id
  where n.user_id = auth.uid()
    and n.actor_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid())
  order by n.created_at desc
  limit p_limit;
$$;
