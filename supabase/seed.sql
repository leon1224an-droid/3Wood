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
  ('seed:bay-hill',          'Bay Hill Club & Lodge',              'Orlando',           'FL', 28.4634,  -81.5064, 18, 'private')
on conflict (external_id) do nothing;
