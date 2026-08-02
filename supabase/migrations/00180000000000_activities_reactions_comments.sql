-- Activities, reactions and comments.
--
-- Until now the feed was a UNION view over user_course_scores + want_to_play,
-- so a feed entry had no server-side identity at all (FeedItem synthesised an
-- id client-side from actor+course+timestamp). Nothing could be attached to
-- one. This introduces a real activity row so reactions, comments and
-- notifications have something to point at.
--
-- Rebuilt from the LAST definition of each function, which for activity_feed()
-- is 00120 (blocked-user filtering), not 00100 where it was introduced.

create table public.activities (
  id         bigint generated always as identity primary key,
  actor_id   uuid   not null references public.profiles on delete cascade,
  kind       text   not null check (kind in ('ranked', 'want')),
  course_id  bigint not null references public.courses on delete cascade,
  created_at timestamptz not null default now(),
  -- One activity per person per course per kind. Re-ranking a course must not
  -- spawn a second entry (and must not orphan the comments on the first).
  unique (actor_id, kind, course_id)
);

create index activities_feed_idx on public.activities (actor_id, created_at desc);

alter table public.activities enable row level security;

-- Readable by any signed-in user (the feed filters by who you follow);
-- never written directly — the ranking RPCs and want_to_play triggers own it.
create policy "activities_select" on public.activities
  for select to authenticated using (true);

grant select on public.activities to authenticated;

-- Backfill from the two sources the feed used to union.
insert into public.activities (actor_id, kind, course_id, created_at)
select user_id, 'ranked', course_id, created_at from public.user_course_rankings
on conflict do nothing;

insert into public.activities (actor_id, kind, course_id, created_at)
select user_id, 'want', course_id, created_at from public.want_to_play
on conflict do nothing;

-- want_to_play is written directly by the app, so it gets triggers.
create or replace function public.sync_want_activity()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.activities (actor_id, kind, course_id)
    values (new.user_id, 'want', new.course_id)
    on conflict (actor_id, kind, course_id) do nothing;
    return new;
  else
    delete from public.activities
     where actor_id = old.user_id and kind = 'want' and course_id = old.course_id;
    return old;
  end if;
end;
$$;

create trigger want_to_play_activity_ins
  after insert on public.want_to_play
  for each row execute function public.sync_want_activity();

create trigger want_to_play_activity_del
  after delete on public.want_to_play
  for each row execute function public.sync_want_activity();

-- Rankings are written only through the RPCs, so they manage activities
-- explicitly. A trigger can't work here: insert_ranking re-logs by calling
-- remove_ranking then inserting, and a delete trigger would drop the activity
-- (and cascade its comments away) on every re-rank.
--
-- Rebuilt from 00040 plus a flag so the internal call can keep the activity.
--
-- The old one-argument version MUST be dropped first: adding a parameter is a
-- new signature, so "create or replace" would leave both in place and the
-- app's one-argument call (RankingRepo.remove) would fail with
-- "function remove_ranking(bigint) is not unique".
drop function if exists public.remove_ranking(bigint);

