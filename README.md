# 3Wood

Rank every golf course you've played. A Beli-style iOS app for US golf courses: log a course, rank it through head-to-head comparisons against courses you've already played, and get a personal 0–10 rating list. Browse a map of ~16k US courses with community average ratings.

## Stack

- **iOS app**: Swift + SwiftUI, MapKit, iOS 17+, MVVM-lite with feature folders (`3Wood/Features/*`)
- **Backend**: Supabase (Postgres + PostGIS + Auth), schema versioned in `supabase/migrations/`
- **Course data**: seeded from an open dataset via `scripts/seed_courses.py`

## Development

```bash
# Backend (local, requires Docker/OrbStack running)
supabase start          # local stack at http://127.0.0.1:54321, Studio at :54323
supabase db push --local  # apply migrations

# App
open 3Wood.xcodeproj    # build & run the 3Wood scheme in Xcode (iOS 17+ simulator)
```

The app's `Config` in `3Wood/Core/Supa.swift` points at the local Supabase stack by default.

## Roadmap

- [x] M0 — Scaffold: Xcode project, Supabase local stack, migrations
- [ ] M1 — Auth + profiles (email, Sign in with Apple)
- [ ] M2 — Course database, search, map, course detail
- [ ] M3 — Want to Play list
- [ ] M4 — Ranking flow (bucket + head-to-head comparisons) and 0–10 scores
- [ ] M5 — Social: follows, friends' scores
- [ ] M6 — Polish + App Store submission
