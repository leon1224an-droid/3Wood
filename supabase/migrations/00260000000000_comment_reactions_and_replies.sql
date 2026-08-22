-- Reactions on comments, and one level of replies — on BOTH activity_comments
-- and list_comments, kept in lockstep on purpose. The two tables have been
-- byte-identical in shape since 00230000000000_custom_lists.sql specifically
-- so the client's ActivityComment model could decode either RPC unchanged;
-- diverging them here (e.g. replies on lists only) would break that
-- assumption for whoever touches activity comments next. One level deep
-- only — a reply can't itself be replied to — matches the same
-- don't-over-build spirit as list_items having no manual position.

alter table public.activity_comments
  add column parent_comment_id bigint references public.activity_comments on delete cascade;
alter table public.list_comments
  add column parent_comment_id bigint references public.list_comments on delete cascade;

create index activity_comments_parent_idx on public.activity_comments (parent_comment_id)
  where parent_comment_id is not null;
create index list_comments_parent_idx on public.list_comments (parent_comment_id)
  where parent_comment_id is not null;

-- ---------------------------------------------------------------------------
-- Reaction tables — same 3-column PK shape activity_reactions was widened to
-- in 00200000000000 (activity_id/user_id/emoji -> here comment_id/user_id/
-- emoji), so a user can hold several emoji on one comment at once, each
-- toggled independently. Two separate tables, not one polymorphic one,
-- matching the existing list_likes-vs-activity_reactions precedent — this
-- codebase gives every engagement surface its own table rather than a shared
-- one with a discriminator column.
-- ---------------------------------------------------------------------------

create table public.activity_comment_reactions (
  comment_id bigint not null references public.activity_comments on delete cascade,
  user_id    uuid   not null default auth.uid() references public.profiles on delete cascade,
  emoji      text   not null,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id, emoji)
);

create index activity_comment_reactions_comment_idx on public.activity_comment_reactions (comment_id);

alter table public.activity_comment_reactions enable row level security;

-- Matches activity_comments' own "comments_select ... using (true)" — a
-- comment's reactions are exactly as visible as the comment itself.
create policy "activity_comment_reactions_select" on public.activity_comment_reactions
  for select to authenticated using (true);
create policy "activity_comment_reactions_write_own" on public.activity_comment_reactions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.activity_comment_reactions to authenticated;

create table public.list_comment_reactions (
  comment_id bigint not null references public.list_comments on delete cascade,
  user_id    uuid   not null default auth.uid() references public.profiles on delete cascade,
  emoji      text   not null,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id, emoji)
);

create index list_comment_reactions_comment_idx on public.list_comment_reactions (comment_id);

alter table public.list_comment_reactions enable row level security;

create policy "list_comment_reactions_select" on public.list_comment_reactions
  for select to authenticated using (
    exists (select 1 from public.list_comments cm
             join public.lists l on l.id = cm.list_id
            where cm.id = comment_id and (l.owner_id = auth.uid() or l.visibility = 'public'))
  );
create policy "list_comment_reactions_write_own" on public.list_comment_reactions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.list_comment_reactions to authenticated;

-- ---------------------------------------------------------------------------
-- Toggle RPCs — same race-safe delete-then-insert shape as toggle_reaction
-- (00210000000000_review_fixes.sql).
-- ---------------------------------------------------------------------------

create or replace function public.toggle_activity_comment_reaction(p_comment_id bigint, p_emoji text)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from public.activity_comment_reactions
   where comment_id = p_comment_id and user_id = auth.uid() and emoji = p_emoji;
  if not found then
    insert into public.activity_comment_reactions (comment_id, user_id, emoji)
    values (p_comment_id, auth.uid(), p_emoji)
    on conflict do nothing;
  end if;
end;
$$;

create or replace function public.toggle_list_comment_reaction(p_comment_id bigint, p_emoji text)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not exists (select 1 from public.list_comments cm
                   join public.lists l on l.id = cm.list_id
                  where cm.id = p_comment_id and (l.owner_id = auth.uid() or l.visibility = 'public')) then
    raise exception 'comment not found';
  end if;
  delete from public.list_comment_reactions
   where comment_id = p_comment_id and user_id = auth.uid() and emoji = p_emoji;
  if not found then
    insert into public.list_comment_reactions (comment_id, user_id, emoji)
    values (p_comment_id, auth.uid(), p_emoji)
    on conflict do nothing;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Replies — add_comment/add_list_comment gain a trailing defaulted param.
-- Same overload trap as remove_ranking/notify before: CREATE OR REPLACE
-- matches on the declared parameter list, so adding one here without
-- dropping the 2-arg version first would leave both coexisting and make any
-- 2-arg call ambiguous. Drop first.
-- ---------------------------------------------------------------------------

