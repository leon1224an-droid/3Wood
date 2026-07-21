-- Extensions required by 3Wood:
--   postgis  — geography column + GiST index for map viewport queries
--   pg_trgm  — trigram index for fuzzy course-name search
create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
