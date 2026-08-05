-- Dev fixture data, applied automatically by `supabase db reset`.
-- ~15 well-known US courses so search/map are demoable before the full
-- ~16k-course import (scripts/seed_courses.py).
insert into public.courses
  (external_id, name, city, state, latitude, longitude, holes, course_type)
values
  ('seed:pebble-beach',      'Pebble Beach Golf Links',            'Pebble Beach',      'CA', 36.5674, -121.9500, 18, 'resort'),
  ('seed:bethpage-black',    'Bethpage State Park (Black Course)', 'Farmingdale',       'NY', 40.7351,  -73.4547, 18, 'public'),
  ('seed:pinehurst-2',       'Pinehurst No. 2',                    'Pinehurst',         'NC', 35.1884,  -79.4672, 18, 'resort'),
  ('seed:torrey-south',      'Torrey Pines (South Course)',        'La Jolla',          'CA', 32.8933, -117.2530, 18, 'municipal'),
  ('seed:whistling-straits', 'Whistling Straits (Straits Course)', 'Sheboygan',         'WI', 43.8511,  -87.7340, 18, 'resort'),
  ('seed:kiawah-ocean',      'Kiawah Island (Ocean Course)',       'Kiawah Island',     'SC', 32.6088,  -80.0393, 18, 'resort'),
  ('seed:chambers-bay',      'Chambers Bay',                       'University Place',  'WA', 47.2004, -122.5716, 18, 'municipal'),
  ('seed:erin-hills',        'Erin Hills',                         'Erin',              'WI', 43.2494,  -88.3610, 18, 'public'),
  ('seed:tpc-sawgrass',      'TPC Sawgrass (Players Stadium)',     'Ponte Vedra Beach', 'FL', 30.1975,  -81.3959, 18, 'resort'),
  ('seed:bandon-dunes',      'Bandon Dunes',                       'Bandon',            'OR', 43.1857, -124.3891, 18, 'resort'),
  ('seed:shinnecock',        'Shinnecock Hills Golf Club',         'Southampton',       'NY', 40.8915,  -72.4432, 18, 'private'),
  ('seed:oakmont',           'Oakmont Country Club',               'Oakmont',           'PA', 40.5261,  -79.8280, 18, 'private'),
  ('seed:augusta',           'Augusta National Golf Club',         'Augusta',           'GA', 33.5021,  -82.0226, 18, 'private'),
  ('seed:harbour-town',      'Harbour Town Golf Links',            'Hilton Head Island','SC', 32.1387,  -80.8042, 18, 'resort'),
  ('seed:bay-hill',          'Bay Hill Club & Lodge',              'Orlando',           'FL', 28.4634,  -81.5064, 18, 'private'),
  -- testLogCourseFlow logs "Spyglass"; keeping it here means the UI suite
  -- passes on seed data alone, without the full OpenGolfAPI import.
  ('seed:spyglass-hill',     'Spyglass Hill Golf Course',          'Pebble Beach',      'CA', 36.5847, -121.9539, 18, 'resort')
on conflict (external_id) do nothing;

-- ---------------------------------------------------------------------------
-- Dev fixture accounts.
--
-- These used to exist only in whoever's local database happened to have them,
-- created by hand through the app — so `supabase db reset` silently destroyed
-- the accounts the UI tests and LiveBackendTests sign in as. Defining them here
-- makes a reset reproducible instead of destructive.
--
-- All accounts use the password `testpass123`. Local stack only: seed.sql is
-- never applied to the hosted project.
--
-- first_ranked_at is deliberately spread across recent weeks so the weekly
-- leaderboard and the week-streak have something real to show.
-- ---------------------------------------------------------------------------

