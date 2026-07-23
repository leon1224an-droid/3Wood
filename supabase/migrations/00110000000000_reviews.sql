-- Optional user-written reviews: one editable review per user per course.
create table public.reviews (
  id         bigint generated always as identity primary key,
  user_id    uuid   not null references public.profiles on delete cascade,
  course_id  bigint not null references public.courses on delete cascade,
  body       text   not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, course_id)
);
create index reviews_course_idx on public.reviews (course_id, created_at desc);

alter table public.reviews enable row level security;

-- Public read (reviews are compiled on the course page); own-row writes.
create policy "reviews_select" on public.reviews
  for select to authenticated using (true);
create policy "reviews_write_own" on public.reviews
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.reviews to authenticated;

-- Reviews for a course, the caller's own first, then newest.
create or replace function public.course_reviews(p_course_id bigint)
returns table (
  id bigint, user_id uuid, username text, body text,
  created_at timestamptz, is_mine boolean
)
language sql stable
set search_path = ''
as $$
  select r.id, r.user_id, p.username, r.body, r.created_at,
         r.user_id = auth.uid()
  from public.reviews r
  join public.profiles p on p.id = r.user_id
  where r.course_id = p_course_id
  order by (r.user_id = auth.uid()) desc, r.created_at desc;
$$;

-- Create or edit the caller's review for a course.
create or replace function public.upsert_review(p_course_id bigint, p_body text)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  insert into public.reviews (user_id, course_id, body)
  values (auth.uid(), p_course_id, p_body)
  on conflict (user_id, course_id)
  do update set body = excluded.body, updated_at = now();
end;
$$;

create or replace function public.delete_review(p_course_id bigint)
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.reviews where user_id = auth.uid() and course_id = p_course_id;
$$;
