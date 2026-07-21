-- US golf courses. Seeded by scripts/seed_courses.py with the service role;
-- clients are read-only (no insert/update/delete policies — RLS blocks them).
create table public.courses (
  id          bigint generated always as identity primary key,
  external_id text unique not null,  -- source-dataset id, for idempotent re-seeding
  name        text not null,
  city        text,
  state       text,                  -- 2-letter code
  address     text,
  latitude    double precision not null,
  longitude   double precision not null,
  geom        extensions.geography(point, 4326) generated always as
                (extensions.st_setsrid(
                   extensions.st_makepoint(longitude, latitude), 4326
                 )::extensions.geography) stored,
  holes       int,
  course_type text,                  -- public / private / resort / municipal…
  website     text,
  phone       text
);

create index courses_geom_idx  on public.courses using gist (geom);
create index courses_name_trgm on public.courses using gin (name extensions.gin_trgm_ops);
create index courses_state_idx on public.courses (state, city);

alter table public.courses enable row level security;

grant select on public.courses to authenticated;

create policy "courses_select" on public.courses
  for select to authenticated using (true);

-- Fuzzy name/city search. avg_score/rating_count are placeholders until the
-- rankings migration (M4) replaces these functions with real community ratings.
create or replace function public.search_courses(p_query text)
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
         null::numeric as avg_score, 0::bigint as rating_count
  from public.courses c
  where c.name ilike '%' || p_query || '%'
     or extensions.similarity(c.name, p_query) > 0.25
     or (c.city || ', ' || c.state) ilike '%' || p_query || '%'
  order by extensions.similarity(c.name, p_query) desc, c.name
  limit 25;
$$;

-- Map viewport query (bounding box), capped so wide zooms stay cheap.
create or replace function public.courses_in_region(
  min_lat double precision, min_lng double precision,
  max_lat double precision, max_lng double precision
)
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
         null::numeric as avg_score, 0::bigint as rating_count
  from public.courses c
  where extensions.st_intersects(
          c.geom,
          extensions.st_makeenvelope(min_lng, min_lat, max_lng, max_lat, 4326)::extensions.geography
        )
  limit 250;
$$;