-- confirmation_token / recovery_token / email_change_token_new / email_change
-- are nullable with no default, but GoTrue scans them into non-nullable Go
-- strings — leaving them NULL makes every sign-in fail with
-- "Database error querying schema". They must be empty strings, not NULL.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
  u.email, extensions.crypt('testpass123', extensions.gen_salt('bf')),
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  '', '', '', ''
from (values
  ('11111111-1111-1111-1111-111111111111'::uuid, 'birdie_ben@example.com'),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'mulligan_mike@example.com'),
  ('33333333-3333-3333-3333-333333333333'::uuid, 'test1@example.com'),
  ('44444444-4444-4444-4444-444444444444'::uuid, 'fairway_fiona@example.com'),
  ('55555555-5555-5555-5555-555555555555'::uuid, 'chip_charlie@example.com'),
  ('66666666-6666-6666-6666-666666666666'::uuid, 'putt_pete@example.com')
) as u(id, email)
on conflict (id) do nothing;

-- GoTrue needs a matching identity row or password sign-in fails.
insert into auth.identities (
  provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
select
  u.id::text, u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
from auth.users u
where u.email like '%@example.com'
on conflict (provider_id, provider) do nothing;

insert into public.profiles (id, username, display_name)
values
  ('11111111-1111-1111-1111-111111111111', 'birdie_ben',    'Ben'),
  ('22222222-2222-2222-2222-222222222222', 'mulligan_mike', 'Mike'),
  ('33333333-3333-3333-3333-333333333333', 'test1',         null),
  ('44444444-4444-4444-4444-444444444444', 'fairway_fiona', 'Fiona'),
  ('55555555-5555-5555-5555-555555555555', 'chip_charlie',  'Charlie'),
  ('66666666-6666-6666-6666-666666666666', 'putt_pete',     'Pete')
on conflict (id) do nothing;

-- birdie_ben follows four people; three of them follow back.
insert into public.follows (follower_id, followee_id)
values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444'),
  ('11111111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555'),
  ('11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111')
on conflict do nothing;

-- Rankings. rank_position must be contiguous within (user, bucket).
insert into public.user_course_rankings
  (user_id, course_id, bucket, rank_position, created_at, first_ranked_at)
select f.user_id, c.id, f.bucket::public.bucket, f.pos,
       now() - (f.weeks_ago || ' weeks')::interval,
       now() - (f.weeks_ago || ' weeks')::interval
from (values
  -- birdie_ben: an unbroken run of the last four weeks (streak = 4).
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:pebble-beach',      'liked',    1, 0),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:pinehurst-2',       'liked',    2, 1),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:bandon-dunes',      'liked',    3, 2),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:augusta',           'liked',    4, 3),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:bethpage-black',    'fine',     1, 1),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:torrey-south',      'fine',     2, 3),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:chambers-bay',      'fine',     3, 6),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'seed:bay-hill',          'disliked', 1, 8),
  -- mulligan_mike: has Pebble Beach so the other-profile course tap works.
  ('22222222-2222-2222-2222-222222222222'::uuid, 'seed:pebble-beach',      'liked',    1, 0),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'seed:kiawah-ocean',      'liked',    2, 2),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'seed:erin-hills',        'fine',     1, 5),
  -- test1: LiveBackendTests asserts Pebble Beach carries a community rating.
  ('33333333-3333-3333-3333-333333333333'::uuid, 'seed:pebble-beach',      'liked',    1, 1),
  ('33333333-3333-3333-3333-333333333333'::uuid, 'seed:oakmont',           'fine',     1, 4),
  -- Enough others to make the leaderboard interesting, weekly and all-time.
  ('44444444-4444-4444-4444-444444444444'::uuid, 'seed:whistling-straits', 'liked',    1, 0),
  ('44444444-4444-4444-4444-444444444444'::uuid, 'seed:shinnecock',        'liked',    2, 0),
  ('44444444-4444-4444-4444-444444444444'::uuid, 'seed:tpc-sawgrass',      'fine',     1, 3),
  ('55555555-5555-5555-5555-555555555555'::uuid, 'seed:harbour-town',      'liked',    1, 0),
  ('55555555-5555-5555-5555-555555555555'::uuid, 'seed:kiawah-ocean',      'fine',     1, 7),
  ('66666666-6666-6666-6666-666666666666'::uuid, 'seed:oakmont',           'liked',    1, 9)
) as f(user_id, ext, bucket, pos, weeks_ago)
join public.courses c on c.external_id = f.ext
on conflict (user_id, course_id) do nothing;

