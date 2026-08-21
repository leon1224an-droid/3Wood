#!/usr/bin/env python3
"""Rebuild the App Review demo account's data on the hosted backend.

App Review testers are asked to verify Guideline 5.1.1(v) — that an account can
really be deleted — and 3Wood's Delete Account button really deletes. So the
reviewer account is expected to vanish roughly every review cycle. This script
rebuilds it in one command instead of a ten-minute tour through the UI.

Usage:
    python3 scripts/seed_review_account.py

It prompts for the password (never echoed, never stored, never an argument, so
it stays out of shell history). If the account is gone it offers to create it.
This repo is public: do not add the password here, and do not pass it on the
command line.

Run this rather than rebuilding through the app. A simulator build launched from
Xcode is a DEBUG build, and Supa.swift points DEBUG at http://127.0.0.1:54321 —
so signing up there creates the account on your laptop, not on the backend Apple
reviews. That has already happened once. This script always talks to hosted.

Idempotent: re-running converges on the same state. insert_ranking removes and
reinserts, upsert_review upserts, and the want_to_play insert ignores duplicates.

Also seeds a second, non-secret fixture account (COMPANION_EMAIL below) with a
review, a ranking, and a comment the demo account can see and report — without
it, a reviewer signed into the demo account alone has no other user's content
on screen to flag or block, which is the likely cause of a Guideline 1.2
rejection ("could not verify the mechanism"). The companion's password is
hardcoded, unlike the demo account's: nobody signs into it by hand, it holds
no real user data, and the pattern matches the local `seed.sql` fixtures
(e.g. `birdie_ben` / `testpass123`) that are already committed.

The scores in docs/appstore-listing.md are not stored — they are derived from
bucket and position (see 00040000000000_rankings.sql):

    score = hi - width * (position - 0.5) / bucket_count
    liked -> hi 10.0, width 3.3      fine -> hi 6.6, width 3.2

Which is why the ranked set must be exactly these three courses. A fourth
changes bucket_count and moves every score. The script asserts the final scores
match the listing doc rather than trusting the arithmetic.
"""
import getpass
import json
import sys
import urllib.error
import urllib.request

SUPABASE_URL = "https://tivzyorqxauwbnczicst.supabase.co"
# Publishable (anon) key — safe to commit; RLS is the boundary. Mirrors Supa.swift.
ANON_KEY = "sb_publishable_TCv1DZgw6l7YE_oeKyJCYg_TqKpxJk8"

EMAIL = "3woodapp+review@gmail.com"
USERNAME = "demo_golfer"

# Fixture account so the demo account has another user's content to report
# and block. Low-value target by design — see module docstring.
COMPANION_EMAIL = "3woodapp+companion@gmail.com"
COMPANION_USERNAME = "sand_wedge_sam"
COMPANION_PASSWORD = "3wood-companion-fixture-2026"
COMPANION_REVIEW_BODY = (
    "Played it on a Tuesday morning and had the whole back nine to ourselves. "
    "Greens were a little slow but nothing to complain about."
)
COMPANION_COMMENT_BODY = "Nice round! What did you have the greens rolling at?"

REVIEW_BODY = (
    "Everything they say about it is true. Play it once in your life — "
    "the closing stretch along the water is worth the green fee on its own."
)

# (label, search query, bucket, position) in the order they must be ranked:
# position is 1-based and validated against the bucket's current count, so
# Pebble must land before Spyglass.
RANKINGS = [
    ("Pebble Beach", "Pebble Beach", "liked", 1, 9.2),
    ("Spyglass Hill", "Spyglass Hill", "liked", 2, 7.5),
    ("Torrey Pines North", "Torrey Pines", "fine", 1, 5.0),
]
BOOKMARK = ("Bethpage", "Bethpage")


def request(method, path, token=None, body=None, prefer=None):
    url = f"{SUPABASE_URL}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", ANON_KEY)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if prefer:
        req.add_header("Prefer", prefer)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        sys.exit(f"\n{method} {path} failed: HTTP {e.code}\n{detail}")


def try_sign_in(email, password):
    """Returns (token, user_id), or None if the credentials are rejected."""
    req = urllib.request.Request(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": password}).encode(),
        method="POST",
    )
    req.add_header("apikey", ANON_KEY)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            out = json.loads(resp.read())
            return out["access_token"], out["user"]["id"]
    except urllib.error.HTTPError as e:
        if e.code in (400, 401):
            return None            # no such user, or wrong password
        sys.exit(f"\nSign-in failed: HTTP {e.code}\n{e.read().decode(errors='replace')}")