create or replace function public.remove_ranking(
  p_course_id bigint, p_drop_activity boolean default true
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_bucket public.bucket;
  v_pos    int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  delete from public.user_course_rankings
   where user_id = v_user and course_id = p_course_id
   returning bucket, rank_position into v_bucket, v_pos;

  if v_pos is not null then
    update public.user_course_rankings
       set rank_position = rank_position + 1000000
     where user_id = v_user and bucket = v_bucket and rank_position > v_pos;
    update public.user_course_rankings
       set rank_position = rank_position - 1000001
     where user_id = v_user and bucket = v_bucket and rank_position > 1000000;
  end if;

  if p_drop_activity then
    delete from public.activities
     where actor_id = v_user and kind = 'ranked' and course_id = p_course_id;
  end if;
end;
$$;

-- Rebuilt from 00160 (first_ranked_at preservation) + activity creation.
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

  -- false: a re-rank keeps its activity, so reactions and comments survive.
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
end;
$$;

-- ---------------------------------------------------------------------------
-- Reactions: one per person per activity, swapping emoji rather than stacking.
-- The allowed set is deliberately NOT constrained here — emoji equality across
-- variation selectors is a trap, and the app owns the palette.
-- ---------------------------------------------------------------------------

create table public.activity_reactions (
  activity_id bigint not null references public.activities on delete cascade,
  user_id     uuid   not null default auth.uid() references public.profiles on delete cascade,
  emoji       text   not null check (char_length(emoji) between 1 and 16),
  created_at  timestamptz not null default now(),
  primary key (activity_id, user_id)
);

create index activity_reactions_activity_idx on public.activity_reactions (activity_id);

alter table public.activity_reactions enable row level security;

create policy "reactions_select" on public.activity_reactions
  for select to authenticated using (true);
create policy "reactions_write_own" on public.activity_reactions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.activity_reactions to authenticated;

create table public.activity_comments (
  id          bigint generated always as identity primary key,
  activity_id bigint not null references public.activities on delete cascade,
  user_id     uuid   not null default auth.uid() references public.profiles on delete cascade,
  body        text   not null check (char_length(body) between 1 and 500),
  created_at  timestamptz not null default now()
);

create index activity_comments_activity_idx on public.activity_comments (activity_id, created_at);

alter table public.activity_comments enable row level security;

create policy "comments_select" on public.activity_comments
  for select to authenticated using (true);
create policy "comments_write_own" on public.activity_comments
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.activity_comments to authenticated;

-- Comments are user-generated content, so they need the same report path
-- reviews have (App Store 1.2). reports could only describe a user or a review.
alter table public.reports add column comment_id bigint references public.activity_comments on delete cascade;

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------

create table public.notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles on delete cascade,  -- recipient
  actor_id    uuid not null references public.profiles on delete cascade,
  kind        text not null check (kind in ('follow', 'comment', 'reaction')),
  activity_id bigint references public.activities on delete cascade,
  comment_id  bigint references public.activity_comments on delete cascade,
  emoji       text,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_inbox_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

-- Strictly your own inbox. Rows are written by triggers (security definer),
-- never by clients — otherwise anyone could forge a notification.
create policy "notifications_select_own" on public.notifications
  for select to authenticated using (user_id = auth.uid());
create policy "notifications_update_own" on public.notifications
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, update on public.notifications to authenticated;

-- Blocks are enforced at write time: if the recipient has blocked the actor,
-- the notification is never created. Cheaper than filtering every read, and it
-- means unread counts can't be inflated by someone you've blocked.
create or replace function public.notify(
  p_user uuid, p_actor uuid, p_kind text,
  p_activity bigint default null, p_comment bigint default null, p_emoji text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if p_user is null or p_actor is null or p_user = p_actor then
    return;  -- never notify yourself
  end if;
  if exists (select 1 from public.blocked_users
              where blocker = p_user and blocked = p_actor) then
    return;
  end if;
  insert into public.notifications (user_id, actor_id, kind, activity_id, comment_id, emoji)
  values (p_user, p_actor, p_kind, p_activity, p_comment, p_emoji);
end;
$$;

create or replace function public.notify_on_follow()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify(new.followee_id, new.follower_id, 'follow');
  return new;
end;
$$;

create trigger follows_notify after insert on public.follows
  for each row execute function public.notify_on_follow();

create or replace function public.notify_on_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  select actor_id into v_owner from public.activities where id = new.activity_id;
  perform public.notify(v_owner, new.user_id, 'comment', new.activity_id, new.id);
  return new;
end;
$$;

create trigger comments_notify after insert on public.activity_comments
  for each row execute function public.notify_on_comment();

create or replace function public.notify_on_reaction()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  select actor_id into v_owner from public.activities where id = new.activity_id;
  perform public.notify(v_owner, new.user_id, 'reaction', new.activity_id, null, new.emoji);
  return new;
end;
$$;

-- Only on insert, not on emoji swap — changing your mind shouldn't re-ping.
create trigger reactions_notify after insert on public.activity_reactions
  for each row execute function public.notify_on_reaction();

-- ---------------------------------------------------------------------------
-- Read APIs
-- ---------------------------------------------------------------------------

-- Feed, now activity-backed. Same blocked-user filtering as 00120, plus the
-- engagement counts each row needs to render.
drop function if exists public.activity_feed();

create or replace function public.activity_feed()
returns table (
  activity_id bigint,
  kind text,
  actor_id uuid,
  username text,
  course_id bigint,
  course_name text,
  city text,
  state text,
  score numeric,
  bucket public.bucket,
  created_at timestamptz,
  reaction_count bigint,
  comment_count bigint,
  my_reaction text,
  top_emojis text[]
)
language sql stable
set search_path = ''
as $$
  with circle as (
    select auth.uid() as uid
    union
    select followee_id from public.follows where follower_id = auth.uid()
  ),
  visible as (
    select uid from circle
    where uid not in (select blocked from public.blocked_users where blocker = auth.uid())
  )
  select a.id, a.kind, a.actor_id, p.username, a.course_id, c.name, c.city, c.state,
         s.score, s.bucket, a.created_at,
         (select count(*) from public.activity_reactions r where r.activity_id = a.id),
         (select count(*) from public.activity_comments cm
           where cm.activity_id = a.id
             and cm.user_id not in (select blocked from public.blocked_users
                                     where blocker = auth.uid())),
         (select r.emoji from public.activity_reactions r
           where r.activity_id = a.id and r.user_id = auth.uid()),
         (select array_agg(e.emoji order by e.n desc)
            from (select r.emoji, count(*) as n
                    from public.activity_reactions r
                   where r.activity_id = a.id
                   group by r.emoji
                   order by count(*) desc
                   limit 3) e)
  from public.activities a
  join public.profiles p on p.id = a.actor_id
  join public.courses c on c.id = a.course_id
  -- Scores only exist for 'ranked'; 'want' rows carry nulls, as before.
  left join public.user_course_scores s
    on a.kind = 'ranked' and s.user_id = a.actor_id and s.course_id = a.course_id
  where a.actor_id in (select uid from visible)
  order by a.created_at desc
  limit 60;
$$;

-- One activity's comments, oldest first (a conversation reads down).
create or replace function public.activity_comments(p_activity_id bigint)
returns table (
  id bigint, user_id uuid, username text, body text,
  created_at timestamptz, is_mine boolean
)
language sql stable
set search_path = ''
as $$
  select cm.id, cm.user_id, p.username, cm.body, cm.created_at,
         cm.user_id = auth.uid()
  from public.activity_comments cm
  join public.profiles p on p.id = cm.user_id
  where cm.activity_id = p_activity_id
    and cm.user_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid())
  order by cm.created_at;
$$;

-- Set, swap, or clear the caller's reaction. Passing the emoji you already
-- have removes it, so the same tap toggles.
create or replace function public.toggle_reaction(p_activity_id bigint, p_emoji text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_existing text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  select emoji into v_existing from public.activity_reactions
   where activity_id = p_activity_id and user_id = auth.uid();

  if v_existing is null then
    insert into public.activity_reactions (activity_id, user_id, emoji)
    values (p_activity_id, auth.uid(), p_emoji);
  elsif v_existing = p_emoji then
    delete from public.activity_reactions
     where activity_id = p_activity_id and user_id = auth.uid();
  else
    update public.activity_reactions set emoji = p_emoji
     where activity_id = p_activity_id and user_id = auth.uid();
  end if;
end;
$$;

create or replace function public.add_comment(p_activity_id bigint, p_body text)
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
  insert into public.activity_comments (activity_id, user_id, body)
  values (p_activity_id, auth.uid(), p_body)
  returning id into v_id;
  return v_id;
end;
$$;

-- The caller's inbox, newest first, with enough context to render a line and
-- deep-link to the activity.
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
  read_at timestamptz,
  created_at timestamptz
)
language sql stable
set search_path = ''
as $$
  select n.id, n.kind, n.actor_id, p.username, n.activity_id,
         a.course_id, c.name, n.emoji, cm.body, n.read_at, n.created_at
  from public.notifications n
  join public.profiles p on p.id = n.actor_id
  left join public.activities a on a.id = n.activity_id
  left join public.courses c on c.id = a.course_id
  left join public.activity_comments cm on cm.id = n.comment_id
  where n.user_id = auth.uid()
    and n.actor_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid())
  order by n.created_at desc
  limit p_limit;
