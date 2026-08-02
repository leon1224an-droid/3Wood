-- Course photos.
--
-- Files live in Storage; this table is the index the app reads, so a photo can
-- be listed, attributed and reported without touching the bucket. Paths are
-- `{user_id}/{course_id}/{uuid}.jpg` and the storage policies key off that
-- first path segment, which is what stops one user writing into another's
-- folder.
--
-- Photos are user-generated content, so they carry the same report path as
-- reviews and comments (App Store 1.2). The app downscales and re-encodes
-- before upload, which also drops EXIF — location metadata must not ride along
-- with a photo of a course.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'course-photos', 'course-photos', true,
  5242880,  -- 5 MB; the client targets far less than this after downscaling
  array['image/jpeg', 'image/png']
)
on conflict (id) do nothing;

-- Public bucket still needs policies for authenticated writes.
create policy "course_photos_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'course-photos');

create policy "course_photos_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'course-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "course_photos_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'course-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create table public.course_photos (
  id           bigint generated always as identity primary key,
  course_id    bigint not null references public.courses on delete cascade,
  user_id      uuid   not null default auth.uid() references public.profiles on delete cascade,
  storage_path text   not null unique,
  created_at   timestamptz not null default now()
);

create index course_photos_course_idx on public.course_photos (course_id, created_at desc);

alter table public.course_photos enable row level security;

create policy "course_photos_select" on public.course_photos
  for select to authenticated using (true);
create policy "course_photos_write_own" on public.course_photos
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.course_photos to authenticated;

alter table public.reports add column photo_id bigint references public.course_photos on delete cascade;

-- A course's photos, newest first, with blocked uploaders filtered out.
create or replace function public.course_photos(p_course_id bigint)
returns table (
  id bigint,
  user_id uuid,
  username text,
  storage_path text,
  created_at timestamptz,
  is_mine boolean
)
language sql stable
set search_path = ''
as $$
  select ph.id, ph.user_id, p.username, ph.storage_path, ph.created_at,
         ph.user_id = auth.uid()
  from public.course_photos ph
  join public.profiles p on p.id = ph.user_id
  where ph.course_id = p_course_id
    and ph.user_id not in (select blocked from public.blocked_users
                            where blocker = auth.uid())
  order by ph.created_at desc
  limit 50;
$$;
