-- Usernames keep the case the owner typed (@LeonAn) but stay unique
-- case-insensitively so @leonan can't be claimed separately.

alter table public.profiles drop constraint if exists profiles_username_check;
alter table public.profiles
  add constraint profiles_username_check check (username ~ '^[A-Za-z0-9_]{3,20}$');

create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username));
alter table public.profiles drop constraint if exists profiles_username_key;
