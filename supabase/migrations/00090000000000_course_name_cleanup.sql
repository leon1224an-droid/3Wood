-- Repair trademark artifacts in seeded course names: a stripped "™" left a
-- literal "tm" glued to the end of a word (e.g. "Spyglass Hilltm" -> "Spyglass
-- Hill"). Only affects the handful of Pebble Beach resort courses.
update public.courses
set name = regexp_replace(name, '([a-z])tm( |$)', '\1\2', 'g')
where name ~ '[a-z]tm( |$)';
