# Beta feedback triage — 2026-08-01

12 items from TestFlight testers, mapped to code and grouped by what they actually
cost. Ordered by value-per-hour, not by the order they arrived.

## The one structural finding

**Comments, reactions, and the alert feed are one backend project, not three features.**

`activity_feed()` (`supabase/migrations/00100000000000_feed_leaderboard.sql`) is a
`UNION ALL` view over `user_course_scores` and `want_to_play`. There is no activity
row. `FeedItem` proves it — it synthesizes a client-side id:

```swift
var id: String { "\(kind)-\(actorID)-\(courseID)-\(createdAt.timeIntervalSince1970)" }
```

Nothing can be attached to an activity until an activity has a stable server id.
A comment or reaction needs a foreign key, and a notification needs a target to
deep-link to. Re-ranking a course changes `created_at`, so the composite key is not
stable either — it has to be a real `activities` table (trigger-populated from the
two source tables, backfilled once).

That migration is the prerequisite for items 1, 2, and the notification half of
anything else. Sequence it first or those three items each pay the cost separately.

---

## Tranche 1 — quick wins (no migration, ~half a day)

| # | Feedback | Where | Fix |
|---|---|---|---|
| 9 | "Tapping on courses not very sensitive" | `CourseMapView.swift` map annotations | Unrated pins are a **12×12** `Circle`; `ScoreBadge(compact:)` is not much larger. Both far under the 44pt minimum. Wrap in a ≥44pt frame with transparent padding + `.contentShape(Rectangle())`. Highest value-per-line on the list. |
| 8 | "Easier way to add to want-to-play from the list" | `CourseRow` (`SearchView.swift`), map list mode | Add a leading swipe action → `WantToPlayRepo.add`. One decision: `CourseRow` doesn't know bookmark state, so either go optimistic (show a checkmark, don't re-fetch) or extend the course query with an `is_saved` flag. Optimistic is the cheap correct answer. |
| 10 | "Link your number text is wordy and not next to phone number" | `ProfileView.swift` — Section `footer:` | Confirmed: the copy sits in the section footer, three rows below the "Phone number" row it describes. Move it inline as row subtext and cut it to ~5 words ("Friends can find you by number"). The longer explanation already exists in `PhoneLinkSheet`'s own footer, so nothing is lost. |
| 6 | "When finding friends through contacts, ability to go back" | `ContactsMatchView.swift` | **Needs one clarifying question.** `.contacts` is a normal `Router.push`, so a system back button should be present. Candidates: (a) they meant `FindFriendsView`, where an active `.searchable` replaces the back button with Cancel; (b) they meant backing out of the contacts permission state; (c) edge-swipe not registering. Ask which screen before coding — a blind fix here is guessing. |

## Tranche 2 — cheap backend (~1 migration each)

| # | Feedback | Cost |
|---|---|---|
| 4 | Weekly + all-time contributor rankings | `leaderboard()` already exists and returns rank/played. Add a `period` argument with a `created_at >= now() - interval '7 days'` filter (next migration is `00160000000000_*`), then a segment control in `LeaderboardView` — reuse the flat underlined `segmentTabs` from `ListsView` rather than a stock picker. |
| 3 | Week streak of adding courses | A `streak_weeks()` RPC over `user_course_rankings.created_at`, surfaced on `ProfileView` (and optionally as a leaderboard column). **Product decision needed:** consecutive ISO weeks with ≥1 log? Does the current in-progress week count? Streaks are a retention lever — worth deciding deliberately, not defaulting. |

## Tranche 3 — the social layer (the big one)

| # | Feedback | Notes |
|---|---|---|
| 1 | Comment + react to friends' activities ("let's make the reacts fun") | Blocked on the `activities` table above. Then: `reactions` + `comments` tables with RLS, counts folded into `activity_feed()`, and a reaction picker. "Fun" here = golf-native emoji set (⛳️🦅🔥💀 for a blow-up round) rather than generic likes — that's a design round, and it should go through the render-PNG review loop. Comments are user-generated content, so they need the `ModerationRepo` report path that reviews already have. |
| 2 | Alert feed (new follower, comment on your activity) | `notifications` table + unread count, a new screen, and a badge on the Feed tab. In-app only is achievable; **push** notifications are a separate project (APNs key, capability, device-token table, server-side send) — don't conflate them. |

## Tranche 4 — refactors and expensive items

| # | Feedback | Notes |
|---|---|---|
| 12 | "Search and map should just be combined" | Genuinely feasible — `CourseMapView` already has list mode, its own `.searchable`, and `MapSearchModel` with course + place suggestions. But it means deleting a tab, choosing which router survives (`nav.searchRouter` vs `nav.mapRouter`), and updating `3WoodUITests/NavigationUITests.swift`. Worth doing; do it alone, not mixed with feature work. Frees a tab slot the alert feed will want. |
| 11 | "Interact with map inside a course page" | `CourseDetailView` sets `.allowsHitTesting(false)` **deliberately** — the snippet is inside a `ScrollView`, and an interactive map eats vertical drags so the page stops scrolling. This is not a one-line deletion. Fix shape: keep it inert, add a tap that opens a full-screen map sheet (or Apple Maps for directions). |
| 7 | "Allow while using → should go to exact current location" | Three candidate causes, all real: (a) `LocationProvider` sets `desiredAccuracy = kCLLocationAccuracyKilometer` — coarse by construction; (b) `if let cached = manager.location` returns a stale fix; (c) in `CourseMapView.task`, `hasCenteredOnUser = true` is set **before** the `await` — the permission alert is exactly when that task gets cancelled, after which it never retries and never centers. (c) is the likeliest and is a 2-line fix. Note `MapUserLocationButton()` already exists in `.mapControls`, so the tester may be complaining about that button rather than first-launch centering — worth confirming. |
| 5 | Add photos to golf courses | **Most expensive item, and it's not close.** Supabase Storage bucket + RLS + upload/compression + a moderation path. `ModerationRepo` and the review-report flow exist because UGC already required them; photos raise that bar (image moderation, EXIF stripping). Plan it as its own release. |

---

## Recommended order

1. Tranche 1 (quick wins) — ship as build 3, immediate visible response to testers
2. Tranche 2 (weekly leaderboard + streak) — retention mechanics, cheap
3. Search/map merge — frees a tab before the alert feed needs one
4. `activities` migration → reactions → comments → alert feed
5. Photos

Branch before any of this lands; `main` is the shipped TestFlight build.
