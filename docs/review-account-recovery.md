# Recovering the App Review demo account

The reviewer account **is expected to disappear roughly once per review cycle.**
Guideline 5.1.1(v) asks reviewers to confirm an account can really be deleted,
`delete_account()` really deletes, and there is no undo. This is the runbook for
putting it back.

Account: `3woodapp+review@gmail.com`, username `@demo_golfer`, hosted backend
`https://tivzyorqxauwbnczicst.supabase.co`. The password lives **only** in App
Store Connect — this repo is public, never write it down here.

## 1. Confirm it is actually the account

Two failures look identical from inside the app ("Invalid login credentials"),
so check which one you have before doing anything.

```sh
# Is the backend even up? Free tier pauses after ~7 days idle.
supabase projects list          # want status ACTIVE_HEALTHY
curl -s https://tivzyorqxauwbnczicst.supabase.co/auth/v1/health \
  -H "apikey: sb_publishable_TCv1DZgw6l7YE_oeKyJCYg_TqKpxJk8"
```

If that is healthy, ask whether the auth user still exists. `profiles` is
useless for this — RLS hides every row from the anon key, so an empty result
proves nothing. Use the admin API with the service key:

```sh
SK=$(supabase projects api-keys --project-ref tivzyorqxauwbnczicst -o json \
  | python3 -c "import sys,json;print(next(k['api_key'] for k in json.load(sys.stdin) if k['name']=='service_role'))")
# note the %2B — a raw + in a query string decodes to a space
curl -s "https://tivzyorqxauwbnczicst.supabase.co/auth/v1/admin/users?filter=3woodapp%2Breview@gmail.com" \
  -H "apikey: $SK" -H "Authorization: Bearer $SK"
```

`"users": []` → the account was deleted, continue below.
A user object → the account exists and the **password** is wrong; skip to §4.

## 2. Rebuild it

From `~/3Wood`, in a normal Terminal (the script uses `getpass`, so it needs a
real TTY):

```sh
python3 scripts/seed_review_account.py
```

Paste the password from **App Store Connect → your app → the 1.0 version page →
App Review Information → Sign-In Required**. The script will report that the
account does not exist and offer to create it — answer `y`. It then sets
`@demo_golfer`, ranks the three courses, bookmarks Bethpage, writes the Pebble
review, and asserts the derived scores are 9.2 / 7.5 / 5.0.

**Eyeball the "Resolving courses" step.** The score assertion cannot catch a
wrong course: a lone `fine` course derives 5.0 whichever one it is, so Torrey
Pines *South* would pass silently. `docs/appstore-listing.md` promises
**Torrey Pines North** and **Bethpage Black** — pick those at the prompts.

## 3. Verify, without breaking it again

Sign in as the demo account on the **TestFlight build on a real iPhone**.

- A simulator build launched from Xcode is DEBUG, and `Supa.swift` points DEBUG
  at `http://127.0.0.1:54321`. Signing in there tells you nothing about hosted,
  and *signing up* there silently creates the account on your laptop. Only
  Release/TestFlight reaches hosted.
- Never tap **Delete Account** while signed in as the demo account. That is the
  only thing that can remove it — `delete_account()` only ever deletes
  `auth.uid()`.

## 4. If the password no longer matches App Store Connect

Whatever you type at the script's prompt becomes the account's password when it
creates the account. If that is not the string in App Store Connect, update
**App Review Information → Sign-In Required** to match. That field is part of
the version metadata, not the binary — changing it does **not** require a new
build or a new upload.

## 5. If Apple already rejected over it

The rejection lands in **Resolution Center** as Guideline 2.1 (Performance —
App Completeness), "we were unable to sign in". Rebuild the account, then reply
in Resolution Center saying the credentials in App Review Information are valid
and ready. No new build is needed; the review resumes on the same submission.

## Recurrence

Expect to run this after every review cycle, and again before flipping the app
to Released. It is idempotent — re-running converges on the same state.
