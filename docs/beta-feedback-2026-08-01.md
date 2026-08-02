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

## Tranche 1 — quick wins — implemented on `beta-feedback-tranche-1`, not merged

| # | Feedback | Where | Fix |
|---|---|---|---|
| 9 | "Tapping on courses not very sensitive" | `CourseMapView.swift` map annotations | Unrated pins are a **12×12** `Circle`; `ScoreBadge(compact:)` is not much larger. Both far under the 44pt minimum. Wrap in a ≥44pt frame with transparent padding + `.contentShape(Rectangle())`. Highest value-per-line on the list. |
| 8 | "Easier way to add to want-to-play from the list" | `CourseRow` (`SearchView.swift`), map list mode | Add a leading swipe action → `WantToPlayRepo.add`. One decision: `CourseRow` doesn't know bookmark state, so either go optimistic (show a checkmark, don't re-fetch) or extend the course query with an `is_saved` flag. Optimistic is the cheap correct answer. |
| 10 | "Link your number text is wordy and not next to phone number" | `ProfileView.swift` — Section `footer:` | Confirmed: the copy sits in the section footer, three rows below the "Phone number" row it describes. Move it inline as row subtext and cut it to ~5 words ("Friends can find you by number"). The longer explanation already exists in `PhoneLinkSheet`'s own footer, so nothing is lost. |
| 6 | "When finding friends through contacts, ability to go back" | `FindFriendsView.swift` | **Cause confirmed from UI-test screenshots, no tester question needed.** `ContactsMatchView` has a normal back button (see snapshot `27-Contacts`). The screen that loses it is `FindFriendsView`: snapshot `07-FindFriends` shows that once the search field is focused, the whole navigation bar is replaced by a lone dismiss-search "✕" — the route *to* contacts is the dead end, not contacts itself. Fixed with `.searchPresentationToolbarBehavior(.avoidHidingContent)`, availability-guarded since the deployment target is 17.0 and the modifier is 17.1+. Re-ran the test: back chevron and title now stay put with the keyboard up. |

## Tranche 2 — implemented on `beta-feedback-tranche-1`, not merged

Migration `00160000000000_leaderboard_period_streak.sql`.

**The finding that shaped this tranche:** neither feature could be built on
`created_at`. `insert_ranking` re-logs by deleting and re-inserting (defined in
`00050`, *not* `00040` — 00050 redefines it to also clear the want-to-play row), so
re-ranking a course first played in 2019 stamps it with today. A weekly board would
have counted re-logs as new courses, and a "streak of adding courses" would have
survived on re-ranking the same course every week — the opposite of what it rewards.
Fixed additively with a `first_ranked_at` column carried across re-ranks; `created_at`
keeps its meaning ("last logged") so the Played list's "Recently logged" sort is
untouched. Verified: after a re-rank, `first_ranked_at` was still 200 days old while
`created_at` reset to today.

| # | Feedback | Shipped |
|---|---|---|
| 4 | Weekly + all-time contributor rankings | `leaderboard(p_period text default 'all')`. The parameter is **defaulted on purpose**: TestFlight build 2 is in the wild calling `leaderboard()` with no arguments, and a defaulted parameter keeps that call resolving. Confirmed against PostgREST rather than assumed — the no-arg POST returns 200 after the migration. `LeaderboardView` gets This Week / All Time tabs. |
| 3 | Week streak of adding courses | `streak_weeks(p_user uuid default null)` — gaps-and-islands over distinct log weeks. Shown as a chip on `ProfileView`. The `p_user` parameter costs nothing now and is what a streak-on-the-leaderboard would need later. |

**Streak definition (decided, not defaulted into):** consecutive calendar weeks
containing at least one *newly added* course. The current week counts once it has a
log; if it doesn't yet, the streak still counts through last week, so it doesn't
collapse to zero every Monday morning. A two-week gap ends it. Weeks are Monday-based
in the server's timezone (UTC), so a Sunday-evening round on the US west coast counts
toward the following week — a real edge, not worth timezone plumbing at this scale.

### Verification