def sign_up(email, password):
    """Create the account. Hosted has email confirmations off, so this returns a
    session immediately; if that ever changes, say so rather than failing oddly."""
    out = request("POST", "/auth/v1/signup",
                  body={"email": email, "password": password})
    if not out.get("access_token"):
        sys.exit(
            "Signed up, but no session came back — email confirmations are"
            " probably ON for this project.\nConfirm the address, then re-run."
        )
    return out["access_token"], out["user"]["id"]


def authenticate(email, password, *, confirm=True, context=""):
    creds = try_sign_in(email, password)
    if creds:
        print("Signed in.\n")
        return creds

    print(f"\n{email} does not exist on this backend (or the password differs).")
    if context:
        print(context)
    if confirm and input("Create it now with the password you just entered? [y/N] ").strip().lower() != "y":
        sys.exit("Aborted — nothing written.")
    creds = sign_up(email, password)
    print("Account created.\n")
    return creds


def resolve(label, query, token):
    """Search for a course and confirm which row we mean. Never guesses silently."""
    results = request("POST", "/rest/v1/rpc/search_courses",
                      token=token, body={"p_query": query}) or []
    if not results:
        sys.exit(f"No course found for {label!r} (searched {query!r}).")

    exact = [c for c in results if c["name"].strip().lower() == label.lower()]
    if len(exact) == 1:
        c = exact[0]
        print(f"  {label:22} -> [{c['id']}] {c['name']}, {c['city']}, {c['state']}")
        return c["id"]

    print(f"\n  {label!r} is ambiguous — {len(results)} matches for {query!r}:")
    for i, c in enumerate(results[:15], 1):
        print(f"    {i:2}. [{c['id']}] {c['name']}, {c['city']}, {c['state']}")
    while True:
        choice = input(f"  Which one is {label}? [1-{min(len(results), 15)}] ").strip()
        if choice.isdigit() and 1 <= int(choice) <= min(len(results), 15):
            return results[int(choice) - 1]["id"]


def main():
    print(f"Rebuilding review account data for {EMAIL}")
    print(f"Target: {SUPABASE_URL}  (PRODUCTION)\n")

    password = getpass.getpass("Password (from App Store Connect): ")
    if not password:
        sys.exit("No password entered.")

    token, user_id = authenticate(
        EMAIL, password,
        context="Reviewers delete this account as part of Guideline 5.1.1(v) testing.",
    )

    # --- username -------------------------------------------------------
    rows = request("GET", f"/rest/v1/profiles?id=eq.{user_id}&select=username",
                   token=token)
    if not rows:
        request("POST", "/rest/v1/profiles", token=token,
                body={"id": user_id, "username": USERNAME})
        print(f"Created profile @{USERNAME}.")
    elif rows[0]["username"] != USERNAME:
        request("PATCH", f"/rest/v1/profiles?id=eq.{user_id}", token=token,
                body={"username": USERNAME})
        print(f"Renamed @{rows[0]['username']} -> @{USERNAME}.")
    else:
        print(f"Profile @{USERNAME} already correct.")

    # --- refuse to seed on top of unknown state -------------------------
    existing = request("POST", "/rest/v1/rpc/my_ranked_courses", token=token,
                       body={}) or []
    if existing:
        print(f"\nAccount already has {len(existing)} ranked course(s):")
        for c in existing:
            print(f"    [{c['course_id']}] {c['name']} — {c['score']}")
        print("\nA course outside the expected three changes bucket_count and")
        print("shifts every score off the values in docs/appstore-listing.md.")
        if input("Remove all of them and reseed? [y/N] ").strip().lower() != "y":
            sys.exit("Aborted — nothing written.")
        for c in existing:
            request("POST", "/rest/v1/rpc/remove_ranking", token=token,
                    body={"p_course_id": c["course_id"], "p_drop_activity": True})
        print("Cleared.")

    # --- resolve every course before writing anything -------------------
    print("\nResolving courses:")
    ranked = [(label, bucket, pos, want, resolve(label, query, token))
              for label, query, bucket, pos, want in RANKINGS]
    bookmark_id = resolve(*BOOKMARK, token)

    print(f"\nAbout to write to PRODUCTION as @{USERNAME}.")
    if input("Proceed? [y/N] ").strip().lower() != "y":
        sys.exit("Aborted — nothing written.")

    # --- rank, bookmark, review -----------------------------------------
    print()
    for label, bucket, pos, _want, course_id in ranked:
        request("POST", "/rest/v1/rpc/insert_ranking", token=token,
                body={"p_course_id": course_id, "p_bucket": bucket,
                      "p_position": pos})
        print(f"Ranked {label} ({bucket}, position {pos}).")

    request("POST", "/rest/v1/want_to_play", token=token,
            body={"user_id": user_id, "course_id": bookmark_id},
            prefer="resolution=ignore-duplicates")
    print("Bookmarked Bethpage.")

    pebble_id = ranked[0][4]
    request("POST", "/rest/v1/rpc/upsert_review", token=token,
            body={"p_course_id": pebble_id, "p_body": REVIEW_BODY})
    print("Wrote the Pebble Beach review.")

    # --- verify against the listing doc ---------------------------------
    print("\nVerifying derived scores:")
    final = request("POST", "/rest/v1/rpc/my_ranked_courses", token=token,
                    body={}) or []
    actual = {c["course_id"]: c for c in final}
    ok = len(final) == len(ranked)
    if not ok:
        print(f"  Expected {len(ranked)} ranked courses, backend returned {len(final)}.")
    for label, _bucket, _pos, want, course_id in ranked:
        got = actual.get(course_id, {}).get("score")
        mark = "ok" if got is not None and abs(float(got) - want) < 0.05 else "MISMATCH"
        if mark != "ok":
            ok = False
        print(f"  {label:22} expected {want}  got {got}  [{mark}]")

    if not ok:
        sys.exit(
            "\nScores do not match docs/appstore-listing.md. Do not submit with\n"
            "this state — fix the data or update the listing doc to match."
        )

    torrey_id = ranked[2][4]  # Torrey Pines North — order matches RANKINGS
    seed_companion(demo_token=token, demo_user_id=user_id,
                    torrey_id=torrey_id, pebble_id=pebble_id)

    print("\nDone. Account matches the review notes in docs/appstore-listing.md.")
    print("Sign in once through the app to confirm before submitting.")