insert into public.want_to_play (user_id, course_id)
select '11111111-1111-1111-1111-111111111111'::uuid, c.id
from public.courses c
where c.external_id in (
  'seed:whistling-straits', 'seed:tpc-sawgrass', 'seed:shinnecock',
  'seed:oakmont', 'seed:harbour-town'
)
on conflict do nothing;

-- testReviews looks for a review mentioning "back nine" on Pebble Beach.
insert into public.reviews (user_id, course_id, body)
select r.user_id, c.id, r.body
from (values
  ('22222222-2222-2222-2222-222222222222'::uuid, 'seed:pebble-beach',
   'Worth every penny. The back nine along the cliffs is unreal — 7 and 8 especially.'),
  ('44444444-4444-4444-4444-444444444444'::uuid, 'seed:pebble-beach',
   'Windy the day I played, but the views make up for the scorecard.'),
  ('55555555-5555-5555-5555-555555555555'::uuid, 'seed:augusta',
   'Once in a lifetime. Faster greens than anything I have putted on.')
) as r(user_id, ext, body)
join public.courses c on c.external_id = r.ext;

-- Activities for the seeded rankings. Migrations run before this file, so the
-- backfill in 00180 saw an empty table; and rankings deliberately have no
-- trigger (insert_ranking manages activities explicitly, because a delete
-- trigger would drop the activity — and its comments — on every re-rank).
-- want_to_play rows do have triggers, so those activities already exist.
insert into public.activities (actor_id, kind, course_id, created_at)
select user_id, 'ranked', course_id, created_at
from public.user_course_rankings
on conflict do nothing;

-- Reactions and comments on Ben's activities, so the feed has engagement to
-- render and his notification inbox isn't empty. The notify triggers fire on
-- these inserts, which is exactly how the alert feed gets its fixtures.
insert into public.activity_reactions (activity_id, user_id, emoji)
select a.id, u.uid, u.emoji
from public.activities a
join public.courses c on c.id = a.course_id
join (values
  ('22222222-2222-2222-2222-222222222222'::uuid, 'Pebble Beach Golf Links', '🔥'),
  ('55555555-5555-5555-5555-555555555555'::uuid, 'Pebble Beach Golf Links', '🦅'),
  ('44444444-4444-4444-4444-444444444444'::uuid, 'Pinehurst No. 2',         '⛳')
) as u(uid, course_name, emoji) on c.name = u.course_name
where a.actor_id = '11111111-1111-1111-1111-111111111111' and a.kind = 'ranked'
on conflict do nothing;

insert into public.activity_comments (activity_id, user_id, body)
select a.id, u.uid, u.body
from public.activities a
join public.courses c on c.id = a.course_id
join (values
  ('44444444-4444-4444-4444-444444444444'::uuid, 'Pebble Beach Golf Links',
   'Still jealous. How was 7 playing?'),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'Pebble Beach Golf Links',
   'Told you it was worth the green fee.')
) as u(uid, course_name, body) on c.name = u.course_name
where a.actor_id = '11111111-1111-1111-1111-111111111111' and a.kind = 'ranked';

-- One round per seeded ranking. The 00220 backfill runs at migration time,
-- before this file exists, so fixtures need their own copy — same reason the
-- activities backfill is repeated here.
insert into public.course_visits (user_id, course_id, played_on)
select user_id, course_id, first_ranked_at::date
from public.user_course_rankings
on conflict do nothing;

-- Ben has played Pebble twice, so the visit history has something to show.
insert into public.course_visits (user_id, course_id, played_on)
select '11111111-1111-1111-1111-111111111111', c.id, (now() - interval '9 months')::date
from public.courses c where c.name = 'Pebble Beach Golf Links';
