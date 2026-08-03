-- Fixes from the post-feature review.

-- 1. toggle_reaction was check-then-act: two concurrent taps on the same emoji
-- could both see "not present" and both insert, so one would fail the primary
-- key and surface an error for a reaction that did in fact save. DELETE first
-- and use FOUND — one statement decides, and the insert is conflict-tolerant.
create or replace function public.toggle_reaction(p_activity_id bigint, p_emoji text)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  delete from public.activity_reactions
   where activity_id = p_activity_id and user_id = auth.uid() and emoji = p_emoji;

  if not found then
    insert into public.activity_reactions (activity_id, user_id, emoji)
    values (p_activity_id, auth.uid(), p_emoji)
    on conflict do nothing;
  end if;
end;
$$;

-- 2. Blocked users' reactions were still counted and still drew a chip on your
-- round. Comments, photos and the notification list all filter blocked users;
-- reactions were the one surface that didn't.
create or replace function public.reaction_summary(p_activity_id bigint)
returns jsonb
language sql stable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('emoji', e.emoji, 'count', e.n, 'mine', e.mine)
      order by e.n desc, e.emoji
    ),
    '[]'::jsonb
  )
  from (
    select r.emoji,
           count(*) as n,
           bool_or(r.user_id = auth.uid()) as mine
    from public.activity_reactions r
    where r.activity_id = p_activity_id
      and r.user_id not in (select blocked from public.blocked_users
                             where blocker = auth.uid())
    group by r.emoji
  ) e;
$$;

-- Same filter for the total, so the number matches the chips beside it.
create or replace function public.reaction_total(p_activity_id bigint)
returns bigint
language sql stable
set search_path = ''
as $$
  select count(*)
  from public.activity_reactions r
  where r.activity_id = p_activity_id
    and r.user_id not in (select blocked from public.blocked_users
                           where blocker = auth.uid());
$$;

-- 3. The unread badge counted alerts the list itself hides, so a blocked
-- actor's engagement made the badge disagree with the screen.
create or replace function public.unread_notification_count()
returns int
language sql stable
set search_path = ''
as $$
  select count(*)::int from public.notifications n
   where n.user_id = auth.uid()
     and n.read_at is null
     and n.actor_id not in (select blocked from public.blocked_users
                             where blocker = auth.uid());
$$;

-- 4. @mention matching had no word boundaries, so "email me@example.com"
-- notified a user called `example`, and "@bobby5" silently resolved to nobody
-- rather than matching @bobby. Anchor both ends, and cap how many mentions one
-- comment can fire so a 500-character comment can't spray notifications.
create or replace function public.add_comment(p_activity_id bigint, p_body text)
returns bigint
language plpgsql security definer
set search_path = ''
as $$
declare
  v_id      bigint;
  v_owner   uuid;
  v_mention text;
  v_target  uuid;
  v_sent    int := 0;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  insert into public.activity_comments (activity_id, user_id, body)
  values (p_activity_id, auth.uid(), p_body)
  returning id into v_id;

  select actor_id into v_owner from public.activities where id = p_activity_id;

  for v_mention in
    select distinct m[1]
    from regexp_matches(
           p_body,
           '(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_]{3,20})(?![A-Za-z0-9_])',
           'g'
         ) as m
  loop
    exit when v_sent >= 10;
    select id into v_target from public.profiles
     where lower(username) = lower(v_mention);
    if v_target is not null and v_target is distinct from v_owner then
      perform public.notify(v_target, auth.uid(), 'mention', p_activity_id, v_id);
      v_sent := v_sent + 1;
    end if;
  end loop;

  return v_id;
end;
$$;

-- 5. Re-opening the tag sheet and pressing Done again re-notified everyone,
-- because the function deleted all tags and notified every id it re-inserted.
-- Only genuinely new tags should ping.
create or replace function public.set_activity_tags(
  p_activity_id bigint, p_user_ids uuid[]
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_added uuid;
  v_prior uuid[];
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.activities
     where id = p_activity_id and actor_id = v_user
  ) then
    raise exception 'not your activity';
  end if;

  select coalesce(array_agg(user_id), '{}'::uuid[]) into v_prior
    from public.activity_tags where activity_id = p_activity_id;

  delete from public.activity_tags where activity_id = p_activity_id;

  for v_added in
    select u
    from unnest(coalesce(p_user_ids, '{}'::uuid[])) as u
    where u <> v_user
      and exists (select 1 from public.follows
                   where follower_id = v_user and followee_id = u)
  loop
    insert into public.activity_tags (activity_id, user_id)
    values (p_activity_id, v_added)
    on conflict do nothing;
    -- Only ping people who weren't already on this round.
    if not (v_added = any (v_prior)) then
      perform public.notify(v_added, v_user, 'tag', p_activity_id);
    end if;
  end loop;
end;
$$;

-- Rebuild the two feed readers so reaction counts use the filtered total.
-- (Bodies otherwise identical to 00200 — including the blocked-user filtering
-- that both already carried.)
drop function if exists public.activity_feed();
drop function if exists public.activity(bigint);

create or replace function public.activity_feed()
returns table (
  activity_id bigint, kind text, actor_id uuid, username text,
  course_id bigint, course_name text, city text, state text,
  score numeric, bucket public.bucket, created_at timestamptz,
  reaction_count bigint, comment_count bigint, reactions jsonb,
  tagged_usernames text[]
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
         public.reaction_total(a.id),
         (select count(*) from public.activity_comments cm
           where cm.activity_id = a.id
             and cm.user_id not in (select blocked from public.blocked_users
                                     where blocker = auth.uid())),
         public.reaction_summary(a.id),
         (select array_agg(tp.username order by tp.username)
            from public.activity_tags t
            join public.profiles tp on tp.id = t.user_id
           where t.activity_id = a.id)
  from public.activities a
  join public.profiles p on p.id = a.actor_id
  join public.courses c on c.id = a.course_id
  left join public.user_course_scores s
    on a.kind = 'ranked' and s.user_id = a.actor_id and s.course_id = a.course_id
  where a.actor_id in (select uid from visible)
  order by a.created_at desc
  limit 60;
$$;

create or replace function public.activity(p_activity_id bigint)
returns table (
  activity_id bigint, kind text, actor_id uuid, username text,
  course_id bigint, course_name text, city text, state text,
  score numeric, bucket public.bucket, created_at timestamptz,
  reaction_count bigint, comment_count bigint, reactions jsonb,
  tagged_usernames text[]
)
language sql stable
set search_path = ''
as $$
  select a.id, a.kind, a.actor_id, p.username, a.course_id, c.name, c.city, c.state,
         s.score, s.bucket, a.created_at,
         public.reaction_total(a.id),
         (select count(*) from public.activity_comments cm
           where cm.activity_id = a.id
             and cm.user_id not in (select blocked from public.blocked_users
                                     where blocker = auth.uid())),
         public.reaction_summary(a.id),
         (select array_agg(tp.username order by tp.username)
            from public.activity_tags t
            join public.profiles tp on tp.id = t.user_id
           where t.activity_id = a.id)
  from public.activities a
  join public.profiles p on p.id = a.actor_id
  join public.courses c on c.id = a.course_id
  left join public.user_course_scores s
    on a.kind = 'ranked' and s.user_id = a.actor_id and s.course_id = a.course_id
  where a.id = p_activity_id
    and a.actor_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid());
$$;
