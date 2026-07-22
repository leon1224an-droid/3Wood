-- Account deletion (required by App Store Review Guideline 5.1.1(v)).
-- Deleting the auth.users row cascades to profiles, which cascades to
-- rankings, want_to_play, and follows.
create or replace function public.delete_account()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = v_user;
end;
$$;
