-- Slack-style reactions, and tagging people in activities and comments.
--
-- Reactions were one-per-person (picking a second emoji swapped the first).
-- Slack's model is the opposite: each emoji is its own chip with a count, you
-- can add as many as you like, and tapping a chip toggles your own presence in
-- it. That means the primary key gains `emoji`.
--
-- Both activity_feed() and activity() embed the reaction subqueries, so BOTH
-- have to be rebuilt here — from their 00180 bodies, which carry the
-- blocked-user filtering.

alter table public.activity_reactions
  drop constraint activity_reactions_pkey;
alter table public.activity_reactions
  add primary key (activity_id, user_id, emoji);

-- Same signature, so create-or-replace is safe (no overload trap). The body
-- becomes a plain per-emoji toggle rather than a three-way swap.
create or replace function public.toggle_reaction(p_activity_id bigint, p_emoji text)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if exists (
    select 1 from public.activity_reactions
     where activity_id = p_activity_id and user_id = auth.uid() and emoji = p_emoji
  ) then
    delete from public.activity_reactions
     where activity_id = p_activity_id and user_id = auth.uid() and emoji = p_emoji;
  else
    insert into public.activity_reactions (activity_id, user_id, emoji)
    values (p_activity_id, auth.uid(), p_emoji);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tagging
-- ---------------------------------------------------------------------------

create table public.activity_tags (
  activity_id bigint not null references public.activities on delete cascade,
  user_id     uuid   not null references public.profiles on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (activity_id, user_id)
);

create index activity_tags_user_idx on public.activity_tags (user_id);

alter table public.activity_tags enable row level security;

create policy "activity_tags_select" on public.activity_tags
  for select to authenticated using (true);

grant select on public.activity_tags to authenticated;

-- 'tag' = named as a playing partner on an activity.
-- 'mention' = @named inside a comment.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (kind in ('follow', 'comment', 'reaction', 'tag', 'mention'));

-- Replace the tags on your own activity.
--
-- Tagging is restricted to people you follow. Without that, anyone could
-- attach any stranger to any round — a spam and harassment vector, and one
-- App Review would reasonably object to.
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
    perform public.notify(v_added, v_user, 'tag', p_activity_id);
  end loop;
end;
$$;

-- Rebuilt from 00180 with @mention notifications. The activity owner already
-- gets a 'comment' notification, so they're excluded from the mention sweep to
-- avoid pinging the same person twice for one comment.
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
    from regexp_matches(p_body, '@([A-Za-z0-9_]{3,20})', 'g') as m
  loop
    select id into v_target from public.profiles
     where lower(username) = lower(v_mention);
    if v_target is not null and v_target is distinct from v_owner then
      perform public.notify(v_target, auth.uid(), 'mention', p_activity_id, v_id);
    end if;
  end loop;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Read APIs, rebuilt for the new reaction shape
-- ---------------------------------------------------------------------------

-- One emoji chip per row: {emoji, count, mine}, busiest first. Factored out
-- because activity_feed() and activity() both need it and previously carried
-- duplicate copies of the same subqueries — which is exactly how two functions
-- drift apart.
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
    group by r.emoji
  ) e;
$$;

-- `reactions` is a jsonb array of {emoji, count, mine}: a text[] of top emoji
-- can't say which ones *you* are in, and highlighting your own chips is the
-- entire point of the Slack model. my_reaction/top_emojis are gone.
drop function if exists public.activity_feed();
drop function if exists public.activity(bigint);

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
  reactions jsonb,
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
         (select count(*) from public.activity_reactions r where r.activity_id = a.id),
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
  reactions jsonb,
  tagged_usernames text[]
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