drop function if exists public.add_comment(bigint, text);
create or replace function public.add_comment(
  p_activity_id bigint, p_body text, p_parent_comment_id bigint default null
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
  if p_parent_comment_id is not null and not exists (
    select 1 from public.activity_comments
     where id = p_parent_comment_id and activity_id = p_activity_id
  ) then
    raise exception 'parent comment not found';
  end if;
  insert into public.activity_comments (activity_id, user_id, body, parent_comment_id)
  values (p_activity_id, auth.uid(), p_body, p_parent_comment_id)
  returning id into v_id;
  return v_id;
end;
$$;

drop function if exists public.add_list_comment(bigint, text);
create or replace function public.add_list_comment(
  p_list_id bigint, p_body text, p_parent_comment_id bigint default null
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
  if not exists (select 1 from public.lists l
                   where l.id = p_list_id and (l.owner_id = auth.uid() or l.visibility = 'public')) then
    raise exception 'list not found';
  end if;
  if p_parent_comment_id is not null and not exists (
    select 1 from public.list_comments where id = p_parent_comment_id and list_id = p_list_id
  ) then
    raise exception 'parent comment not found';
  end if;
  insert into public.list_comments (list_id, user_id, body, parent_comment_id)
  values (p_list_id, auth.uid(), p_body, p_parent_comment_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Read RPCs — gain parent_comment_id and a per-comment reaction summary
-- (same {emoji,count,mine} shape reaction_summary() already returns for
-- activities, so the client's ReactionSummary struct decodes it unchanged).
-- Still byte-identical between the two functions.
-- ---------------------------------------------------------------------------

drop function if exists public.activity_comments(bigint);
create or replace function public.activity_comments(p_activity_id bigint)
returns table (
  id bigint, user_id uuid, username text, body text, created_at timestamptz,
  is_mine boolean, parent_comment_id bigint, reactions jsonb
)
language sql stable
set search_path = ''
as $$
  select cm.id, cm.user_id, p.username, cm.body, cm.created_at,
         cm.user_id = auth.uid(), cm.parent_comment_id,
         coalesce((
           select jsonb_agg(jsonb_build_object('emoji', r.emoji, 'count', r.cnt, 'mine', r.mine)
                             order by r.emoji)
           from (
             select emoji, count(*) as cnt, bool_or(user_id = auth.uid()) as mine
             from public.activity_comment_reactions
             where comment_id = cm.id
             group by emoji
           ) r
         ), '[]'::jsonb)
  from public.activity_comments cm
  join public.profiles p on p.id = cm.user_id
  where cm.activity_id = p_activity_id
    and cm.user_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid())
  order by cm.created_at;
$$;

drop function if exists public.list_comments(bigint);
create or replace function public.list_comments(p_list_id bigint)
returns table (
  id bigint, user_id uuid, username text, body text, created_at timestamptz,
  is_mine boolean, parent_comment_id bigint, reactions jsonb
)
language sql stable
set search_path = ''
as $$
  select cm.id, cm.user_id, p.username, cm.body, cm.created_at,
         cm.user_id = auth.uid(), cm.parent_comment_id,
         coalesce((
           select jsonb_agg(jsonb_build_object('emoji', r.emoji, 'count', r.cnt, 'mine', r.mine)
                             order by r.emoji)
           from (
             select emoji, count(*) as cnt, bool_or(user_id = auth.uid()) as mine
             from public.list_comment_reactions
             where comment_id = cm.id
             group by emoji
           ) r
         ), '[]'::jsonb)
  from public.list_comments cm
  join public.profiles p on p.id = cm.user_id
  join public.lists l on l.id = cm.list_id
  where cm.list_id = p_list_id
    and (l.owner_id = auth.uid() or l.visibility = 'public')
    and cm.user_id not in (select blocked from public.blocked_users where blocker = auth.uid())
  order by cm.created_at;
$$;

-- ---------------------------------------------------------------------------
-- Notifications — 'comment_reply' notifies the PARENT COMMENT's author (not
-- necessarily the activity/list owner — that's who the existing
-- 'comment'/'list_comment' notification already covers, and still fires
-- unconditionally below, reply or not). 'comment_reaction' notifies the
-- reacted-to comment's author. Both reuse notify()'s existing params
-- (p_comment/p_list_comment already exist for exactly this purpose, p_emoji
-- already exists for 'reaction') — no notify()/notifications() signature
-- change needed, only the kind check constraint widens.
-- ---------------------------------------------------------------------------

create or replace function public.notify_on_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
  v_parent_author uuid;
begin
  select actor_id into v_owner from public.activities where id = new.activity_id;
  perform public.notify(v_owner, new.user_id, 'comment', new.activity_id, new.id);
  if new.parent_comment_id is not null then
    select user_id into v_parent_author from public.activity_comments where id = new.parent_comment_id;
    perform public.notify(v_parent_author, new.user_id, 'comment_reply', new.activity_id, new.id);
  end if;
  return new;
end;
$$;

create or replace function public.notify_on_list_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
  v_parent_author uuid;
begin
  select owner_id into v_owner from public.lists where id = new.list_id;
  perform public.notify(v_owner, new.user_id, 'list_comment', null, null, null, new.list_id, new.id);
  if new.parent_comment_id is not null then
    select user_id into v_parent_author from public.list_comments where id = new.parent_comment_id;
    perform public.notify(v_parent_author, new.user_id, 'comment_reply', null, null, null, new.list_id, new.id);
  end if;
  return new;
end;
$$;

create or replace function public.notify_on_activity_comment_reaction()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_author uuid;
  v_activity bigint;
begin
  select user_id, activity_id into v_author, v_activity
    from public.activity_comments where id = new.comment_id;
  perform public.notify(v_author, new.user_id, 'comment_reaction', v_activity, new.comment_id, new.emoji);
  return new;
end;
$$;

create trigger activity_comment_reactions_notify after insert on public.activity_comment_reactions
  for each row execute function public.notify_on_activity_comment_reaction();

create or replace function public.notify_on_list_comment_reaction()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_author uuid;
  v_list bigint;
begin
  select user_id, list_id into v_author, v_list
    from public.list_comments where id = new.comment_id;
  perform public.notify(v_author, new.user_id, 'comment_reaction', null, null, new.emoji, v_list, new.comment_id);
  return new;
end;
$$;

create trigger list_comment_reactions_notify after insert on public.list_comment_reactions
  for each row execute function public.notify_on_list_comment_reaction();

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (kind in (
    'follow', 'comment', 'reaction', 'tag', 'mention',
    'list_bookmark', 'list_comment', 'comment_reply', 'comment_reaction'
  ));
