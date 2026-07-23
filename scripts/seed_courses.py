#!/usr/bin/env python3
"""One-shot import of all US golf courses from OpenGolfAPI into the courses table.

Data source: OpenGolfAPI (https://opengolfapi.org), licensed ODbL 1.0.
The app credits "© OpenGolfAPI contributors" in its About screen.

Usage:
    DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
        python3 scripts/seed_courses.py

Idempotent: upserts on external_id, so re-running after a data refresh is safe.
On success, removes the handful of 'seed:*' dev fixture courses that the real
dataset supersedes.
"""
import json
import os
import re
import sys
import time
import urllib.request

import psycopg

API = "https://api.opengolfapi.org/api/v1/courses/state/{}"
STATES = [
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI",
    "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN",
    "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
    "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
    "WV", "WI", "WY",
]

UPSERT = """
insert into public.courses
    (external_id, name, city, state, latitude, longitude, holes, course_type)
values (%s, %s, %s, %s, %s, %s, %s, %s)
on conflict (external_id) do update set
    name = excluded.name,
    city = excluded.city,
    state = excluded.state,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    holes = excluded.holes,
    course_type = excluded.course_type
"""


PAGE_SIZE = 500


def fetch_state(code: str) -> list:
    courses, offset = [], 0
    while True:
        url = f"{API.format(code)}?limit={PAGE_SIZE}&offset={offset}"
        req = urllib.request.Request(url, headers={"User-Agent": "3Wood-seed/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.load(resp)
        page = payload["courses"]
        courses.extend(page)
        offset += len(page)
        if not page or offset >= payload["total"]:
            return courses


def in_us_bounds(lat, lng) -> bool:
    # Continental US + Alaska + Hawaii; drops null-island and bad geocodes.
    return lat is not None and lng is not None and 17.5 <= lat <= 71.5 and -180.0 <= lng <= -64.5


def clean_name(name: str) -> str:
    # A stripped "™" leaves a literal "tm" glued to a word end (e.g.
    # "Spyglass Hilltm" -> "Spyglass Hill"); repair it.
    return re.sub(r"([a-z])tm( |$)", r"\1\2", name.strip())


def to_row(c: dict):
    return (
        f"ogapi:{c['id']}",
        clean_name(c["course_name"]),
        (c.get("city") or "").strip() or None,
        c.get("state"),
        c["lat"],
        c["lng"],
        c.get("holes"),
        (c.get("type") or "").strip().lower() or None,
    )


def main():
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        sys.exit("Set DATABASE_URL (local: postgresql://postgres:postgres@127.0.0.1:54322/postgres)")

    rows, dropped = [], 0
    for code in STATES:
        courses = fetch_state(code)
        kept = [c for c in courses if in_us_bounds(c.get("lat"), c.get("lng"))]
        dropped += len(courses) - len(kept)
        rows.extend(to_row(c) for c in kept)
        print(f"  {code}: {len(kept)} courses")
        time.sleep(0.2)  # be polite to the free API

    print(f"Fetched {len(rows)} courses ({dropped} dropped for missing/out-of-bounds coords)")

    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.executemany(UPSERT, rows)
            cur.execute("delete from public.courses where external_id like 'seed:%'")
            cur.execute("select count(*) from public.courses")
            print(f"courses table now holds {cur.fetchone()[0]} rows")


if __name__ == "__main__":
    main()
