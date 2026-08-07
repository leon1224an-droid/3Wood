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


def try_sign_in(password):
    """Returns (token, user_id), or None if the credentials are rejected."""
    req = urllib.request.Request(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": EMAIL, "password": password}).encode(),
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


def sign_up(password):
    """Create the account. Hosted has email confirmations off, so this returns a
    session immediately; if that ever changes, say so rather than failing oddly."""
    out = request("POST", "/auth/v1/signup",
                  body={"email": EMAIL, "password": password})
    if not out.get("access_token"):
        sys.exit(
            "Signed up, but no session came back — email confirmations are"
            " probably ON for this project.\nConfirm the address, then re-run."
        )
    return out["access_token"], out["user"]["id"]


def authenticate(password):
    creds = try_sign_in(password)
    if creds:
        print("Signed in.\n")
        return creds

    print(f"\n{EMAIL} does not exist on this backend (or the password differs).")
    print("Reviewers delete this account as part of Guideline 5.1.1(v) testing.")
    if input("Create it now with the password you just entered? [y/N] ").strip().lower() != "y":
        sys.exit("Aborted — nothing written.")
    creds = sign_up(password)
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

    token, user_id = authenticate(password)

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

    print("\nDone. Account matches the review notes in docs/appstore-listing.md.")
    print("Sign in once through the app to confirm before submitting.")


if __name__ == "__main__":
    main()