$$;

create or replace function public.unread_notification_count()
returns int
language sql stable
set search_path = ''
as $$
  select count(*)::int from public.notifications
   where user_id = auth.uid() and read_at is null;
$$;

create or replace function public.mark_notifications_read()
returns void
language sql security definer
set search_path = ''
as $$
  update public.notifications set read_at = now()
   where user_id = auth.uid() and read_at is null;
$$;

-- A single activity in the same shape as the feed, for deep links from the
-- alert feed. Not restricted to who you follow — a notification can point at
-- an activity from outside your circle — but blocked actors stay hidden.
create or replace function public.activity(p_activity_id bigint)
returns table (
  activity_id bigint,
  kind text,
  actor_id uuid,
  username text,
  course_id bigint,
  course_name text,
  city text,
  state text,
  score numeric,
  bucket public.bucket,
  created_at timestamptz,
  reaction_count bigint,
  comment_count bigint,
  my_reaction text,
  top_emojis text[]
)
language sql stable
set search_path = ''
as $$
  select a.id, a.kind, a.actor_id, p.username, a.course_id, c.name, c.city, c.state,
         s.score, s.bucket, a.created_at,
         (select count(*) from public.activity_reactions r where r.activity_id = a.id),
         (select count(*) from public.activity_comments cm
           where cm.activity_id = a.id
             and cm.user_id not in (select blocked from public.blocked_users
                                     where blocker = auth.uid())),
         (select r.emoji from public.activity_reactions r
           where r.activity_id = a.id and r.user_id = auth.uid()),
         (select array_agg(e.emoji order by e.n desc)
            from (select r.emoji, count(*) as n
                    from public.activity_reactions r
                   where r.activity_id = a.id
                   group by r.emoji
                   order by count(*) desc
                   limit 3) e)
  from public.activities a
  join public.profiles p on p.id = a.actor_id
  join public.courses c on c.id = a.course_id
  left join public.user_course_scores s
    on a.kind = 'ranked' and s.user_id = a.actor_id and s.course_id = a.course_id
  where a.id = p_activity_id
    and a.actor_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid());
$$;