Seven cases against the local stack in a rolled-back transaction, since seed data is
all stamped "now" and would make these tests vacuous: streak with a gap → 2 (not 4),
grace period with nothing logged this week → 2, only a stale 3-week-old log → 0, no
rankings → 0, five unbroken weeks → 5, two logs in one week → 2 (no double-count),
and the weekly board showing 1 where all-time shows 3.

`SegmentTabs` was extracted from `ListsView` into `Core/DesignSystem` so the
leaderboard's switcher is literally the same control rather than a lookalike.

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

### Verification

`xcodebuild test` — 16 unit tests in 3 suites plus all 6 `NavigationUITests` pass.
(The unit bundle is Swift Testing, so it reports as `✔ Test run with 16 tests`
rather than XCTest's `Executed N tests` — easy to misread as "not running".)

`LiveBackendTests.repeatedWantToPlayInsertIsIdempotent` is new: it inserts the same
`want_to_play` row twice against the real backend with the exact `Prefer` header
supabase-swift sends, because `want_to_play` grants INSERT but not UPDATE and a
wrong resolution there fails at runtime, not compile time. Checked that the test
discriminates — with the header removed it fails on the duplicate (409), so it
would catch a revert to plain `.insert`.

Note the swipe path is exercised at the repo/RLS layer, not through the SwiftUI
gesture; `QuickSaveState` itself has no test.

All 6 `NavigationUITests` pass. The suite attaches a screenshot
per screen, so the changed surfaces were checked visually from the result bundle
(`06-Profile`, `07-FindFriends`, `05-Map`, `03-Search-Results`). Note the map
snapshot still shows the continental US: the simulator has no location fix, so
`currentLocation()` returns nil — which now correctly leaves `hasCenteredOnUser`
false so a later attempt can still center. **Untested in the simulator:** the pin
tap targets and swipe-to-save both need a device with a real location and a
zoomed-in map; worth a pass on the phone before pushing a build.

One known limit of the tap-target fix: the 44pt hit areas overlap between adjacent
pins in dense metros, and the topmost in z-order wins. Still strictly better than a
12pt dot, but clustered courses won't feel fully fixed — clustering or
zoom-dependent sizing is the real answer if testers raise it again.

## Local dev environment — read before the next `supabase db reset`

Running `supabase db reset` while building tranche 2 destroyed local dev data that
existed **only** in the local database: the ~16k imported courses, and the fixture
accounts (`birdie_ben`, `test1`, `mulligan_mike`) with their rankings, follows and
reviews. `seed.sql` held 15 courses and no accounts, and the UI tests *sign in* as
`birdie_ben@example.com` rather than creating it — so a reset silently removed the
thing every test depends on.

Fixed so it can't happen the same way again:

- All six fixture accounts, their rankings, follows, bookmarks and reviews are now
  defined in `seed.sql`, so `db reset` reproduces them. Password `testpass123`.
  (`auth.users` needs `confirmation_token` / `recovery_token` /
  `email_change_token_new` / `email_change` set to `''` rather than left NULL —
  GoTrue scans them into non-nullable strings and every sign-in fails with
  "Database error querying schema" otherwise.)
- `scripts/seed_courses.py` used to end with
  `delete from courses where external_id like 'seed:%'`. `courses` cascades on
  delete, so that would now silently take the seeded rankings/bookmarks/reviews with
  it. It now skips any fixture course that dev data references.
- Spyglass Hill was added to the seed because `testLogCourseFlow` logs it; the whole
  suite now passes on seed data alone, with no import required.

**Still missing:** the ~16k real courses. Re-import with
`DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres python3
scripts/seed_courses.py` (hits OpenGolfAPI for 51 states, few minutes). Not run
automatically — it's a long external fetch.

## Recommended order

1. Tranche 1 (quick wins) — ship as build 3, immediate visible response to testers
2. Tranche 2 (weekly leaderboard + streak) — retention mechanics, cheap
3. Search/map merge — frees a tab before the alert feed needs one
4. `activities` migration → reactions → comments → alert feed
5. Photos

Branch before any of this lands; `main` is the shipped TestFlight build.