def seed_companion(demo_token, demo_user_id, torrey_id, pebble_id):
    """Seeds a second fixture account with content the demo account can see,
    report, and block — see the module docstring for why this exists."""
    print(f"\nSeeding companion account {COMPANION_EMAIL}...")
    token, user_id = authenticate(COMPANION_EMAIL, COMPANION_PASSWORD, confirm=False)

    rows = request("GET", f"/rest/v1/profiles?id=eq.{user_id}&select=username",
                   token=token)
    if not rows:
        request("POST", "/rest/v1/profiles", token=token,
                body={"id": user_id, "username": COMPANION_USERNAME})
        print(f"Created profile @{COMPANION_USERNAME}.")
    elif rows[0]["username"] != COMPANION_USERNAME:
        request("PATCH", f"/rest/v1/profiles?id=eq.{user_id}", token=token,
                body={"username": COMPANION_USERNAME})
    else:
        print(f"Profile @{COMPANION_USERNAME} already correct.")

    request("POST", "/rest/v1/rpc/insert_ranking", token=token,
            body={"p_course_id": torrey_id, "p_bucket": "liked", "p_position": 1})
    print("Companion ranked Torrey Pines North.")

    request("POST", "/rest/v1/rpc/upsert_review", token=token,
            body={"p_course_id": torrey_id, "p_body": COMPANION_REVIEW_BODY})
    print("Companion wrote a Torrey Pines North review — reportable from that "
          "course's page as @demo_golfer.")

    request("POST", "/rest/v1/follows", token=demo_token,
            body={"follower_id": demo_user_id, "followee_id": user_id},
            prefer="resolution=ignore-duplicates")
    print("@demo_golfer now follows the companion, so its activity appears in "
          "@demo_golfer's feed — block it there to demonstrate content vanishing.")

    activities = request(
        "GET",
        f"/rest/v1/activities?actor_id=eq.{demo_user_id}&kind=eq.ranked"
        f"&course_id=eq.{pebble_id}&select=id&limit=1",
        token=token,
    ) or []
    if activities:
        activity_id = activities[0]["id"]
        # add_comment has no upsert — guard against piling up duplicates
        # across repeated runs the way insert_ranking/upsert_review do.
        existing_comments = request(
            "GET",
            f"/rest/v1/activity_comments?activity_id=eq.{activity_id}"
            f"&user_id=eq.{user_id}&select=id&limit=1",
            token=token,
        ) or []
        if not existing_comments:
            request("POST", "/rest/v1/rpc/add_comment", token=token,
                    body={"p_activity_id": activity_id,
                          "p_body": COMPANION_COMMENT_BODY})
            print("Companion commented on @demo_golfer's Pebble Beach activity.")
        else:
            print("Companion's comment on that activity already exists.")
        print("Reportable from that activity's detail view.")
    else:
        print("Could not find @demo_golfer's Pebble Beach activity to comment "
              "on — rank Pebble Beach first, then re-run this script.")


if __name__ == "__main__":
    main()
