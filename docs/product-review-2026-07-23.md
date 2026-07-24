# 3Wood — Comprehensive Product Review

*2026-07-23 · 39 agents (7 specialist reviewers + adversarial verification of every finding + completeness critic + 3 gap reviewers) · evidence: 24 light + 13 dark screenshots from the full UI-test tour, plus the entire Swift codebase and SQL migrations.*

**97 findings confirmed** (2 refuted in verification, 4 could not be verified due to one stalled verifier). Severity mix: 
**15 high · 48 medium · 34 low.**


## Functionality — Code Audit

**Strengths (keep these):**

- RankingEngine is clean, pure, and genuinely well-tested: binary insertion with an exhaustive every-slot test (RankingEngineTests.binaryInsertionFindsEverySlot) and a log2 comparison bound. The brand-new-user edge case is handled correctly — an empty bucket finishes immediately and saves at position 1 with no comparison screens and no crash (RankingEngine.swift lines 40-54, verified by emptyBucketFinishesImmediately test).
- Server-side ranking writes are done right: insert_ranking/remove_ranking are atomic SECURITY DEFINER RPCs with a clever two-step position shift to avoid transient unique-index collisions, re-logging is handled by remove-then-insert, and the QoL migration correctly auto-removes a course from Want to Play when it gets ranked (00050 lines 44-81). Scores are pure views, never stored — no denormalization drift.
- ScoreBadge color thresholds (>=6.7 green, 3.4-6.6 gold, <3.4 red) exactly match the SQL bucket score ranges, so a 'liked' course can never render amber — a small but real cross-layer consistency win.
- Search and map debouncing is implemented correctly: task cancellation checked both before and after the await, so stale responses can't clobber newer results (SearchViewModel.swift lines 14-32, MapViewModel.swift lines 15-30).
- Username validation is enforced identically client-side (regex in UsernameSetupView) and in the DB check constraint, and self-follow is blocked by a DB check constraint — the schema doesn't trust the client.
- RLS design is coherent: public reads where the product needs them (Beli-style public rankings/profiles/reviews), own-row writes everywhere else, and no direct write path to rankings outside the RPCs.
- Account deletion is a single server-side RPC that cascades through profiles to all user data (meets App Store 5.1.1(v)), followed by a local sign-out, with a destructive confirmation dialog and a surfaced error alert — one of the few flows that does show errors.
- State refresh after the core action mostly works: ListsView and CourseDetailView reload on log-flow dismissal, and .task re-running on tab/nav reappearance keeps Feed and Profile counts fresh in the happy path.


### [HIGH] Offline app launch silently dumps a signed-in user onto the Welcome screen

SessionStore.resolveProfile treats any fetch error as 'signed out'. On a cold launch with the backend unreachable (airplane mode, bad hotel Wi-Fi, or the hosted project having a blip), a user with a perfectly valid persisted session is shown WelcomeView with 'Create account / Sign in'. There is no retry path: nothing re-runs resolveProfile when connectivity returns, so the user is pushed to re-enter credentials (which also fails while offline), and a confused user may tap 'Create account'. The comment says 'so the user can retry' but no retry mechanism exists — the only thing that re-triggers resolution is a new auth event.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/SessionStore.swift lines 45-56: `catch { state = .signedOut }` inside resolveProfile; RootView.swift lines 10-19 renders WelcomeView for .signedOut with no distinction from a real sign-out.

**Recommendation:** Add a `.failed` state with a Retry button (and/or auto-retry with backoff). Only show WelcomeView when there is genuinely no session; if supa.auth.currentSession exists but the profile fetch failed, show an offline/retry screen instead.

**Verifier:** Confirmed. SessionStore.swift:52-55 catches any profile-fetch error and sets state = .signedOut; RootView.swift:13-14 renders WelcomeView for .signedOut with no distinction from a real sign-out. I also verified the claimed absence of a retry path: the start() loop only re-resolves on .initialSession/.signedIn/.userUpdated auth events — a token refresh after connectivity returns hits `default: break` (lines 30-31), so nothing ever re-runs resolveProfile. Supabase emits .initialSession from the locally persisted session, so an airplane-mode cold launch deterministically lands a valid signed-in user on 'Create account / Sign in'. High is correct: this reads as being logged out / data gone, and golfers are exactly the users who launch apps with poor signal.


### [HIGH] Every load error is swallowed into a misleading empty state — offline users see 'No courses yet' over their real data

All list-loading code paths use `try?` with no error state, so a network failure renders the same UI as 'you have no data'. Concretely: Lists tab first-load failure shows 'No courses yet — Log your first course' to a user who has dozens of rankings (they will reasonably think their data was deleted); Feed shows 'Your feed is quiet — Follow friends to see...'; Search shows 'No results for X'; Leaderboard shows 'No rankings yet'; and the Map is worse — a mid-session fetch failure assigns an empty array and wipes already-drawn pins. No screen has an error message or a Retry affordance anywhere in the app.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift lines 61-69 (empty-state CTA) + 115-120 (`(try? await rankedTask) ?? ranked` — falls back to [] on first load); Feed/FeedView.swift lines 12-20 + 54-57; Search/SearchViewModel.swift line 27 (`?? []` then 'No results'); Feed/LeaderboardView.swift lines 53-56; Map/MapViewModel.swift lines 21-28 (`let found = (try? ...) ?? []` then `courses = found` clears existing pins on failure).

**Recommendation:** Track a load-failed flag per screen and render a 'Couldn't load — Retry' state distinct from the true empty state. On the map, keep the previous `courses` array when a fetch throws (only replace on success).

**Verifier:** Confirmed at every cited site: ListsView.swift:118-119 (`(try? ...) ?? ranked` — [] on first-load failure, then lines 61-69 show the 'No courses yet / Log your first course' CTA), FeedView.swift:55 ('Your feed is quiet'), SearchViewModel.swift:27 (`?? []` feeding SearchView's ContentUnavailableView.search 'No Results'), LeaderboardView.swift:54 (`?? []` → 'No rankings yet'), and MapViewModel.swift:26-28 where a mid-session failure assigns [] and unconditionally replaces `courses`, wiping drawn pins — unlike lists/feed which at least keep prior data. One overstatement to correct: LogCourseFlow.swift:46-53 does render a 'Couldn't save' error screen, so 'no error message anywhere in the app' is not literally true — but no LOAD path surfaces an error and no Retry button exists anywhere. Keeping high: telling a user with dozens of rankings 'No courses yet' on a transient failure directly attacks the core promise (your ranked list), and spotty-signal contexts are this app's home turf.


### [MEDIUM] User actions can fail with zero feedback — most acutely, saving a review over 2000 characters always silently does nothing

WriteReviewSheet.save catches all errors and does nothing: no alert, no message, the sheet just stays open and Save appears broken. The DB enforces `char_length(body) between 1 and 2000`, but the app neither limits nor counts characters, so any review longer than 2000 chars fails the check server-side and is silently unsavable — the user cannot know why. The same silent-catch pattern applies to review deletion, follow/unfollow (FollowButton), and the bookmark toggle, so offline taps on these controls appear to be accepted-then-ignored.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/CourseDetail/WriteReviewSheet.swift lines 51-62 (`catch { // Keep the sheet open... }`) and 64-69 (`catch {}`); /Users/leon-an/3Wood/supabase/migrations/00110000000000_reviews.sql line 6 (check 1..2000); Features/Profile/FindFriendsView.swift lines 84-86; Features/CourseDetail/CourseDetailView.swift lines 211-213.

**Recommendation:** Show an inline error in the review sheet on save failure, add a character counter with a 2000 cap on the TextEditor, and surface follow/bookmark failures (e.g., brief alert or revert with haptic).

**Verifier:** Confirmed. WriteReviewSheet.swift:59-61 is an empty catch on save ('Keep the sheet open so the text isn't lost') and 64-69 an empty catch on delete; the sheet has no character counter or limit anywhere (lines 12-48), while reviews.sql:6 enforces `check (char_length(body) between 1 and 2000)` and upsert_review will raise — so a >2000-char review is permanently unsavable with Save appearing dead. FindFriendsView.swift:84-86 (FollowButton) and CourseDetailView.swift:211-213 (toggleBookmark) show the same silent-catch pattern; there the button state is left unchanged (a partial mitigation, per the comments), but the user still gets zero feedback that the tap failed. Medium is right: real but recoverable annoyances, with the 2000-char case being a genuine dead end.


### [MEDIUM] Swift ScoreMath diverges from the SQL score view on decimal ties — result screen can show a different score than the list

The done screen (RankResultView) shows a score computed locally with Double math, while every other surface shows the Postgres numeric-computed score. When the raw score lands exactly on x.x5, Double's binary representation falls just below the tie and rounds down, while numeric rounds half-away-from-zero up. I verified this numerically: 38 mismatches across all positions for bucket sizes 1-50, e.g. 'fine' bucket, position 5 of 32: raw = 6.15, Swift shows 6.1, SQL stores 6.2. So a user finishes the comparison flow, sees 6.1 on the celebration screen, then finds 6.2 in their list. The test fixtures (RankingEngineTests.scoreFormulaMatchesSQLFixtures) only cover 8 non-tie cases, so the claimed parity guarantee is not actually enforced.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/RankingEngine.swift lines 89-93 (`(raw * 10).rounded() / 10` on Double) vs /Users/leon-an/3Wood/supabase/migrations/00040000000000_rankings.sql lines 114-119 (`round(...::numeric, 1)`); local score shown at LogCourseFlow.swift lines 134-139; verified with a Decimal-vs-Double comparison script (fine 5/32: 6.1 vs 6.2; 38 mismatches for counts <= 50).

**Recommendation:** Compute the tie-safe way in Swift, e.g. do the arithmetic in Decimal (NSDecimalRound .plain) to mirror numeric, or simpler: after saving, fetch the just-inserted row's score from my_ranked_courses and display that. Add tie-case fixtures (e.g. fine 5/32) to RankingEngineTests.

**Verifier:** Confirmed and independently reproduced. RankingEngine.swift:91-92 computes `(raw * 10).rounded() / 10` in Double, while rankings.sql:114-119 computes the identical formula in Postgres numeric (all operands are numeric/int, so exact decimal arithmetic) and rounds half-away-from-zero. I ran my own Decimal-vs-Double script: exactly 38 mismatches across bucket sizes 1-50, including the cited fine 5/32 case (raw 6.15 → Swift shows 6.1, SQL stores 6.2). The locally computed score is what the done screen displays (LogCourseFlow.swift:134-139), so the celebration score can differ by 0.1 from the list. Also confirmed the parity test gap: RankingEngineTests.swift:88-97 has only 8 fixtures, none landing on a .x5 tie, despite the comment in rankings.sql:108-109 claiming cross-checked parity. Medium is correct — a real, documented-invariant violation visible to users, but a rare 0.1 cosmetic inconsistency, not data corruption.


### [MEDIUM] Course detail's community rating is a stale snapshot — after ranking, the same screen still says 'No ratings yet — be the first!'

CourseDetailView holds `let course: Course` and never refetches it. reloadMyRanking (which runs after the log flow dismisses) refreshes myRanking, friends and reviews — but the community card and its avg-score badge come from the immutable `course` value captured when the row was tapped. So the very action the screen encourages ('be the first!') produces contradictory UI: 'Your score 8.4' directly above 'Community rating — No ratings yet — be the first!'. The same staleness applies after any ranking to ratingCount/avgScore shown on this screen.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift line 5 (`let course: Course`), lines 55-74 (community card reads course.ratingCount / course.avgScore), lines 188-197 (reloadMyRanking refreshes everything except the course row). CourseRepo.course(id:) already exists (Core/Repositories/CourseRepo.swift lines 22-27) but is not used here.

**Recommendation:** In reloadMyRanking, also refetch the course via CourseRepo.course(id:) into a @State copy and drive the community card (and header) from it.

**Verifier:** Verified against /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift: line 5 `let course: Course` is immutable; the community card (lines 55-74) reads course.ratingCount/course.avgScore from it; reloadMyRanking (lines 188-197) refreshes myRanking, bookmark, friends, and reviews but never the course. CourseRepo.course(id:) exists unused (Core/Repositories/CourseRepo.swift lines 22-27). I also confirmed the contradiction actually occurs: the course_community_ratings view (supabase/migrations/00040000000000_rankings.sql lines 124-128) averages ALL users' scores including the logger's own, so after the log flow dismisses, 'Your score' appears (myRanking is refreshed) directly above a still-stale 'No ratings yet — be the first!'. Medium is correct: a visible self-contradiction in the core log flow, but it self-corrects on next navigation and loses no data.


### [MEDIUM] courses_in_region LIMIT 250 with no ORDER BY silently drops an arbitrary subset in dense areas

The map region query caps at 250 rows with no ordering, so when a viewport contains more than 250 courses (any state jump — the zoom-hint threshold is 12 degrees latitude and e.g. the California jump spans ~11.4, so thousands of courses qualify; also metro areas like Phoenix/LA at moderate zoom), Postgres returns an arbitrary 250. Pins for well-known courses can simply be missing with no indication, and results can differ between pans. The list mode then presents this arbitrary subset 'sorted by community score' as if it were the complete ranked list for the area.

**Evidence:** /Users/leon-an/3Wood/supabase/migrations/00040000000000_rankings.sql lines 184-195 (`limit 250`, no order by); /Users/leon-an/3Wood/3Wood/Features/Map/MapViewModel.swift line 11 (maxUsefulSpan = 12); Features/Map/CourseMapView.swift lines 189-201 (state jump spans up to ~11.4 deg so pins render) and line 146 (list sorts the truncated subset by avgScore).

**Recommendation:** Add `order by r.rating_count desc nulls last, c.id` (rated courses first) so truncation is deterministic and keeps the most relevant pins, and/or lower maxUsefulSpan; consider surfacing 'showing 250 of N' in list mode.

**Verifier:** All citations check out: migration 00040000000000_rankings.sql lines 184-195 show `limit 250` with no ORDER BY; MapViewModel.swift line 11 has maxUsefulSpan = 12 and regionChanged fetches regardless of span; CourseMapView.swift jump(to:) (lines 189-201) yields ~11.4 deg latitude for California (9.5 * 1.2), under the hint threshold, so pins render from the truncated set; line 146 sorts that arbitrary subset by avgScore in list mode. I checked whether this is the known small-seed-data non-issue and it is not: seed.sql explicitly states the ~15 demo courses precede 'the full ~16k-course import (scripts/seed_courses.py)', and that script exists in /Users/leon-an/3Wood/scripts/ — so viewports exceeding 250 courses (California alone has ~900+) are the intended production condition. Latent today but guaranteed at the planned import; medium is right.


### [MEDIUM] Sign-up will dead-end on hosted Supabase if email confirmations are on

EmailSignInView.submit relies entirely on SessionStore reacting to an auth state change after signUp. On local dev (confirmations off) signUp returns a session and this works. On a default hosted Supabase project, email confirmation is enabled: signUp returns a user with no session and emits no signedIn event — the button spinner stops and literally nothing happens, with no 'check your email' message. Since the stated next milestone is moving to hosted Supabase, this is a pre-launch trap that will look like a total signup outage.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift lines 63-74 (no handling of the confirm-email case; comment 'nothing else to do'); Core/Supa.swift lines 10-13 (local-only config, hosted swap planned).

**Recommendation:** After signUp, check whether the response contains a session; if not, show a 'Confirm your email, then sign in' state. Alternatively disable email confirmation deliberately on the hosted project and document it.

**Verifier:** Verified end to end. EmailSignInView.swift lines 63-74 discard the signUp response ('SessionStore reacts to the auth state change; nothing else to do') and SessionStore only transitions on auth events. In the vendored SDK, _signUp (AuthClient.swift lines 434-446) emits .signedIn only when response.session is non-nil; with email confirmation enabled — the hosted Supabase default — session is nil, no event fires, so the spinner stops and the screen shows nothing: no error, no 'check your email'. Local config.toml has no enable_confirmations override, matching the works-locally/breaks-hosted trap, and MEMORY.md confirms hosted Supabase is the next milestone. Medium is the right call: it would be high if live today (total signup outage), but it is pre-launch, deterministic to hit in the first hosted test, and fixable with either a one-line response check or a dashboard toggle.


### [LOW] Tapping 'Write a review' before reviews finish loading silently overwrites an existing review

myReview is computed from `reviews`, which loads asynchronously in reloadMyRanking (and is empty if that fetch failed). If the user taps the button before the reviews arrive — easy on a slow connection — the sheet opens in 'Write a review' mode with a blank editor and no Delete button; saving hits upsert_review's ON CONFLICT and replaces their existing review, which they never saw. Their previous text is unrecoverably lost.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift line 14 (myReview from async-loaded reviews), lines 134-138 and 149-151 (sheet gets `existing: myReview?.body`); supabase/migrations/00110000000000_reviews.sql lines 50-53 (upsert overwrites).

**Recommendation:** Disable the Write/Edit button until the reviews fetch has completed (success or failure), or have WriteReviewSheet fetch the caller's current review itself before enabling Save.

**Verifier:** Verified in code. CourseDetailView.swift:14 derives myReview from the async-loaded `reviews` array (populated only at reloadMyRanking line 196, and blanked to [] on fetch failure via `try? ... ?? []`). Lines 135 and 149 drive both the button label and the sheet's `existing:` from it; WriteReviewSheet.swift:47 seeds the editor from `existing` and line 28 hides Delete when nil. upsert_review in 00110000000000_reviews.sql:50-53 does ON CONFLICT DO UPDATE on body, so saving a blank-mode review does replace an unseen prior one. Severity low is fair: it is unrecoverable data loss, but the window is a single network round-trip on a screen the user just opened, and requires the user to already have a review on that course.


### [LOW] Your own profile reached from the Leaderboard shows a non-functional Follow button for yourself

LeaderboardView lets you tap your own (highlighted 'isMe') row, which pushes OtherProfileView; unlike PeopleListView (which hides FollowButton when person.id == myID), OtherProfileView renders FollowButton unconditionally. Tapping 'Follow' on yourself violates the DB check constraint (follower_id <> followee_id), the error is swallowed, and the button just never responds — it looks broken.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift lines 38-43 (no isMe gate on navigation); Features/Profile/OtherProfileView.swift line 21 (unconditional FollowButton); contrast Features/Profile/PeopleListView.swift lines 85-87; supabase/migrations/00060000000000_follows.sql line 7 (check constraint).

**Recommendation:** In OtherProfileView, hide the FollowButton (or route to the own-profile screen) when person.id equals the signed-in user's id, mirroring PeopleListView.

**Verifier:** Verified. LeaderboardView.swift:38-43 wraps every row (including isMe rows, which are only styled differently at lines 23/36) in an onTapGesture that pushes OtherProfileView; OtherProfileView.swift:21 renders FollowButton unconditionally, unlike PeopleListView.swift:85-87 which gates on `person.id != myID`. 00060000000000_follows.sql:7 has `check (follower_id <> followee_id)`, and FollowButton's catch (FindFriendsView.swift:84-86) swallows the resulting error, so the button silently does nothing. Real but cosmetic-broken-control on your own row only; low is correct.


### [LOW] Follow-state race in OtherProfileView can overwrite the user's tap and wedge the button

OtherProfileView arrives with isFollowing hard-coded false (from Leaderboard) and corrects it via an async isFollowing fetch. If the user taps Follow before that fetch (issued at view load, pre-follow) returns, the stale response overwrites person.isFollowing back to false. The button then shows 'Follow' while the follow row already exists; the next tap attempts a duplicate insert, throws on the primary key, is silently caught, and never toggles — the button is stuck showing the wrong state until the view is recreated.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Profile/OtherProfileView.swift lines 61-69 (task overwrites person.isFollowing after load) combined with FindFriendsView.swift lines 75-88 (FollowButton toggle + silent catch); LeaderboardView.swift lines 39-42 (isFollowing: false seed).

**Recommendation:** Only apply the fetched isFollowing if the user hasn't interacted yet (e.g., fetch before enabling the button, or compare against a generation counter). Treating a unique-violation on follow as success ('already following') would also self-heal.

**Verifier:** Verified, and the race window is actually wider than claimed: OtherProfileView.swift:61-69 awaits statsTask and rankedTask before applying the followingTask result to person.isFollowing (lines 67-68), so the stale-false overwrite (seeded by LeaderboardView.swift:41 `isFollowing: false`) can land after a user's successful Follow tap any time until all three fetches complete. The next tap then attempts a duplicate insert on the (follower_id, followee_id) primary key (00060000000000_follows.sql:6), which the silent catch in FollowButton (FindFriendsView.swift:83-86) swallows without toggling, wedging the label at 'Follow' until the view is recreated (the .task fetch then self-heals it). Real but requires tapping within the initial-load window; low is right.


### [LOW] ListsView triggers duplicate concurrent reloads (.task + .onAppear, plus onDismiss)

ListsView attaches both `.task { await reload() }` and `.onAppear { Task { await reload() } }` to the same view — both fire on every appearance, doubling the my_ranked_courses and my_want_to_play requests each time the tab is shown; dismissing the log flow adds a third via fullScreenCover onDismiss while onAppear also fires. Harmless today, but the racing responses can apply out of order (last-writer-wins between identical queries), and it doubles backend load on the app's most-visited data.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift lines 47-55 (onDismiss reload, .task reload, .onAppear reload all present).

**Recommendation:** Keep only `.task` (it re-runs on each appearance and cancels on disappear); keep the onDismiss reload only if the cover can dismiss without triggering reappearance.

**Verifier:** Verified. ListsView.swift:47-55 attaches all three: fullScreenCover onDismiss { Task { reload() } }, .task { await reload() }, and .onAppear { Task { await reload() } }. Both .task and .onAppear fire on every appearance (tab switches included), doubling the my_ranked_courses + want-to-play fetches, and reload()'s last-writer-wins assignments (lines 118-119, `?? ranked` fallback) mean racing identical responses can apply out of order — though since they are the same query the user-visible risk is negligible. Correctly rated low: pure redundancy/efficiency cleanup, fix is deleting the .onAppear block.


**Refuted in verification (not real issues):**

- Token-refresh failure leaves the app 'signed in' with every request failing silently — verifier: Refuted on its stated mechanism and its severity-driving claim. The supabase-swift AuthChangeEvent enum (SourcePackages/checkouts/supabase-swift/Sources/Auth/Types.swift lines 4-28) contains exactly 8 cases and NO tokenRefreshFailure — that event does not exist in this SDK, so it cannot 'hit default

## Functionality — Visible QA

**Strengths (keep these):**

- Score badge system is consistent and correct everywhere it appears: identical thresholds (green >= 6.7, gold 3.4-6.7, gray dash for unrated) across Lists, Search, Course Detail, friends' scores, Feed, and Map, with monospaced digits and legible contrast in both light and dark (ScoreBadge.swift is a single source of truth).
- Cross-screen data coherence is excellent: Spyglass 9.8/#1 and Pebble Beach 9.5/#2 agree across Lists, Log Result, Course Detail, and Feed; friends' scores on Course Detail match the exact accounts in the Following list; own-review 'You' chip and 'Edit' affordance appear only for the signed-in user's review.
- Leaderboard tie handling uses proper competition ranking (1,1,1,4,5,6,6,8,9,10) with gold top-rank numbers and a clearly highlighted 'You' row — do not change.
- Map empty/loading affordances are genuinely good: 'Zoom in to explore courses' hint at continental zoom (with code comment showing the blob problem was deliberately considered), a removable filter chip whose filtering is verifiably correct (Private filter excludes Semi-Private rows), and list/map mode toggle.
- Dark mode parity on the captured screens is faithful and high-contrast: green tints, gold ranks, red destructive actions, and badges all read correctly on dark surfaces with no clipped or invisible text.
- Keyboard scenes are handled well: search fields stay visible above the keyboard on Search, Find Friends, and the Log picker (which smartly docks its field directly above the keyboard), with no layout jumps or obscured results.
- Review editing flow is complete and safe: Edit sheet pre-fills the existing text, offers Cancel/Save, and includes a clearly destructive 'Delete review'; the no-reviews state has friendly copy plus a 'Write a review' CTA.
- The comparison step ('Which did you like more?') includes both a NEW badge on the course being placed and a 'Too close to call' escape hatch with progress copy ('A few more to place this course') — thoughtful ranking UX worth preserving.


### [HIGH] City-level map is buried under overlapping blank gray markers for unrated courses

After a city jump (Scottsdale, AZ), dozens of unrated courses each render a compact ScoreBadge containing only a dash. The gray capsules overlap into large merged blobs that hide streets, course labels, and even each other; only the single rated course (green 8.4) is legible. The zoom-hint gate in CourseMapView only suppresses pins at continental zoom — at city zoom there is no clustering, thinning, or distinct (smaller/outlined) treatment for unrated pins, so the core 'explore courses on the map' promise is visually broken in any course-dense metro.

**Evidence:** /tmp/3wood-review/shots-light/23-Map-CityJump_0_5D6C680F-934E-4B8E-8023-B79D1AF34804.png — the map area is covered in gray dash-capsules merged into blobs (verified at full resolution via a 300,800-1000,1400 crop). Code: /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift lines 82-92 (Annotation renders ScoreBadge(score: course.avgScore, compact: true) for every course once !showZoomHint) and /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift lines 10, 21 (nil score renders '–' on .gray).

**Recommendation:** At city zoom, render unrated courses as a small dot or thin-outlined pin instead of a full '–' badge, and add density handling (MapKit clustering or a cap with 'N more — zoom in'). Keep the full score capsule only for rated courses.

**Verifier:** Verified. 23-Map-CityJump_0_5D6C680F....png shows the Scottsdale map covered in gray '–' capsules merged into large blobs; only the one rated course (green 8.4) is legible and street/course labels are hidden. Code confirms the mechanism: /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift lines 82-92 render ScoreBadge(compact: true) for every filtered course once !showZoomHint (the inline comment even admits badges 'read as dark blobs' but only gates continental zoom), and /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift renders '–' on .gray for nil scores with no smaller treatment or clustering. This breaks the map-exploration promise for real users in any course-dense metro, so high is correct.


### [MEDIUM] Both Feed captures (light and dark) are obscured by the iOS 'Save Password?' system sheet

The only evidence for the Feed tab in both appearances has an iOS password-autofill sheet covering the middle third of the screen, hiding 3-4 feed rows. The UI test types a password into a secure field with no interruption monitor and without disabling password autofill, so the system prompt fires mid-run. Beyond making the Feed unreviewable, this prompt can steal taps and make the whole capture suite flaky.

**Evidence:** /tmp/3wood-review/shots-light/18-Feed_0_A9309486-A162-4958-8899-C644932F7D83.png and /tmp/3wood-review/shots-dark/dark-18-Feed_0_863972FA-D6C9-47F9-B03A-FC751A5C2C73.png — 'Save Password?' sheet with Not Now/Save centered over the feed in both. Code: /Users/leon-an/3Wood/3WoodUITests/NavigationUITests.swift lines 57-59 (types 'testpass123' into app.secureTextFields.firstMatch with no addUIInterruptionMonitor and no autofill mitigation).

**Recommendation:** In the UI test setup, disable password autofill (e.g. simulator defaults / associated-domains-free test bundle ID) or add an interruption monitor that taps 'Not Now', then recapture Feed in both appearances.

**Verifier:** Verified. 18-Feed_0_A9309486....png and dark-18-Feed_0_863972FA....png both show the 'Save Password?' sheet (Not Now/Save) covering the middle third of the feed, hiding several rows. Code confirms the cause: /Users/leon-an/3Wood/3WoodUITests/NavigationUITests.swift lines 57-59 type 'testpass123' into app.secureTextFields.firstMatch, and a grep of the whole 3WoodUITests target finds no addUIInterruptionMonitor or autofill mitigation. Note this is a test-infrastructure issue, not an app bug users hit (the prompt is normal iOS behavior), but it leaves the Feed tab with zero usable evidence in either theme and can steal taps mid-run, so medium (clear improvement to the capture pipeline) is right.


### [MEDIUM] Profile stats row layout is broken by List-injected disclosure chevrons

On both own Profile and other-user profiles, the Played/Followers/Following bar shows a stray chevron floating in empty space between 'Followers' and 'Following' plus a second chevron at the trailing edge, with wildly uneven gaps (Played and Followers packed left, Following pushed right). Cause: ProfileStatsBar's two NavigationLinks live inside a List row, so List stretches each link and appends its own disclosure indicator. It reads as a rendering glitch, and 'Played' (not tappable) is visually indistinguishable from the tappable stats.

**Evidence:** /tmp/3wood-review/shots-light/06-Profile_0_C2DBDEC1-3E1E-48F0-A257-912948FF5605.png and /tmp/3wood-review/shots-light/08-OtherProfile_0_50D39496-6602-4E1A-AC60-D7B31871E7D1.png (same in dark-06/dark-08) — chevron mid-gap after '3 Followers', second chevron at far right; confirmed via full-res crop (60,700-1150,900). Code: /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift lines 10-24 (NavigationLinks in HStack) embedded in List rows at /Users/leon-an/3Wood/3Wood/Features/Profile/ProfileView.swift line 21 and OtherProfileView.swift line 25.

**Recommendation:** Use Button + navigationDestination (or NavigationLink with .buttonStyle(.plain) wrapped so List doesn't decorate it, e.g. place the bar in a plain Section row with hidden accessories) and lay out the three stats with equal flexible spacing; add a subtle affordance only on the tappable stats.

**Verifier:** Verified. 06-Profile_0_C2DBDEC1....png shows '16 Played' and '3 Followers' packed left, a chevron floating in empty space mid-row, '4 Following' pushed right, and a second chevron at the trailing edge; 08-OtherProfile_0_50D39496....png shows the identical glitch. Code confirms: ProfileStatsBar in /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift lines 9-25 puts two NavigationLinks in an HStack, and it is embedded inside List rows in ProfileView.swift (Section VStack) and OtherProfileView.swift, so List stretches the links and appends its own disclosure indicators. It visibly reads as broken on both profile screens and 'Played' is indistinguishable from the tappable stats; medium is appropriate.


### [MEDIUM] Bucket picker uses system orange/red instead of the design-system SunriseGold/ClayRed

'It was fine' and 'Didn't like it' buttons are bright system .orange and .red, visibly clashing with the muted vintage palette used everywhere else (score badges use sunriseGold #D9A441 and clayRed #B3402F). The same semantic tiers therefore have two different colors in the same flow: pick a mid bucket on a saturated orange button, then see the resulting score in muted gold.

**Evidence:** /tmp/3wood-review/shots-light/11-Log-BucketPicker_0_9C171F22-7042-4E62-A207-D3D9D785844D.png — saturated orange/red buttons vs muted badge colors in 01/02. Code: /Users/leon-an/3Wood/3Wood/Features/Ranking/BucketPickerView.swift lines 33-39 (case .fine: .orange; case .disliked: .red) vs /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift lines 20-27 (.sunriseGold / .clayRed).

**Recommendation:** Change BucketPickerView.color(for:) to .sunriseGold and .clayRed so bucket colors match the score-badge tiers and the Refined Classic palette.

**Verifier:** Verified in code and screenshot. BucketPickerView.swift lines 33-39 literally use '.fine: .orange' and '.disliked: .red' while ScoreBadge.swift lines 23-25 use .sunriseGold/.clayRed for the same semantic tiers. Screenshot 11-Log-BucketPicker shows saturated system orange and red capsules that clash with the muted vintage palette; notably the 'Liked it' button correctly uses .fairwayGreen, so this is an inconsistency, not a deliberate choice. Directly violates the owner's flat/vintage 'Refined Classic' taste in the app's core logging flow, and the same tier changes color between bucket pick and resulting score badge. Medium is the correct severity: clear improvement, one-line fix, but not user-blocking.


### [MEDIUM] Imported course names have wrong title-casing ('Tpc', capital 'At') shown throughout the UI

Course names from the OpenGolfAPI import appear naively title-cased: 'Tpc Myrtle Beach' (should be 'TPC'), 'Black At Bethpage State Park', 'Apache Course At Desert Mountain Golf Club', 'Cougar Point At Kiawah Island' (mid-name 'At' should be lowercase). These are real production-bound names, not wd_* seed throwaways, and they appear on Search, Lists, Map list, and profiles. A cleanup migration already exists for the stripped-trademark 'tm' artifact but not for casing.

**Evidence:** /tmp/3wood-review/shots-light/03-Search-Results_0_EEF72A1C...png ('Tpc Myrtle Beach'), /tmp/3wood-review/shots-light/16-Map-ListView_0_0A9DEA36...png ('Anthem Golf & Country Club', 'Apache Course At Desert Mountain Golf Club'), 01-Lists-Played rows 5/7. Code: /Users/leon-an/3Wood/supabase/migrations/00090000000000_course_name_cleanup.sql handles only the 'tm' regex, no casing fixes.

**Recommendation:** Add a follow-up migration normalizing known acronyms (TPC, GC, CC) to uppercase and connector words (At, Of, The, And) to lowercase mid-name, mirroring the existing cleanup-migration pattern.

**Verifier:** Verified in multiple screenshots: 03-Search-Results shows 'Tpc Myrtle Beach' and 'Dunes At Monterey Peninsula Country Club'; 16-Map-ListView shows 'Apache Course At Desert Mountain Golf Club', 'Birdie Ranch At Silver Creek', 'Chiricahua Course At Desert Mountain Golf Club'; 01-Lists-Played rows 5 and 7 show 'Black At Bethpage State Pa...' and 'Cougar Point At Kiawah Isla...'. These are imported real-course names, not the excluded wd_* seed-account quirk, and course names are the product's core content. The cited migration 00090000000000_course_name_cleanup.sql only fixes the stripped-'tm' artifact (single regexp_replace, lines 4-6), confirming no casing normalization exists. Medium is right: visible on nearly every screen and undermines credibility pre-App-Store, but not functionally breaking.


### [MEDIUM] Search ranking places weak token matches above location-relevant results

Searching 'pebble beach' correctly puts Pebble Beach Golf Links first, but the #2 result is 'Pebble Creek, Lexington, OH' (matches only 'Pebble') ahead of 'Dunes At Monterey Peninsula Country Club', which is actually located in Pebble Beach, CA (bottom of the visible list). Any-token matching outranks whole-phrase/city relevance.

**Evidence:** /tmp/3wood-review/shots-light/03-Search-Results_0_EEF72A1C-C1B4-4FD4-848B-AA8EE2FC9309.png — result order: Pebble Beach Golf Links, Pebble Creek (OH), Tpc Myrtle Beach, Pebble Brook (IN), Pelican Beach (NE), Dunes At Monterey Peninsula CC.

**Recommendation:** Boost whole-phrase matches and city/state matches above single-token name matches in the search ranking (e.g. weight city ilike match at least as high as a partial name token).

**Verifier:** Verified in both the screenshot and the code. 03-Search-Results_0_EEF72A1C-C1B4-4FD4-848B-AA8EE2FC9309.png shows exactly the claimed order: Pebble Beach Golf Links (8.8) first, then Pebble Creek (Lexington, OH), Tpc Myrtle Beach, Pebble Brook (IN), Pelican Beach (NE), with Dunes At Monterey Peninsula Country Club — located in Pebble Beach, CA — last. Root cause confirmed at /Users/leon-an/3Wood/supabase/migrations/00040000000000_rankings.sql:164-168: search_courses matches on name ilike OR trigram similarity OR city/state ilike, but orders solely by extensions.similarity(c.name, p_query) desc, so city-matched courses always sink to the bottom. This is real ranking logic, not seed data, and it degrades every city-based query (searching a city name orders results by name-similarity to the city string, which is near-random). Severity upgraded from low to medium: Search is a primary tab and location-based discovery is a core use case for a course-logging app, though the flagship phrase match did land at #1.


### [LOW] Ranked-list rows truncate long course names to one line, inconsistently with Search and Map list

My Courses (Played) and other-profile course lists clip names: 'Black At Bethpage State Pa...', 'Cougar Point At Kiawah Isla...'. The same names wrap fully to two lines in Search results and the Map list ('Anthem Golf Country Club Ironwood Course'). On the ranking screens — the app's core artifact — the identifying part of the name (which Bethpage course? which Kiawah course?) is lost.

**Evidence:** /tmp/3wood-review/shots-light/01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png rows 5 and 7; /tmp/3wood-review/shots-light/08-OtherProfile...png row 2; contrast with /tmp/3wood-review/shots-light/16-Map-ListView_0_0A9DEA36...png (2-line wrap). Code: /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:80 and Features/Profile/OtherProfileView.swift:43 use .lineLimit(1) while Features/Search/SearchView.swift:46 uses .lineLimit(2).

**Recommendation:** Change ranked-list rows to .lineLimit(2) to match Search/Map list, or add middle truncation; verify row height still aligns the rank number and score badge.

**Verifier:** Verified but overstated. 01-Lists-Played_0_07C245AF....png rows 5 and 7 show 'Black At Bethpage State Pa...' and 'Cougar Point At Kiawah Isla...'; 08-OtherProfile row 2 shows the same truncation; 16-Map-ListView and 03-Search-Results show full 2-line wraps ('Anthem Golf Country Club Ironwood Course', 'Dunes At Monterey Peninsula Country Club'). Code confirms: ListsView.swift and OtherProfileView.swift use .lineLimit(1) while SearchView.swift uses .lineLimit(2). However, the claim that the identifying part is lost ('which Bethpage course?') misreads the evidence: the distinguishing token ('Black At...', 'Cougar Point At...') leads the name and survives truncation, and the location subtitle ('Farmingdale, NY', 'Kiawah Island, SC') disambiguates further. So this is a real cross-screen inconsistency and polish issue, not an information-loss problem — downgraded from medium to low.


### [LOW] List content readable beneath the floating tab bar; score badge bleeds through the Profile tab highlight

On scrollable lists, the row behind the floating tab bar is cut mid-glyph and the next row ('Oakmont Country Club' with its 6.9 badge) remains readable in the home-indicator area below the bar. A green score capsule from the covered row also shows through/around the translucent Profile tab highlight, looking like a green glow on the Profile item. No scroll-edge fade or bottom content margin softens the collision.

**Evidence:** /tmp/3wood-review/shots-light/01-Lists-Played_0_07C245AF...png bottom edge (verified via crop 0,2300-1206,2622: 'Bandon Sheep Ranch' bisected, row-10 'Oakmont Country Club 6.9' fully readable below the bar, green capsule visible behind the Profile tab). Same pattern in dark-01.

**Recommendation:** Add a bottom content margin / safeAreaInset matching the tab bar height plus a scroll-edge material or gradient so rows fade out instead of rendering crisply beneath the bar.

**Verifier:** Verified by cropping 01-Lists-Played_0_07C245AF...png at full resolution (y 2200-2622): 'Bandon Sheep Ranch' is bisected mid-glyph by the floating bar with 'Randolph, OR' ghosting through it, row 10 'Oakmont Country Club' with its 6.9 badge is fully readable in the home-indicator area below the bar, and a green score capsule bleeds through beside the Profile tab item, reading as a stray green glow/badge on Profile. The claim is accurate and not standard translucent-bar behavior done well, since there is no fade or content margin. Low severity is correct: a polish/finish issue that does not impair function.


### [LOW] Log-flow result screen has unbalanced vertical layout

On the 'All set!' confirmation, the title sits alone at the very top (directly under the status bar) while the course name, 9.8 badge, and '#1 of your "Liked it" courses' cluster sits slightly below center, leaving a large dead zone between them. The moment of payoff for the app's core loop reads as unfinished compared to the tight composition of the comparison step.

**Evidence:** /tmp/3wood-review/shots-light/13-Log-Result_0_32145F14-D4A6-4A15-868E-F370214C61F3.png — 'All set!' at y≈190/2000 with empty space until the course block at y≈860.

**Recommendation:** Group 'All set!' with the course/score block in one centered VStack (or move the title just above the block) so the confirmation reads as a single composition above the Done button.

**Verifier:** Verified in 13-Log-Result_0_32145F14...png: 'All set!' sits alone at roughly y=190/2000 directly under the status bar, followed by empty space until the Spyglass Hill / 9.8 badge / '#1 of your Liked it courses' cluster at roughly y=860-1170, then another large gap before the Done button. The screenshot matches the description; the title reads as disconnected from the payoff block. This is the reward moment of the core loop, but it is a composition nit with a simple fix and no functional impact, so low is the right severity. Note as a strength not to lose: the result block itself (course name, fairway-green 9.8 capsule, rank caption) is well composed and on-palette.


### [LOW] Dark-mode capture coverage is incomplete: no dark evidence for 12 of the 24 screens

Dark captures exist only for screens 01-09, 18, and 19. The entire log flow (picker, bucket picker with its custom button tints, comparison, result), Following list, Map list/filter/city-jump, Reviews, Write Review, and Welcome have no dark screenshots, so dark regressions there (custom colors, material overlays, keyboard scenes) are unverifiable from this evidence set.

**Evidence:** ls /tmp/3wood-review/shots-dark shows only dark-01 through dark-09, dark-18, dark-19 (11 screen PNGs) versus 24 light PNGs in /tmp/3wood-review/shots-light.

**Recommendation:** Extend the dark-mode capture run to cover the log flow, map sub-states, and review screens — these use the most custom color work and are the likeliest dark-mode regression points.

**Verifier:** Verified by ls: /tmp/3wood-review/shots-dark contains only dark-01 through dark-09, dark-18, and dark-19 (11 screen PNGs) versus 24 light screen PNGs. Minor correction: 13 screens lack dark evidence (00-Welcome, 10-17 log flow/following/map sub-states, 20-23 reviews/map controls), not 12. The substantive claim stands — the log flow (custom bucket-picker tints), map list/filter/city-jump, and review screens have zero dark-mode evidence, so dark regressions there are unverifiable. Severity low is correct: this is a review-evidence gap, not a demonstrated user-facing defect.


### [LOW] Capture run records a test-failure attachment from a supabase-swift auth session warning

Both light and dark runs attach a 'Complete Issue Description.txt' marked isAssociatedWithFailure=true on NavigationUITests/testFeedAndLeaderboard, containing the supabase-swift warning about the initial session being emitted after refreshing the locally stored session (behavior changing in the next major release). Not user-visible today, but it flags the capture test as failed and is a forward-compat risk for session restore on app launch.

**Evidence:** /tmp/3wood-review/shots-light/Complete Issue Description.txt.png and /tmp/3wood-review/shots-dark/dark-Complete Issue Description.txt.png (text: 'Initial session emitted after attempting to refresh the local stored session... set emitLocalSessionAsInitialSession: true'; see supabase/supabase-swift PR #822); /tmp/3wood-review/shots-light/manifest.json marks the attachment isAssociatedWithFailure: true.

**Recommendation:** Opt in to emitLocalSessionAsInitialSession: true in the AuthClient configuration (adding the recommended session.isExpired check) so the warning-triggered failure disappears and behavior is stable across the supabase-swift major upgrade.

**Verifier:** Verified. '/tmp/3wood-review/shots-light/Complete Issue Description.txt.png' is a text attachment containing verbatim the supabase-swift warning ('Initial session emitted after attempting to refresh the local stored session... set emitLocalSessionAsInitialSession: true... Check https://github.com/supabase/supabase-swift/pull/822'), and manifest.json marks it isAssociatedWithFailure: true under NavigationUITests/testFeedAndLeaderboard(). The recommendation is applicable: /Users/leon-an/3Wood/3Wood/Core/Supa.swift:16-19 constructs SupabaseClient with no auth options, so the opt-in is not set. Not user-visible today, but a real forward-compat risk for session restore across the next supabase-swift major release and a false-failure in the capture suite. Low is the right severity.


## Usability (Heuristic Evaluation)

**Strengths (keep these):**

- Log flow modal is protected against accidental dismissal: interactiveDismissDisabled() plus an explicit Cancel button (LogCourseFlow.swift:58-66) — the right error-prevention call for a multi-step flow.
- Account deletion is a model destructive-action pattern: confirmation dialog with explicit, concrete consequences ('permanently removes your profile, rankings, and lists') and a real error alert on failure (ProfileView.swift:55-73). Extend this pattern elsewhere; don't change it.
- Community averages are explicitly labeled 'avg' under the badge and unrated courses say 'Not rated' (SearchView.swift:62-74, visible in 03-Search-Results), preventing confusion with personal scores; the 'You' chip on the user's own review (CourseDetailView.swift:165-171) serves the same recognition goal.
- Empty states are mostly actionable ContentUnavailableViews with a next step — 'Log your first course' button on empty Played (ListsView.swift:61-69), 'Find friends' on empty Feed — rather than dead text.
- The map's 'Zoom in to explore courses' hint plus suppressing pins at continental zoom (CourseMapView.swift:82-92,101-109, visible in 05-Map) is good status visibility and avoids the pin-soup problem at low zoom.
- Active filter state is always visible and one-tap dismissible via the green chip with an x, in both map and list modes (CourseMapView.swift:116-130, screenshot 17-Map-Filtered) — textbook visibility of system status.
- ScoreBadge color semantics (green/gold/red on the flat vintage palette) are consistent across feed, lists, profiles, map pins, and results, and the thresholds match the ScoreMath bucket ranges exactly.
- WriteReviewSheet disables Save on empty input and deliberately keeps the sheet open on save failure so the user's text isn't lost (WriteReviewSheet.swift:42-44,59-61).
- The leaderboard highlights the current user's row with a tinted background and bold username (LeaderboardView.swift:22-23,36; visible in 19-Leaderboard) so you can always find yourself.
- The ranking interaction itself is low-burden and well-scoped: binary insertion means ~log2(n) questions, the 'NEW' tag clearly marks which course is being placed (ComparisonView/12-Log-Comparison), and re-logging correctly excludes the course itself from comparisons (LogFlowModel.start, LogCourseFlow.swift:103-105).


### [HIGH] No way to remove or un-log a mis-ranked played course

Once a course is logged it is permanent from the UI. The backend supports removal — RankingRepo.remove(courseID:) calls the remove_ranking RPC — but a project-wide grep shows zero UI callers. The Played list uses a plain ForEach with no .onDelete or .swipeActions, and CourseDetailView only offers 'Update my ranking' (re-run the flow), never 'Remove from my courses'. If a user logs the wrong course (easy to do: search results are full of near-identical names like 'Anthem Golf Country Club Ironwood/Persimmon Course' in 16-Map-ListView), it pollutes their ranking, their 0-10 scores for every other course in that bucket, the community average, and the leaderboard count forever. Violates Nielsen #3, User Control and Freedom (no emergency exit / undo for a core action).

**Evidence:** /Users/leon-an/3Wood/3Wood/Core/Repositories/RankingRepo.swift:21-22 (remove exists); grep for 'RankingRepo.remove|remove_ranking' outside Repositories returns nothing; /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:71-93 (ForEach without onDelete); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:93-99 (only 'Update my ranking').

**Recommendation:** Add swipe-to-delete on the Played list rows and a 'Remove from Played' action (with confirmation) on CourseDetailView, both wired to the already-existing RankingRepo.remove.

**Verifier:** Verified in code. RankingRepo.swift:21-23 defines remove(courseID:) calling the remove_ranking RPC, and a project-wide grep confirms zero UI callers (only the definition plus SQL migrations; the CourseDetailView hit is WantToPlayRepo.remove, a different repo). ListsView.swift:72-89 renders the Played list with a plain ForEach — the only confirmationDialog/swipeActions/onDelete hit in the entire app is an unrelated one in ProfileView. CourseDetailView.swift:93-99 offers only 'Log this course' / 'Update my ranking'. 'Update my ranking' can fix a wrong score but cannot un-log a wrong course, so logging the wrong course (plausible given near-duplicate names like the Anthem Ironwood/Persimmon pair visible in 16-Map-ListView) permanently pollutes the user's bucket scores, played count, leaderboard standing, and the community average. Severity high is correct: irreversible damage to the app's core artifact with the fix already built server-side.


### [MEDIUM] A mis-tap in the head-to-head comparison cannot be undone

In the comparison step the entire course card is the button; one accidental tap immediately commits a binary-search answer and advances. RankingEngine has no history — answer() collapses the [lo, hi) window and there is no rewind method — and LogCourseFlow has no Back affordance in .compare or .pickBucket steps. The only recovery is Cancel (losing all answers) and redoing the whole flow. Same problem one step earlier: picking the wrong bucket ('Liked it' vs 'It was fine') is instantly committed with no way back. Because comparisons are the app's core interaction and each answer permanently steers the final 0-10 score, this violates #3 User Control and Freedom and #5 Error Prevention.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:50-75 (full-card tap targets, no undo control); /Users/leon-an/3Wood/3Wood/Features/Ranking/RankingEngine.swift:62-74 (state mutation with no history stack); /Users/leon-an/3Wood/3Wood/Features/Ranking/LogCourseFlow.swift:58-64 (toolbar has only Cancel); screenshot 12-Log-Comparison_0_B15DB4D4-...png shows no back/undo affordance anywhere.

**Recommendation:** Keep an answer history in LogFlowModel (stack of (lo, hi) snapshots) and add a small 'Back' / undo-last-answer button to ComparisonView and a back step from comparison to bucket picker.

**Verifier:** Code and screenshot confirm the mechanics: ComparisonView.swift:53-74 makes each full card a Button with immediate onAnswer; RankingEngine.swift:62-74 collapses the [lo,hi) window with no history stack or rewind; LogCourseFlow.swift:58-64 has only a Cancel toolbar item, and screenshot 12-Log-Comparison_0_B15DB4D4 shows no back/undo affordance. So the finding is real. But 'high' overstates the damage: (1) Cancel discards everything before any save, and flows are short (log2 of bucket size, the screenshot even says 'A few more to place this course'), so redoing costs seconds; (2) the claim that an answer 'permanently steers the final 0-10 score' is wrong — a committed mistake is fully correctable via 'Update my ranking' on CourseDetailView, which re-runs the flow and replaces the old ranking (migration 00040_rankings.sql:83 removes before re-inserting). A real Nielsen #3/#5 friction worth fixing, but recoverable in-product: medium.


### [MEDIUM] Network failures are silently rendered as empty states

Every data load swallows errors with try? and falls through to the empty state: an offline or backend-down user on the Lists tab sees 'No courses yet — Log your first course', on Feed sees 'Your feed is quiet — Follow friends', and Leaderboard shows 'No rankings yet'. The system state (request failed) is indistinguishable from the data state (you truly have nothing), which can even push users toward wrong recovery actions (re-logging courses they already logged). Violates #1 Visibility of System Status and #9 Help Users Recognize, Diagnose, and Recover from Errors.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:115-120 (ranked = (try? await rankedTask) ?? ranked; on first load a failure leaves [] and shows the 'No courses yet' ContentUnavailableView at lines 61-69); /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:54-57; /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:53-56.

**Recommendation:** Track a loadFailed state per screen and show a distinct 'Couldn't load — Retry' ContentUnavailableView (with a retry button) instead of the true-empty state when the fetch throws.

**Verifier:** Verified at all three cited sites: ListsView.swift:118-119 uses try? with '?? ranked' so a first-load failure leaves [] and shows the 'No courses yet — Log your first course' ContentUnavailableView (lines 61-69); FeedView.swift:54-56 does the same with the 'Your feed is quiet' state; LeaderboardView.swift:53-56 falls back to [] and 'No rankings yet'. Real #1/#9 violation. But high overstates it: the '?? ranked'/'?? items' fallbacks preserve previously loaded data within a session, so the false-empty only appears on a cold launch while offline; and the escalation that users would be 'pushed toward wrong recovery actions (re-logging)' doesn't hold, because LogCourseFlow surfaces save failures loudly via its .failed step ('Couldn't save'), so the wrong path fails visibly rather than silently corrupting anything. Distinct 'Couldn't load — Retry' states are a clear improvement, not a core-promise breakage: medium.


### [MEDIUM] First-run dead-end: new users land on an empty Feed that never points at the core action

After signup (00-Welcome flow) a zero-data account lands on the Feed tab (first tab in MainTabView). The empty-feed state only says 'Follow friends to see the courses they play and rank' with a Find Friends button — but a brand-new user has no friends and the product's core promise ('Rank every course you've played', per the Welcome tagline) is never surfaced. Logging the first course requires discovering the Lists tab, whose empty state does have the right CTA, or a course detail page. There is no onboarding step and no global '+' action. The most prominent first-run path (Find friends → search usernames you don't know) is a dead end. Violates #6 Recognition Rather than Recall and general discoverability of the primary task; also #4 Consistency: the tab is labeled 'Lists' but the screen is titled 'My Courses' (screenshot 01), weakening the scent that 'my played courses live there'.

**Evidence:** /Users/leon-an/3Wood/3Wood/App/MainTabView.swift:5-7 (Feed is the default tab); /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:12-20 (empty state offers only 'Find friends'); /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:31-39,61-69 (log action lives behind a '+' toolbar icon on the Lists tab); screenshots 00-Welcome.png and 01-Lists-Played_0_07C245AF-...png ('Lists' tab vs 'My Courses' title).

**Recommendation:** Add a 'Log your first course' primary button to the empty Feed state (alongside Find Friends), and/or a short first-run prompt after username setup that starts LogCourseFlow. Consider renaming the tab to 'My Courses' to match its title.

**Verifier:** Facts check out: RootView.swift:15-18 routes signup → UsernameSetupView → MainTabView with no onboarding step (grep for onboarding/first-run code finds none), MainTabView.swift:5-7 puts FeedView first, and FeedView.swift:12-20's empty state offers only 'Find friends' — a genuine dead end for a friendless new account. The Welcome screenshot confirms the core promise is 'Rank every course you've played.', which the landing screen never surfaces. The Lists-vs-'My Courses' label mismatch is also real (MainTabView.swift:16 vs ListsView.swift:31 and screenshot 01). But 'dead-end' overstates it: the Lists tab's empty state has a prominent 'Log your first course' primary button (ListsView.swift:61-69) plus a '+' toolbar action, one tab tap away, and users who intentionally installed a course-ranking app will explore the tab bar. This is a first-run funnel weakness — the primary CTA is one hop off the landing screen — not an unrecoverable trap: medium. The recommendation (add a log CTA to the empty Feed) is cheap and correct.


### [MEDIUM] Leaderboard is reachable only via an unlabeled trophy glyph, and its metric is unexplained

The leaderboard's single entry point is a bare 'trophy' SF Symbol in the Feed toolbar — no label, no mention anywhere else (not on Profile, not a tab). Users who don't tap unlabeled toolbar icons will never find a headline feature. Once inside, the screen offers no explanation of what is being ranked or over whom: rows just say '17 courses'. Is it global? Friends-only? Courses played this year? Ties produce three '1's then a '4' (standard competition ranking) with no explanation. Violates #6 Recognition Rather than Recall (icon-only entry, hidden scope) and #1 (what does this ranking mean?).

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:37-45 (trophy icon, only entry point — grep shows LeaderboardView referenced nowhere else); screenshot 19-Leaderboard_0_FAE3B8C4-...png (three gold '1' rows, '17 courses', no header/subtitle); /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:29-31.

**Recommendation:** Add a subtitle under the title (e.g. 'Most courses played — everyone on 3Wood') and a second entry point (Profile row or Feed section header 'Leaderboard >'). Keep the trophy but give it an accessibility label and consider a text label in the nav bar.

**Verifier:** Verified. Grep confirms LeaderboardView is referenced only from FeedView.swift:39 — a bare trophy SF Symbol with an accessibilityIdentifier (test-only) and no visible or VoiceOver label. Screenshot 19-Leaderboard_0_FAE3B8C4.png shows exactly what is claimed: three gold '1' rows then '4' (competition ranking), rows reading '17 courses', and no header/subtitle explaining metric or scope. The SQL (supabase/migrations/00100000000000_feed_leaderboard.sql:48-68) confirms it is global across all users ranked by count of ranked courses — none of which the UI states. A headline feature hidden behind one unlabeled icon with an unexplained metric is a fair medium.


### [MEDIUM] The 0-10 score system is never explained; bucket choice silently caps the score

A first-time user answers 'How was Spyglass Hill?' → 'Liked it', taps through two comparisons, and is shown 'All set! 9.8' — a number they never chose and whose origin is never explained anywhere in the app (AboutView contains only version and licenses). Worse, the bucket choice invisibly locks the score range (Liked 6.7-10, Fine 3.4-6.6, Didn't like 0-3.3 per ScoreMath): a golfer who politely picks 'It was fine' for a course they'd give a 7 can never score it above 6.6, and nothing in BucketPickerView (screenshot 11) discloses this. The green/gold/red badge colors carry this meaning but are never keyed. Violates #10 Help and Documentation and #2 Match Between System and the Real World (the system's model of 'fine' ≠ the user's).

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/RankingEngine.swift:79-94 (hidden bucket ranges); /Users/leon-an/3Wood/3Wood/Features/Ranking/BucketPickerView.swift:7-31 (no range hints); /Users/leon-an/3Wood/3Wood/Features/Ranking/RankResultView.swift:10-34 (score shown with no explanation); /Users/leon-an/3Wood/3Wood/Features/Profile/AboutView.swift (no scoring help); screenshots 11-Log-BucketPicker and 13-Log-Result.

**Recommendation:** Show the score range on each bucket button (e.g. 'Liked it · 6.7-10'), and add a one-line explainer on the result screen ('Your score comes from where it ranks among your Liked courses') plus a 'How scores work' entry under About.

**Verifier:** Verified with one overstatement. ScoreMath (RankingEngine.swift:79-94) confirms hidden ranges: 'It was fine' can never exceed 6.6, 'Liked it' spans 6.7-10. BucketPickerView.swift:7-31 and screenshot 11 confirm the buckets show no range hints; AboutView.swift contains only version and licenses. Overstatement: the result screen is not fully opaque — RankResultView:21 and screenshot 13 show '#1 of your "Liked it" courses' beneath the 9.8 badge, partially explaining the score's origin. Still, the numeric mapping and the invisible cap (a user who picks 'fine' for a 7-worthy course is locked below 6.6) are real, undisclosed, and touch the app's core ranking promise. Medium stands, noting the mechanic intentionally mirrors Beli.


### [MEDIUM] Map toolbar is three unlabeled, look-alike glyphs; the state jump behind a flag icon is undiscoverable

The Map screen's toolbar (screenshots 05/22: flag top-left; filter and list.bullet top-right) relies entirely on icon recognition. The flag glyph opens a 51-item US-state jump menu — nothing about a flag says 'browse by state', and golfers may read a flag as a pin/hole marker. The filter (line.3.horizontal.decrease.circle) and list-toggle (list.bullet) sit adjacent and both read as 'lines in a circle' at a glance; there is no segmented Map/List control as iOS users know from Find My or Maps. Discoverability of the list view and of state browsing depends on exploratory tapping. Violates #6 Recognition Rather than Recall and #4 Consistency and Standards (iOS convention is a labeled segmented toggle for map/list).

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:157-185 (modeToggle icon-only, filterMenu icon-only, stateMenu Label with 'flag' renders icon-only in the toolbar); screenshots 05-Map_0_08A56B1B-...png and 22-Map-Controls_0_00C3AC51-...png (three bare glyphs).

**Recommendation:** Replace the mode toggle with a small 'Map | List' segmented control (or at least 'map'/'list.bullet' with text), rename the state menu icon to something location-like with a 'State' text label, and keep the filled-filter-icon state cue (which is good).

**Verifier:** Confirmed. Screenshots 05-Map_0_08A56B1B and 22-Map-Controls_0_00C3AC51 both show exactly three bare glyphs: a flag top-left and filter + list.bullet adjacent top-right, with no text labels. Code matches: CourseMapView.swift:157-164 (modeToggle is an icon-only Button toggling map/list), 166-175 (filterMenu icon-only), 177-185 (stateMenu uses Label("State", systemImage: "flag"), which the screenshot proves renders icon-only in the toolbar). Nothing about a flag communicates 'browse by state', and the map/list toggle lacks the iOS-standard segmented control. One mitigating note: the prominent 'Jump to a city' search field covers part of the geographic-jump need, so state browsing is not the only path — but the finding's core claim stands. Medium is right: discoverability of the list view and state jump depends on exploratory tapping, but the map itself still works without them.


### [MEDIUM] Destructive social/content actions fire instantly with weak affordances and no confirmation

Two cases: (1) Unfollow — the FollowButton renders as plain gray text 'Following' (screenshots 08, 15) that looks like a status label, sits millimeters from the row's navigation tap area (rows use onTapGesture over the whole row), and a single tap unfollows immediately with no confirmation; failures are also swallowed silently. (2) Delete review — 'Delete review' in WriteReviewSheet deletes on first tap with no confirmation, permanently discarding the user's written text. Both violate #5 Error Prevention and #3 User Control and Freedom (no undo), and the label-like button hurts affordance (#6).

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Profile/FindFriendsView.swift:71-93 (borderless, .secondary-tinted 'Following' button, empty catch); /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift:86-93 (FollowButton inside a row whose whole area is onTapGesture navigation); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/WriteReviewSheet.swift:28-33,64-70 (unconfirmed delete, empty catch); screenshots 08-OtherProfile and 15-Following-List (gray 'Following' text).

**Recommendation:** Give the follow button a bordered/capsule style in both states, confirm unfollow (or provide an undo toast), and put a confirmationDialog on 'Delete review' — the pattern already exists for account deletion in ProfileView.swift:55-65.

**Verifier:** Confirmed on every point. FindFriendsView.swift:71-93: FollowButton is .borderless with .secondary tint when following — in screenshots 15-Following-List and 08-OtherProfile it reads as plain gray status text ('Following'), indistinguishable from a label; a single tap unfollows immediately (line 79) and the catch block is empty (85-86), so failures are silent. PeopleListView.swift:76-93: the button sits inside a row whose entire area is .contentShape(Rectangle()) + onTapGesture navigation, millimeters from the chevron, so mis-taps are plausible. WriteReviewSheet.swift:28-33 and 64-70: 'Delete review' deletes on first tap with no confirmation and an empty catch, permanently discarding written text. The recommendation's claim that the confirmation pattern already exists is verified — ProfileView.swift:55-65 has a confirmationDialog for account deletion. Medium is correct: unfollow is recoverable (re-follow), but review deletion destroys user-authored content; still not core-promise-breaking.


### [LOW] 'Too close to call' silently ranks the new course below its opponent

The 'Too close to call' escape hatch does not average or defer — RankingEngine treats it as 'existing course wins' (lo = mid + 1) and immediately terminates the entire binary search, placing the new course just below the current candidate even if several comparisons remained. A user who taps it on the first comparison (against the bucket's median course) thinks they punted one question but has actually pinned the course at roughly mid-table. The label promises neutrality the system doesn't deliver — #2 Match Between System and the Real World, with a dash of #5 Error Prevention since the consequence is invisible.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/RankingEngine.swift:70-73 (case .tooClose: lo = mid + 1; hi = lo — abandons the window); /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:38-41 (plain 'Too close to call' button, no consequence hint); screenshot 12-Log-Comparison.

**Recommendation:** Either only end the search when the window is already small (otherwise continue with the next midpoint), or relabel/subtitle the button to state the outcome ('Place it just below Torrey Pines South').

**Verifier:** Code reading verified (RankingEngine.swift:70-73: case .tooClose sets lo = mid + 1; hi = lo, ending the search and placing the course just below the opponent; ComparisonView.swift:38-41 has no consequence hint), but the severity and framing are overstated. 'Too close to call' semantically means the two courses are equal, and placing the new course adjacent to the tied opponent is precisely that meaning — terminating the search is correct design, not a mismatch; the recommendation to 'continue with the next midpoint' is algorithmically incoherent since the tie answer is itself the placement signal. Nor is the outcome silent: RankResultView immediately shows the final position ('#N of your ... courses'). The surviving kernel is small: users who read the button as 'skip this question' get no hint of the consequence, so a one-line subtitle would be worthwhile polish. Downgrade medium to low.


### [LOW] Comparison progress hint is vague even though the engine knows the count

During ranking, the only progress signal is the static string 'A few more to place this course' until the final question flips to 'Last one'. RankingEngine already computes maxComparisonsRemaining and LogCourseFlow passes it in, but ComparisonView discards the number. For a user with a large bucket (7+ comparisons) there's no sense of how long the modal flow will take, discouraging completion. Violates #1 Visibility of System Status.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:43-45 (comparisonsRemaining used only for a binary 'Last one' check); /Users/leon-an/3Wood/3Wood/Features/Ranking/RankingEngine.swift:57-60 (exact upper bound available); screenshot 12-Log-Comparison ('A few more to place this course').

**Recommendation:** Show 'About 3 more' (or a dot progress indicator) using the value already passed in.

**Verifier:** Confirmed. ComparisonView.swift:43 uses the passed-in comparisonsRemaining only for a binary check: comparisonsRemaining == 1 ? "Last one" : "A few more to place this course" — the actual number is discarded. RankingEngine.swift:56-60 computes maxComparisonsRemaining (log2 upper bound) and even documents it as 'for a progress hint'. Screenshot 12-Log-Comparison shows the vague 'A few more to place this course' string at the bottom. With small demo buckets the flow is short, but for a user with 50+ played courses it is ~6 comparisons with no progress signal. Low is the right severity: it discourages completion slightly but the flow is still short and functional, and the fix is trivial since the value is already plumbed through.


### [LOW] Bucket picker uses system orange/red instead of the app's SunriseGold/ClayRed palette

BucketPickerView tints its buttons .fairwayGreen / .orange / .red. The saturated system orange and red (screenshot 11) clash with the vintage 'Refined Classic' palette used everywhere else — ScoreBadge and the score system correctly use SunriseGold (#D9A441) and ClayRed (#B3402F). Since bucket → score-color is the same semantic mapping, the inconsistency also weakens learnability of the color code (the 'fine' bucket is bright orange here but muted gold on every badge). Violates #4 Consistency and Standards (internal), and the owner's stated aesthetic yardstick.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/BucketPickerView.swift:33-39 (.orange, .red); /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift:20-27 (sunriseGold/clayRed for the same tiers); screenshot 11-Log-BucketPicker_0_9C171F22-...png (bright system orange/red buttons).

**Recommendation:** Tint the buttons .sunriseGold and .clayRed to match the badge semantics and the flat vintage palette.

**Verifier:** Confirmed. BucketPickerView.swift:33-39 tints buckets .fairwayGreen / .orange / .red, while ScoreBadge.swift:20-27 uses .sunriseGold and .clayRed for the exact same semantic tiers (mid/low). Screenshot 11-Log-BucketPicker_0_9C171F22 shows the clash plainly: the 'It was fine' and 'Didn't like it' buttons are saturated stock system orange and red, visibly louder than the muted FairwayGreen button above them and out of key with the vintage 'Refined Classic' palette (SunriseGold #D9A441, ClayRed #B3402F). This directly violates the owner's stated flat/vintage yardstick and is a genuine internal inconsistency (same bucket → different color on badges vs picker). It borders medium because the screen is part of every log flow, but it is a two-line tint change with no functional harm, so low (high-priority polish) is fair.


**Refuted in verification (not real issues):**

- Feed does not refresh after following friends, so the empty state appears broken — verifier: Refuted on mechanism. The cited code is real (FeedView.swift:50 has only .task; .refreshable only on the List at :28), but the claim that '.task does not re-fire' on navigation pop is wrong: .task is appearance-scoped, and a NavigationStack root receives disappear/appear on push/pop, so returning fr

## Convenience & Task-Flow Friction

**Strengths (keep these):**

- Course detail is a genuine hub with no dead ends: log/update ranking, one-tap bookmark toggle in the toolbar, friends' scores, community rating, inline reviews with write/edit, and a map snippet all on one screen (/Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift; screenshot 04-CourseDetail_0_1F5E3373-75B2-432E-9787-3994DA8F628F.png).
- LogCourseFlow accepts an optional course, so 'Log this course' from a detail page correctly skips the picker and drops straight into bucket selection (LogCourseFlow.swift:6-7, 67-71) — the right shortcut exists where it was wired.
- Feed rows navigate directly to the course detail with the score badge inline — the highest-value tap target for a feed item is the default (FeedView.swift:22-26, 47-49).
- The social loop Leaderboard → other profile → their ranked courses → course detail is complete and consistent, with follow buttons available at every people-list surface (LeaderboardView.swift:38-51, OtherProfileView.swift:35-59, PeopleListView.swift).
- 'Too close to call' in the comparison step prevents forced false choices, and re-logging correctly excludes the course itself from its own comparison pool (ComparisonView.swift:38-41; LogCourseFlow.swift:103-105).
- Map/list mode share filter state, the active filter renders as a one-tap clearable chip in both modes, and the zoom hint honestly explains why pins are hidden at continental zoom (CourseMapView.swift:101-130; screenshot 17-Map-Filtered).
- Empty states consistently carry the next action instead of dead-ending: quiet feed → 'Find friends' button, empty played list → 'Log your first course' (FeedView.swift:13-20; ListsView.swift:61-69).
- WriteReviewSheet prefills for edit, keeps the user's text on save failure rather than discarding it, and includes delete — the full review lifecycle lives in one sheet (WriteReviewSheet.swift:28-33, 47, 60).


### [HIGH] No way to remove a mis-logged course — the delete API exists but is never wired to any UI

If a user logs the wrong course (easy to do from a search picker of 16,000 similarly-named courses, e.g. the three 'Anthem Golf' variants visible in the map list), there is no way to undo it. The Played list has no swipe-to-delete or context menu, and CourseDetailView only offers 'Update my ranking', which re-runs the comparison flow — it cannot remove the entry. RankingRepo.remove(courseID:) is fully implemented but has zero call sites in the app.

**Evidence:** /Users/leon-an/3Wood/3Wood/Core/Repositories/RankingRepo.swift:21-23 (remove exists); grep for 'RankingRepo.remove' returns only the definition; /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:71-93 (played rows are plain NavigationLinks, no onDelete/swipeActions — grep across the codebase finds zero swipeActions/onDelete/contextMenu); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:93-99 (only 'Log this course' / 'Update my ranking'); screenshot 14-PlayedRow-Detail_0_58C67550-4BA6-4650-A405-755A534ECC44.png shows the detail with no remove affordance.

**Recommendation:** Add swipe-to-delete (with confirmation) on Played rows in ListsView calling RankingRepo.remove, and/or a 'Remove from my courses' option (context menu or a small destructive row) on CourseDetailView when myRanking != nil.

**Verifier:** Fully confirmed. /Users/leon-an/3Wood/3Wood/Core/Repositories/RankingRepo.swift:21-23 defines remove(courseID:) calling the remove_ranking RPC, and a codebase-wide grep shows its ONLY occurrence is the definition — zero call sites (WantToPlayRepo.remove IS wired, at CourseDetailView.swift:206, which proves the pattern was intended but never finished for rankings). ListsView.swift:71-93 renders Played rows as plain NavigationLinks with no onDelete/swipeActions; grep for swipeActions/onDelete/contextMenu across all Swift files returns nothing. CourseDetailView.swift:93-99 offers only 'Log this course' / 'Update my ranking' (re-runs LogCourseFlow, which can only insert). Screenshot 14-PlayedRow-Detail_0_58C67550...png confirms: 'Your score 9.8', bookmark toggle, and 'Update my ranking' — no remove affordance anywhere. High is correct: a mis-log (plausible among 16k similar names) permanently pollutes the user's ranked list, feed, and the course's community average, with no recovery path despite the backend supporting it.


### [MEDIUM] Log-flow course picker is a blank search box — no nearby, recents, or want-to-play suggestions

The core job — 'I just walked off the 18th, log this round' — starts with an empty list and a keyboard (screenshot 10 shows nothing until 'spyglass' is typed). The app already has location permission (map near-me) and knows the user's want-to-play list and recently viewed courses, but LogCoursePickerView is a bare SearchViewModel with an empty ContentUnavailableView. A busy golfer should see the course they are literally standing on as the first suggestion.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/LogCourseFlow.swift:148-173 (picker shows only search results; overlay 'Find the course you played' when empty); grep for 'recent|nearby' across 3Wood/ returns nothing; screenshot 10-Log-Picker_0_3252F4E7-5575-4723-9A20-E9851E5D0CC7.png (empty screen + keyboard).

**Recommendation:** Pre-populate the picker before any typing: 'Near you' section (reuse CourseRepo.inRegion around the user's location), followed by the want-to-play list ('Finally played one of these?') and recently viewed courses. This turns a ~10-interaction flow into 2 taps for the common case.

**Verifier:** Confirmed in code: LogCoursePickerView (LogCourseFlow.swift:148-173) is a bare List(viewModel.results) with a searchable field and an empty-state ContentUnavailableView ('Find the course you played') — no pre-populated content of any kind. Grep for recent/nearby/inRegion confirms CourseRepo.inRegion (CourseRepo.swift:11) exists but is used only by MapViewModel, so location-based suggestions are genuinely absent, and no recents mechanism exists at all. Screenshot 10-Log-Picker_0_3252F4E7...png shows the search-driven flow (note: it captures 'spyglass' already typed with one result, not the literal empty state, so the description slightly overstates what the PNG shows — but the code proves the empty state). Severity adjusted high → medium: the flow works, typing a course name is standard search behavior, and nothing is lost or blocked; pre-populating near-you/want-to-play is a clear convenience improvement to the core loop rather than something that breaks it.


### [MEDIUM] No global entry point for logging — the '+' lives only on the Lists tab, not on the launch tab

The app opens on Feed, which has no log button (its only toolbar action is the leaderboard trophy). To log a round from a cold open the user must know to switch to Lists and find the '+' in the corner, or search for the course first and use the detail button. For a Beli-style app whose core loop is 'played → log', the primary action is buried one tab and one corner away from where the user lands.

**Evidence:** /Users/leon-an/3Wood/3Wood/App/MainTabView.swift:5-20 (five tabs, no compose/plus tab); /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:33-46 (toolbar has only Wordmark + trophy); /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:32-40 (the only '+'); screenshot 18-Feed_0_A9309486-A162-4958-8899-C644932F7D83.png vs 01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png.

**Recommendation:** Add a '+' to the Feed toolbar (or a center '+' tab, the Beli pattern) presenting LogCourseFlow. The flow is already a self-contained fullScreenCover, so this is a one-line hookup per surface.

**Verifier:** Confirmed. MainTabView.swift:5-20 has five plain tabs with no compose tab; FeedView.swift:33-46 toolbar contains only the Wordmark (principal) and the trophy NavigationLink to LeaderboardView; ListsView.swift:32-40 holds the app's only '+' (fullScreenCover → LogCourseFlow). Screenshot 18-Feed_0_A9309486...png confirms the Feed toolbar has only wordmark + trophy. Severity adjusted high → medium: the log action is reachable in two taps from cold open (Lists tab, which is named 'My Courses' and is a fairly natural home, then '+'), plus CourseDetailView has its own 'Log this course' button, so the primary action is one learned tab-switch away rather than genuinely buried. Adding '+' to Feed is a cheap, worthwhile improvement (the finding is right that LogCourseFlow is a self-contained fullScreenCover), but this is discoverability friction, not a broken core loop.


### [MEDIUM] Feed and course detail dead-end on people — usernames are never tappable

Job 3 ('what are my friends up to') half-works: tapping a feed row reaches the course, but '@birdie_ben ranked' offers no path to birdie_ben's profile. Same on course detail: the 'Friends' scores' rows are plain Text. The only routes to a friend's profile are Find Friends search, the leaderboard, or Profile → Following — three or more taps and a context switch from the place where the friend's activity actually caught your eye.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:47-49 (navigationDestination only for FeedItem → CourseDetailByID) and 60-87 (FeedRow renders username as static text); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:81-88 (friend rows: Text + ScoreBadge, no link); screenshots 18-Feed_0_A9309486-A162-4958-8899-C644932F7D83.png and 04-CourseDetail_0_1F5E3373-75B2-432E-9787-3994DA8F628F.png ('Friends' scores' list of four names, no chevrons).

**Recommendation:** Make usernames tappable (push OtherProfileView) in FeedRow and the friends'-scores card, using the same explicit-tap pattern already proven in FindFriendsView/PeopleListView. FeedItem already carries the user id.

**Verifier:** Confirmed on all cited evidence. FeedView.swift:47-49 registers a navigationDestination only for FeedItem → CourseDetailByID, and FeedRow (lines 60-87) renders '@username ranked' as concatenated static Text inside the row's course NavigationLink — no per-user tap target. CourseDetailView.swift:81-88 renders friends' scores as plain Text('@username') + ScoreBadge with no link. Screenshot 04-CourseDetail_0_1F5E3373...png shows exactly the described 'Friends' scores' card with four usernames (@mulligan_mike, @sliceofjenny, @parfect_paula, @test_golfer1) and no chevrons; 18-Feed shows the same static-username feed rows. The recommendation is feasible as stated: FeedItem carries actorID (FeedItem.swift:6), FriendScore carries userID (ProfileSummary.swift:18), and OtherProfileView already exists and is pushed from FindFriendsView, PeopleListView, and LeaderboardView. Medium is the right severity: the social loop half-works with a multi-tap workaround, so it's a clear improvement rather than a core-promise failure.


### [MEDIUM] Want-to-play list items can only be removed via a 3-step detour through course detail

To clear a course off the want-to-play list you must open its detail, tap the bookmark toolbar icon, and navigate back — for every item. There are no swipe actions anywhere in the app. The empty-state copy even acknowledges the indirection: 'Bookmark courses you'd like to play from their detail page.' A swipe would also be the natural home for the app's single biggest missing shortcut: 'I finally played this one — log it', which currently requires detail → Log this course.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:97-113 (plain List of NavigationLinks, no onDelete); grep across 3Wood/ finds zero swipeActions/onDelete/contextMenu; screenshot 02-Lists-WantToPlay_0_6EE11139-D50A-4980-BED7-A1DB3A2D11E8.png; /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:119-128 (bookmark toggle is the only removal path).

**Recommendation:** Add swipeActions to want-to-play rows: destructive 'Remove' (WantToPlayRepo.remove) and a leading 'Log' action that opens LogCourseFlow(course:) — converting a bucket-list course into a ranked one in one gesture.

**Verifier:** Verified. /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:105-112 renders the want-to-play list as plain NavigationLinks with no onDelete, and a project-wide grep for swipeActions/onDelete/contextMenu returned zero matches. The only removal path is the bookmark toolbar toggle in CourseDetailView.swift:119-128 / toggleBookmark at 203-214, and the empty-state copy at ListsView.swift:102 explicitly instructs the detail-page detour. Screenshot 02-Lists-WantToPlay_0_6EE11139-D50A-4980-BED7-A1DB3A2D11E8.png shows rows with no removal affordance. Medium is right: it is a real per-item friction on a core list, but each removal is only a few taps and nothing is broken.


### [MEDIUM] Map 'near me' is not the default — the app opens on a continental-US view with a zoom hint

The map's initial camera is hardcoded to the center of the US at a 40-degree span, which triggers the 'Zoom in to explore courses' hint and renders zero pins — the first thing the near-me job shows the user is an instruction to do more work. Locating yourself requires finding the small MapUserLocationButton. List mode compounds it: rows carry no distance and are sorted by community average (unrated courses fall into arbitrary order, as the all-'Not rated' Arizona list shows), so 'what's closest' is unanswerable in list form.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:44-49 (hardcoded 39.8/-98.6, span 40), 94-97 (location only via MapUserLocationButton), 146 (list sorted by avgScore, no distance); screenshot 05-Map_0_08A56B1B-B2B1-4E2E-B3A8-E0D22A57EA43.png (whole-US view + 'Zoom in to explore courses'); 16-Map-ListView_0_0A9DEA36-2CA6-4232-B99F-9E9ABF0A7082.png (no distances, all 'Not rated').

**Recommendation:** On first appear, if location is authorized, start the camera at the user's location (fall back to the US view otherwise). In list mode, show distance per row and offer a distance sort when a location fix exists.

**Verifier:** Verified. CourseMapView.swift:44-49 hardcodes the initial camera to 39.8/-98.6 with a 40-degree span; screenshot 05-Map_0_08A56B1B-B2B1-4E2E-B3A8-E0D22A57EA43.png shows exactly that: whole-continent view, zero pins, and the 'Zoom in to explore courses' hint — the first screen of the near-me feature asks the user to do more work. There is no CLLocationManager anywhere in the app; location is reachable only through the small MapUserLocationButton (line 95). The list-mode half also holds: line 146 sorts by avgScore only, and screenshot 16-Map-ListView_0_0A9DEA36-2CA6-4232-B99F-9E9ABF0A7082.png shows Arizona rows with no distances and every score 'Not rated', so proximity is unanswerable in list form (the 'Not rated' values themselves are small-seed-data artifacts, but the absence of distance/sort is a code-level gap). Medium, not high: near-me is one standard-iOS tap away via the location button, so the core promise is reachable, just not defaulted.


### [MEDIUM] Silent failures: save review, follow, and bookmark can fail with zero user feedback

Several primary actions swallow errors: saving a review keeps the sheet open but shows nothing (the user taps Save and the button appears to do nothing), deleting a review fails silently, follow/unfollow reverts without explanation, and the bookmark toggle 'leaves the icon as-is'. On a flaky course-parking-lot connection these read as the app being broken, and for the review case the user cannot tell whether their text was saved.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/CourseDetail/WriteReviewSheet.swift:59-61 ('// Keep the sheet open so the text isn't lost.' — no message) and 69 (empty catch); /Users/leon-an/3Wood/3Wood/Features/Profile/FindFriendsView.swift:84-86 (FollowButton empty catch); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:211-213 (bookmark empty catch).

**Recommendation:** Show a lightweight inline error (alert or footer text) on review save/delete failure at minimum — that is the one flow where user-authored content is at stake. Follow/bookmark can stay optimistic but should flash a brief toast on failure.

**Verifier:** Verified all three citations. WriteReviewSheet.swift:59-61 catches the save error with only the comment 'Keep the sheet open so the text isn't lost.' and shows nothing (Save re-enables via the defer at line 53, so the tap appears to do nothing); line 69 is a literal empty catch for delete. FindFriendsView.swift:84-86 (FollowButton) and CourseDetailView.swift:211-213 (bookmark) are also comment-only empty catches. The description slightly overstates follow behavior — state never flips optimistically, it just stays unchanged rather than 'reverting' — but the user-facing effect (button tap silently does nothing on failure) is the same. Medium is correct: the review text is not actually lost (sheet stays open), so this is confusing rather than destructive, which keeps it below high.


### [MEDIUM] No review prompt at the end of the log flow — writing a review requires re-finding the course

The moment of highest motivation to write a review is right after ranking a course, but RankResultView offers only 'Done', which dismisses the whole flow. To add a review the user must then navigate Search → course → 'Write a review'. Beli-style apps capture the note in the same session.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/RankResultView.swift:24-33 (single Done button); screenshot 13-Log-Result_0_32145F14-D4A6-4A15-868E-F370214C61F3.png (score badge + Done, nothing else); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:149-152 (review entry only lives on detail).

**Recommendation:** Add a secondary 'Add a note' button on RankResultView that presents WriteReviewSheet(courseID:) before dismissing — the sheet is already reusable and takes a course ID.

**Verifier:** Verified. RankResultView.swift:26-31 offers a single 'Done' button and nothing else; screenshot 13-Log-Result_0_32145F14-D4A6-4A15-868E-F370214C61F3.png confirms: 'All set!', the 9.8 badge, rank line, and Done. The only review entry point is the 'Write a review' button on CourseDetailView.swift:149-152, so adding a note after logging requires re-navigating to the course. The recommendation is cheap because WriteReviewSheet takes just a courseID and an onSaved closure (WriteReviewSheet.swift:3-6). Medium holds for a social-review app where post-round notes are core content and the moment of peak motivation is being discarded; it is an engagement gap, not a breakage, so not high.


### [LOW] Comparison step hides how much work remains

ComparisonView receives comparisonsRemaining but only uses it for a binary 'Last one' vs the vague 'A few more to place this course'. With up to log2(n) comparisons, a golfer with a big list has no sense of progress, which makes the flow feel open-ended and increases mid-flow cancels (which discard all answers).

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:43-45 (remaining count collapsed to two strings); screenshot 12-Log-Comparison_0_B15DB4D4-5F04-4A7B-9008-3B33D3C9DA3E.png (footer 'A few more to place this course').

**Recommendation:** Show the actual bound ('At most 3 more') or a small dot progress indicator; the value is already plumbed through.

**Verifier:** Verified. ComparisonView.swift:43 collapses comparisonsRemaining to exactly two strings ('Last one' vs 'A few more to place this course'), and screenshot 12-Log-Comparison shows the vague footer. The secondary claims also hold: LogCourseFlow.swift:128 passes engine.maxComparisonsRemaining (a real upper bound, so 'At most N more' is trivially available), and the Cancel button (LogCourseFlow.swift:60-62) just calls dismiss(), discarding the in-progress engine state. Severity low is correct — bucket lists cap comparisons at ~log2(n), so even large lists mean few steps, but the fix is nearly free.


### [LOW] City jump fails silently and offers no suggestions

The map's 'Jump to a city' field only acts on keyboard submit and, if MKLocalSearch returns nothing (typo, ambiguous query), the guard returns with no feedback — the map just doesn't move. There is no autocomplete, so the user cannot tell a typo from a dead feature.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:204-219 (jumpToPlace: 'guard ... else { return }' — silent on geocode failure, submit-only via onSubmit at line 67); screenshot 23-Map-CityJump_0_5D6C680F-934E-4B8E-8023-B79D1AF34804.png.

**Recommendation:** Use MKLocalSearchCompleter to show live city suggestions under the field, and show a brief 'Couldn't find that place' hint when geocoding fails.

**Verifier:** Verified in code. CourseMapView.swift:67 triggers jumpToPlace only via onSubmit(of: .search); lines 205-211 have two silent guards — empty query and 'try? await MKLocalSearch...start()' with 'else { return }' — so a typo or geocode failure produces zero feedback and the map simply doesn't move. Screenshot 23-Map-CityJump only shows the success case (Scottsdale), so the screenshot neither proves nor refutes the failure path, but the code is unambiguous. Low severity is right: the state menu and map panning are alternate paths, and retrying is cheap; this is polish (feedback + MKLocalSearchCompleter), not a core-promise break.


### [LOW] Played list has no filter or search once it grows

The Played list is a single global ranking with no way to filter by bucket, state, or search within it, and the leading number is the global index even though rank position is computed per bucket ('#1 of your Liked-it courses' on detail vs a different number in the list). Fine at demo scale; friction at 50+ courses, which is exactly the power user this app targets.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:71-93 (no searchable, no bucket segmenting; index from enumerated()); screenshots 01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png and 14-PlayedRow-Detail_0_58C67550-4BA6-4650-A405-755A534ECC44.png ('#1 of your "Liked it" courses' while the list shows its own numbering).

**Recommendation:** Add .searchable and a bucket filter (Liked/Fine/Didn't like chips) to the Played list; consider showing the per-bucket rank to match the detail view's framing.

**Verifier:** Verified. ListsView.swift:71-93 has no .searchable modifier, no bucket segmenting, and numbers rows via Array(ranked.enumerated()) — a global index across all buckets. Screenshot 14-PlayedRow-Detail shows the detail framing '#1 of your "Liked it" courses' while screenshot 01-Lists-Played shows the enumerated list. One overstatement: in the actual screenshots the two numbers coincide (Spyglass is #1 both globally and in-bucket), so the cited mismatch is inferred from the code rather than visible; it would only diverge for courses past the first bucket. Core claim (no search/filter at scale) is real but explicitly a future-scale problem — low is the correct severity.


### [LOW] Search tab empty state is inert — no nearby or trending courses to browse

The 'where should I play next' job via Search starts at a placeholder ('Search any of 16,000+ US golf courses') that offers nothing to tap. Discovery is pushed entirely to the Map tab; a couple of zero-effort rows (near you, top-rated in your state) would let Search serve browsing as well as lookup.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Search/SearchView.swift:12-19 (empty ContentUnavailableView until 2 typed characters); screenshot 03-Search-Results_0_EEF72A1C-C1B4-4FD4-848B-AA8EE2FC9309.png.

**Recommendation:** Seed the pre-query state with 'Near you' and 'Top rated in <state>' sections reusing CourseRepo.inRegion / existing avg-score data.

**Verifier:** Verified in code. SearchView.swift:14-19 renders a plain ContentUnavailableView ('Find a course' / 'Search any of 16,000+ US golf courses by name or city') with nothing tappable until 2 characters are typed. Minor evidence flaw: the cited screenshot 03-Search-Results shows a populated results list for 'pebble beach', not the empty state, so the screenshot doesn't illustrate the finding — the code does. The claim itself stands: discovery is entirely deferred to the Map tab. Low is right; Search-as-lookup works well (labelled avg badges, type tags), and seeding the empty state is an enhancement, not a defect. Note the minimalist empty state is also arguably consistent with the owner's flat/minimalist taste, which further caps this at low.


## Visual Clarity

**Strengths (keep these):**

- ScoreBadge is a genuinely strong at-a-glance device: bold rounded monospaced digits on green/gold/red capsules, readable at tiny sizes, and its color semantics are applied consistently across Played list, course detail, friends' scores, feed, and the result screen in both light and dark mode. Do not change the core badge design.
- Played-list row anatomy (rank numeral, headline name, secondary location, trailing badge) has excellent scan rhythm — the eye runs straight down the badge column to compare scores. Same anatomy reused in Search and Map list keeps the app coherent.
- Dark mode is a real first-class variant, not an afterthought: the lightened green/gold variants keep badge contrast on near-black, cards retain their grouping, and the gold leaderboard ranks read well (dark-01, dark-02, dark-04, dark-19).
- Course detail hierarchy of the three stacked cards (Your score, Community rating, Friends' scores) with badges right-aligned is clear, and the full-width fairway-green 'Update my ranking' CTA is unmistakably the primary action.
- The bucket picker's three full-width color-coded buttons (11-Log-Picker) are a model of decisive, flat, minimal UI — one glance, one tap (only the hues need palette alignment).
- The comparison screen keeps exactly two cards plus a 'vs' and nothing else — appropriate focus for the app's core interaction; the NEW tag on the just-logged course is a nice orienting touch.
- Course-type tags (Resort/Private/Semi-Private) as quiet caption capsules add useful density without stealing attention from names.
- Leaderboard highlights the current user's row with a tinted background and bolder text — findable instantly in a long list.
- The Righteous wordmark with golf-ball O's on the Welcome screen and Feed header lands the vintage/flat brand personality well.


### [HIGH] City-zoom map is buried under dozens of identical gray 'no-score' badge blobs

At city zoom, every course gets a compact ScoreBadge annotation; unrated courses render as a solid gray capsule containing only a dash. In the Scottsdale screenshot, roughly 40 gray blobs cover street names, course labels, and each other, while the single rated course (green 8.4) is the only marker carrying information. The map — a core tab — becomes visual noise the eye must fight through, and the gray capsules are indistinguishable from one another, so tapping is guesswork. The code even acknowledges the failure mode at continental zoom ('hundreds of overlapping badges read as dark blobs') but the same problem persists at city zoom.

**Evidence:** /tmp/3wood-review/shots-light/23-Map-CityJump_0_5D6C680F-934E-4B8E-8023-B79D1AF34804.png (entire Scottsdale viewport: ~40 gray dash-capsules vs one green 8.4); /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:84-92 renders ScoreBadge(score: course.avgScore, compact: true) for every course, and ScoreBadge.swift:21 returns .gray with a '–' glyph when score is nil.

**Recommendation:** Render unrated courses as a small flat dot or pin (palette sand/dark-pine outline) and reserve the capsule badge for rated courses only; alternatively cluster markers or cap annotation count per viewport. The rated-course badges then pop instantly.

**Verifier:** Confirmed. 23-Map-CityJump_0_5D6C680F...png shows the Scottsdale viewport covered by roughly 40 identical solid-gray dash capsules that sit on top of street names and course labels; the lone rated course (green 8.4) is the only informative marker. Code matches: CourseMapView.swift:84-92 renders ScoreBadge(score: course.avgScore, compact: true) for every course in the viewport, and ScoreBadge.swift:21 returns .gray with a dash when score is nil; the comment at lines 82-83 acknowledges the blob failure mode but only suppresses it at continental zoom. This is not a seed-data quirk — unrated courses will be the majority in production too, so the Map tab (core to the near-me/city-jump promise) genuinely reads as noise. High severity stands.


### [MEDIUM] Bucket picker uses system orange/red instead of the app's SunriseGold/ClayRed

The 'It was fine' and 'Didn't like it' buttons are tinted with SwiftUI's default .orange and .red — bright, saturated system hues that clash with the muted 'Refined Classic' palette. Worse for consistency: the very same semantic tiers (mid score, low score) are rendered as SunriseGold #D9A441 and ClayRed #B3402F everywhere else via ScoreBadge, so the mid/low colors a user learns on this screen do not match the badge colors they see on every list afterward.

**Evidence:** /tmp/3wood-review/shots-light/11-Log-BucketPicker_0_9C171F22-7042-4E62-A207-D3D9D785844D.png (compare the neon orange/red buttons to the gold 3.7/4.2 badges in 02-Lists-WantToPlay); /Users/leon-an/3Wood/3Wood/Features/Ranking/BucketPickerView.swift:36-37 — `case .fine: .orange` / `case .disliked: .red`.

**Recommendation:** Change the tints to .sunriseGold and .clayRed so the bucket colors match the score-badge tiers and the vintage palette.

**Verifier:** Confirmed. BucketPickerView.swift:36-37 literally reads `case .fine: .orange` / `case .disliked: .red` while `.liked` gets the palette's .fairwayGreen — so two of three buttons bypass the design system. The screenshot 11-Log-BucketPicker_0_9C171F22...png shows saturated neon system orange/red directly under the muted dark-green button, and comparing to the gold 3.7/4.2 badges in 02-Lists-WantToPlay confirms the mid-tier color a user learns here does not match the SunriseGold badge tier seen everywhere else. Clashes with the stated vintage/flat 'Refined Classic' palette and breaks color-semantics consistency. Medium is right — a clear, trivial-to-fix improvement, not user-harming.


### [MEDIUM] Comparison-flow progress text is nearly invisible (.tertiary footnote)

On the pairwise comparison screen, 'A few more to place this course' / 'Last one' is the only signal of how much work remains in a repetitive flow, yet it is set in tertiary-gray footnote at the very bottom of the screen — in the light screenshot it is barely distinguishable from the background. Users who cannot see flow progress are more likely to abandon ranking, which is the app's core mechanic.

**Evidence:** /tmp/3wood-review/shots-light/12-Log-Comparison_0_B15DB4D4-5F04-4A7B-9008-3B33D3C9DA3E.png (bottom edge, below 'Too close to call'); /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:43-45 — footnote + .foregroundStyle(.tertiary).

**Recommendation:** Raise to .secondary at least, and consider an explicit count ('2 comparisons left') or a small progress dots row near the question title where the eye already is.

**Verifier:** Confirmed with one nitpick: the code (ComparisonView.swift:43-45) uses .font(.caption), not .footnote — actually smaller than claimed — with .foregroundStyle(.tertiary). In 12-Log-Comparison_0_B15DB4D4...png, 'A few more to place this course' at the bottom edge is a very pale gray, close to illegible on the light background, and it is the only progress signal in the pairwise flow. The abandonment argument for the app's core ranking mechanic is plausible but the flow is short (few comparisons), so medium — not high — is the correct severity. Medium stands.


### [MEDIUM] 'avg' and 'Not rated' labels are below comfortable legibility (.caption2 + .tertiary)

The 'avg' caption under community-score badges is the only thing distinguishing a community average from a personal score — a crucial distinction in this app — yet it is caption2 tertiary gray, effectively invisible at arm's length (see the Want-to-Play tab, where every badge is an average). 'Not rated' in Search and Map list rows has the same problem: it is the row's entire right-column content and it almost vanishes, especially in light mode.

**Evidence:** /tmp/3wood-review/shots-light/02-Lists-WantToPlay_0_6EE11139-D50A-4980-BED7-A1DB3A2D11E8.png (tiny 'avg' under each badge), /tmp/3wood-review/shots-light/03-Search-Results_0_EEF72A1C-C1B4-4FD4-848B-AA8EE2FC9309.png ('Not rated' right column); /Users/leon-an/3Wood/3Wood/Features/Search/SearchView.swift:66-73 — .font(.caption2).foregroundStyle(.tertiary) for both.

**Recommendation:** Bump both to .secondary; for 'avg' consider putting it inside the capsule ('8.8 avg') or using an outlined badge variant for community averages so the distinction reads at badge level, not via a 9pt caption.

**Verifier:** Confirmed. SearchView.swift:66-73 sets both the 'avg' caption and the 'Not rated' text to .font(.caption2) + .foregroundStyle(.tertiary). In 02-Lists-WantToPlay_0_6EE11139...png the 'avg' under each gold/green badge is tiny and faint; in 03-Search-Results_0_EEF72A1C...png the 'Not rated' right column nearly vanishes against white. The code's own comment at line 62 ('labelled so it isn't mistaken for a personal score') proves the label is load-bearing — the community-vs-personal distinction is a core concept in a Beli-style app — so its near-invisibility undermines its purpose. Medium is correct.


### [MEDIUM] Profile stats bar: stray chevrons and uneven gaps break the three-stat rhythm

On Profile, the row reads '16 Played   3 Followers  >        4 Following  >'. The NavigationLinks pick up list disclosure chevrons and stretch, so a chevron floats in dead space between Followers and Following (it visually belongs to neither), the gap before Following is far larger than the gap between Played and Followers, and Played (non-tappable) looks identical to the tappable stats. The code intends a simple HStack(spacing: 28) of three equal stat items; the rendered layout contradicts it.

**Evidence:** /tmp/3wood-review/shots-light/06-Profile_0_C2DBDEC1-3E1E-48F0-A257-912948FF5605.png and /tmp/3wood-review/small/dark-06-Profile_0_58AE60B2-E529-4E30-B61B-DCD956D65946.png (stats row inside the profile card); /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift:10-24 (ProfileStatsBar with NavigationLink + .buttonStyle(.plain)).

**Recommendation:** Suppress the disclosure indicators (e.g., use Button + programmatic navigation, or NavigationLink with an EmptyView-hidden overlay pattern) so the three stats sit evenly spaced; if tap affordance is needed, tint the tappable numbers fairwayGreen instead.

**Verifier:** Confirmed in 06-Profile_0_C2DBDEC1-3E1E-48F0-A257-912948FF5605.png: a disclosure chevron floats in empty space between '3 Followers' and '4 Following' (belonging visually to neither), a second chevron sits at the card's trailing edge, and the gap before 'Following' is several times wider than the Played-Followers gap. Code at /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift:10-24 matches the citation exactly: HStack(spacing: 28) with two NavigationLinks + .buttonStyle(.plain), which inside a List row acquire system disclosure indicators and stretch — the rendered layout contradicts the intended even spacing. Not seed-data related; it reads as a layout bug on a screen every user sees. Medium is correct.


### [MEDIUM] Played list truncates long course names while sibling lists wrap them

In the ranked Played list, 'Black At Bethpage State Pa...' and 'Cougar Point At Kiawah Isla...' truncate at one line — cutting off exactly the words that distinguish similar courses — while the Search results and Map list wrap the same style of name onto two lines ('Anthem Golf Country Club Ironwood Course'). Equivalent rows behave differently across screens, and the Played list (the app's centerpiece) is the one that loses information.

**Evidence:** /tmp/3wood-review/shots-light/01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png rows 5 and 7 (truncated) vs /tmp/3wood-review/shots-light/16-Map-ListView_0_0A9DEA36-2CA6-4232-B99F-9E9ABF0A7082.png (two-line names); /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:80 uses .lineLimit(1) while /Users/leon-an/3Wood/3Wood/Features/Search/SearchView.swift:46 uses .lineLimit(2).

**Recommendation:** Use .lineLimit(2) in ListsView rows to match Search/Map list behavior.

**Verifier:** Confirmed. 01-Lists-Played_0_07C245AF...png rows 5 and 7 show 'Black At Bethpage State Pa...' and 'Cougar Point At Kiawah Isla...' truncated to one line, while 16-Map-ListView_0_0A9DEA36...png wraps 'Anthem Golf Country Club Ironwood Course' onto two lines. Code confirms the inconsistency: /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:80 uses .lineLimit(1) vs /Users/leon-an/3Wood/3Wood/Features/Search/SearchView.swift:46 .lineLimit(2). One quibble: the description overstates that truncation cuts 'exactly the words that distinguish' the courses — in both visible cases the distinguishing words (Black, Cougar Point) lead the name and only 'Park'/'Island' are cut. Still, the cross-screen inconsistency in the app's centerpiece ranked list is real and the fix is trivial. Medium (clear improvement) stands.


### [MEDIUM] Map's 'flag' toolbar icon does not communicate 'jump to state'

The top-leading toolbar item on the Map tab is a bare flag glyph that opens a state-jump menu. On a golf app map, a flag most plausibly reads as 'flagstick/pin', 'favorites', or 'report' — jumping to a US state is about the last guess. It is also the lone icon on the leading side, separated from the two trailing icons (filter, list toggle), which are conventional. Users will either never discover state jump or tap it by accident.

**Evidence:** /tmp/3wood-review/shots-light/05-Map_0_08A56B1B-B2B1-4E2E-B3A8-E0D22A57EA43.png and 22-Map-Controls (top-left flag icon); /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:69 + :183 — Label("State", systemImage: "flag") in a topBarLeading menu.

**Recommendation:** Show the text label ('State' or 'CA') in the toolbar button, or fold state jump into the existing 'Jump to a city' search as suggestions; if an icon must stay, 'map' or 'globe.americas' communicates geography better than 'flag'.

**Verifier:** Confirmed in 05-Map_0_08A56B1B...png and 22-Map-Controls_0_00C3AC51...png: a bare flag glyph is the lone top-leading toolbar item, with the two conventional icons (filter, list toggle) grouped trailing. Code matches: CourseMapView.swift:69 (ToolbarItem(placement: .topBarLeading) { stateMenu }) and :183 (Label("State", systemImage: "flag")). The ambiguity argument holds with extra force in a golf app, where 'flag' already means flagstick — the same screen's course rows even use the flag icon for hole counts (CourseDetailView.swift:26). Mitigating factor: the prominent 'Jump to a city' search covers the same geography-jump job, so the harm is undiscoverability of a secondary path rather than a broken flow. Medium is the right level for this clarity fix; not high.


### [LOW] Course detail shows the course name twice at the top

The inline navigation bar title ('Pebble Beach Golf Links') sits directly above an in-content title2 heading with the identical string, so the most prominent zone of the screen spends two lines saying the same thing. On the Reviews scroll position the nav title persists while the user reads reviews — fine — but at rest the duplication flattens hierarchy and wastes the screen's prime real estate.

**Evidence:** /tmp/3wood-review/shots-light/04-CourseDetail_0_1F5E3373-75B2-432E-9787-3994DA8F628F.png and /tmp/3wood-review/shots-light/14-PlayedRow-Detail_0_58C67550-4BA6-4650-A405-755A534ECC44.png (nav bar title + repeated heading immediately below); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:21 (.font(.title2.bold()) heading) and :117 (.navigationTitle(course.name)).

**Recommendation:** Keep the in-content heading and leave the nav bar title empty at rest, revealing it only on scroll (toolbar title visibility tied to scroll offset), the standard detail-page pattern.

**Verifier:** Confirmed in both 04-CourseDetail_0_1F5E3373...png and 14-PlayedRow-Detail_0_58C67550...png: inline nav bar reads 'Pebble Beach Golf Links'/'Spyglass Hill Golf Course' with the identical string in bold title2 immediately below. Code matches: CourseDetailView.swift:20-21 (Text(course.name).font(.title2.bold())) and :117 (.navigationTitle(course.name)). However, severity is overstated: an always-visible inline nav title is a standard, unobjectionable iOS pattern, the redundancy costs one short line, and it does not confuse or mislead anyone. Hiding the nav title until scroll is polish that suits the owner's minimalist taste, not a clear usability gain. Downgrade to low.


### [LOW] Search-field placement flips between the two search flows

The Log-a-course picker anchors its search field at the bottom of the screen (above the keyboard) with results filling from the top, while Find Friends puts the search field at the top with results below. Two structurally identical modal search tasks, two opposite layouts — each time, the eye has to re-find the input and re-learn the scan direction.

**Evidence:** /tmp/3wood-review/shots-light/10-Log-Picker_0_3252F4E7-5575-4723-9A20-E9851E5D0CC7.png (field at bottom, result at top, huge empty middle) vs /tmp/3wood-review/shots-light/07-FindFriends_0_7C80C14E-2E28-46FD-9942-8D72CF65B439.png (field at top).

**Recommendation:** Pick one placement for both. Bottom-anchored is a defensible thumb-reach choice, but then Find Friends should match; results should stack adjacent to the field either way.

**Verifier:** Verified in /tmp/3wood-review/shots-light/10-Log-Picker_0_3252F4E7-5575-4723-9A20-E9851E5D0CC7.png: search field is bottom-anchored just above the keyboard while the single result ('Spyglass Hill Golf Course') sits at the very top, with a large empty middle between them. /tmp/3wood-review/shots-light/07-FindFriends_0_7C80C14E-2E28-46FD-9942-8D72CF65B439.png shows the opposite: field at top, results directly below. Both are structurally identical modal search tasks (field + X dismiss + result list), so the inconsistency claim holds. Within the Log-Picker itself the field-to-result distance is also genuinely awkward. Low severity is right — it costs a moment of re-orientation, nothing more.


### [LOW] Leaderboard tie ranks show three gold '1's with no tie cue

The top three rows all display rank '1' in SunriseGold with identical '17 courses' counts, then jump to '4'. Standard competition ranking is defensible, but three identical gold numerals stacked in the leftmost scan column momentarily read as a rendering bug rather than a three-way tie, and gold is applied to the numeral '1' rather than to top-3 positions, so it doubles down on the repetition.

**Evidence:** /tmp/3wood-review/shots-light/19-Leaderboard_0_FAE3B8C4-41AC-4E06-94C2-817CC3B9B609.png and /tmp/3wood-review/shots-dark/dark-19-Leaderboard_0_FC03A592-48E0-4982-AF73-18937425A1AC.png (rows 1-3: gold 1/1/1, then 4).

**Recommendation:** Add a tie marker ('T1') or use a single medal glyph for the tied group; alternatively add a secondary sort (e.g., avg score) so exact ties are rare with real data.

**Verifier:** Verified in both cited screenshots: rows 1-3 show gold '1' numerals with identical '17 courses', then rank jumps to 4 (and later 6/6 then 8). Code confirms the mechanism exactly as claimed: LeaderboardView.swift:59-66 colors by rank VALUE (case 1: gold, 2: silver, 3: bronze), so a tied top group renders three golds and silver/bronze never appear. This is app behavior, not just the known seed-data non-issue — integer course counts will produce ties with real data too, though the specific 3-way tie shown is demo data. Not visually broken and standard competition ranking is defensible, so low is the correct severity.


### [LOW] Log-result screen: 'All set!' is stranded at the top, far from its content

On the ranking-complete screen, the headline 'All set!' sits alone at the very top while the course name, big score badge, and '#1 of your Liked it courses' cluster at screen center, with a large dead zone between. The celebratory message and the thing being celebrated are ~700pt apart, so the moment reads as two unrelated fragments; the strongest element (the 9.8 badge — which is excellent) has no title anchoring it.

**Evidence:** /tmp/3wood-review/shots-light/13-Log-Result_0_32145F14-D4A6-4A15-868E-F370214C61F3.png ('All set!' at top edge; course + badge + caption at vertical center; Done at bottom).

**Recommendation:** Move 'All set!' into the centered stack above the course name (and let it be the largest text on screen); keep Done pinned at the bottom.

**Verifier:** Verified in /tmp/3wood-review/shots-light/13-Log-Result_0_32145F14-D4A6-4A15-868E-F370214C61F3.png: 'All set!' sits alone at the top edge in a relatively small headline weight, the course name + large green 9.8 badge + '#1 of your "Liked it" courses' caption cluster at vertical center, and Done is pinned at the bottom — with a very large dead zone between headline and content, exactly as described. The centered badge cluster itself is strong and on-brand (flat, 2-D, minimalist), so this is purely a grouping/hierarchy polish issue. Low severity is correct.


### [LOW] Want-to-Play averages wear the same solid badge as personal scores in the adjacent tab

Flipping between the Played and Want-to-Play segments, the right column looks identical: solid green/gold capsules with one-decimal numbers. But Played badges are the user's own rankings and Want-to-Play badges are community averages — a semantic switch signaled only by the near-invisible 'avg' caption (see separate finding). Equivalent-looking elements carrying different meanings across sibling screens forces a double-take, especially when a gold 3.7 avg sits where a personal score would.

**Evidence:** /tmp/3wood-review/shots-light/01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png vs /tmp/3wood-review/shots-light/02-Lists-WantToPlay_0_6EE11139-D50A-4980-BED7-A1DB3A2D11E8.png (identical badge treatment, different meaning); ScoreBadge.swift has no variant for community vs personal.

**Recommendation:** Add a visually distinct ScoreBadge variant for community averages (outlined capsule or muted fill) used consistently in Want-to-Play, Search, Map, and the 'Community rating' card, reserving the solid fill for the user's own scores.

**Verifier:** Verified across both screenshots and code. 01-Lists-Played shows solid green capsules (personal rankings, with rank numbers); 02-Lists-WantToPlay shows the identical solid-capsule treatment for community averages (gold 3.7/4.2/4.7/6.5 and notably a green 8.1 that is indistinguishable from a personal score), differentiated only by a tiny gray 'avg' caption. ScoreBadge.swift (lines 5-27) confirms no personal-vs-community variant exists — only score and compact — and grep shows the same component renders avgScore in SearchView.swift:65, CourseMapView.swift:88, and CourseDetailView.swift:71. Mitigating factors keep this at low rather than medium: the 'avg' caption does exist in list contexts, and the Want to Play / Search / Map contexts involve courses the user has not played, so genuine misattribution of a community average as one's own score is unlikely; it is a double-take, not a misread. The recommended outlined-vs-solid distinction also fits the flat/minimalist taste.


## Aesthetics vs. Vintage/Flat/Minimalist Taste

**Strengths (keep these):**

- The wordmark is genuinely excellent and should not be touched: Righteous logotype with both o's replaced by custom-drawn knockout golf balls (GolfBallShape, even-odd dimple lattice) is flat, 2-D, vintage, and ownable — the strongest brand asset in the app (/Users/leon-an/3Wood/3Wood/Core/DesignSystem/Wordmark.swift; visible in 00-Welcome.png and the Feed nav bar).
- Carrying the wordmark into the Feed navigation bar at size 24 (FeedView.swift:35) is the right instinct — brand presence inside the app, not just on the splash screen.
- The ScoreBadge system is on-brand and legible: palette-mapped green/gold/red pills with monospaced digits, consistent across Lists, Search, CourseDetail, Feed, and the map callout — the one place the full semantic palette is actually wired up correctly (ScoreBadge.swift:20-27).
- Genuine 2-D flatness discipline in code: essentially no shadows, no gradients, no skeuomorphism anywhere — a single .thinMaterial capsule on the map (CourseMapView.swift:108) is the only material in the entire app. The foundation for the flat aesthetic is already clean; it's the warmth and custom character that are missing, not flatness.
- Minimalist restraint in layout: screens are uncluttered with clear hierarchy (CourseDetail's score-stack, the comparison flow's single-question-per-screen pacing). The bones are right — this is a re-skinning problem, not a redesign problem.
- The leaderboard's current-user row highlight (FairwayGreen at 12% opacity, LeaderboardView.swift:36) is a subtle, flat, on-palette touch worth keeping.
- Dark mode palette variants are thoughtfully warm (Cream dark #20221D, Sand dark #35382F are warm near-blacks, not pure gray), so the recommended Cream/Sand surface work will translate to dark mode with no extra design effort.


### [HIGH] Cream/Sand warm surfaces are defined but never used — every screen is white/gray default iOS

The palette's whole 'vintage paper' premise (Cream #F7F3E8 surfaces, Sand #E3D9C2 borders/separators) exists only as a comment block. A grep for .cream/.sand/.darkPine across 3Wood/Features returns zero hits; the only palette tokens used in features are fairwayGreen and ad-hoc colors. Card surfaces all use `.quaternary.opacity(0.5)` cool gray, list screens sit on plain white, Profile sits on systemGroupedBackground gray. The result is 'default iOS with a green accent' — exactly what the owner doesn't want. This is the single highest-leverage fix: make Cream the app-wide scroll background, use Sand for hairline rules and card strokes, and DarkPine for headings. Dark mode already has warm variants (#20221D/#35382F) so parity comes free.

**Evidence:** Code: /Users/leon-an/3Wood/3Wood/Core/DesignSystem/Colors.swift:9-10 (tokens documented, never referenced in Features — verified by grep); /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:74,90,182 and /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:72 all use `.background(.quaternary.opacity(0.5), ...)`. Screenshots: 01-Lists-Played_0_07C245AF...png (pure white list), 04-CourseDetail_0_1F5E3373...png (gray score cards on white), 06-Profile_0_C2DBDEC1...png (gray grouped background).

**Recommendation:** Set Color.cream as the background of every root scroll view (`.background(Color.cream)` + `.scrollContentBackground(.hidden)` on Lists), replace `.quaternary.opacity(0.5)` card fills with Color.cream plus a 1px Color.sand stroke, and use Color.sand for list separators/hairlines. Stays 100% flat — it's just a fill swap — and instantly reads 'considered vintage brand'.

**Verifier:** Fully confirmed. I ran the grep myself: zero references to .cream, .sand, or .darkPine anywhere in 3Wood/**/*.swift outside the Colors.swift doc comment (/Users/leon-an/3Wood/3Wood/Core/DesignSystem/Colors.swift:9-11 documents them as surface/border/heading tokens). Card fills are .quaternary.opacity(...) cool gray at CourseDetailView.swift:74,90,182, ComparisonView.swift:72, WriteReviewSheet.swift:18, and SearchView.swift:57. Screenshots confirm the visual result: 01-Lists-Played_0_07C245AF...png is a pure-white list, 04-CourseDetail_0_1F5E3373...png shows cool-gray score cards on white, 06-Profile_0_C2DBDEC1...png sits on gray systemGroupedBackground. The only brand color in play is fairwayGreen, so the app reads as 'default iOS with a green accent' — the opposite of the stated Refined Classic / vintage premise. Not seed-data related; not contradicted by minimalist taste (warm flat fills are still flat). High severity stands: it is systemic, app-wide, and the root cause of the generic look.


### [HIGH] Bucket picker uses candy-bright system .orange and .red instead of SunriseGold and ClayRed

The 'How was it?' step — a core ranking moment shown on every log — renders 'It was fine' in system orange (#FF9500-ish) and 'Didn't like it' in system red. These saturated iOS defaults are the loudest palette violation in the app; the intended SunriseGold #D9A441 and ClayRed #B3402F are muted, vintage tones that already exist as tokens with dark variants. The same three-tier semantic (green/gold/red) is done correctly in ScoreBadge, so this screen contradicts the app's own score-color language.

**Evidence:** Screenshot: 11-Log-BucketPicker_0_9C171F22...png (bright orange and red capsule buttons). Code: /Users/leon-an/3Wood/3Wood/Features/Ranking/BucketPickerView.swift:36-37 — `case .fine: .orange` / `case .disliked: .red`; compare /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift:23-25 which correctly uses .sunriseGold/.clayRed.

**Recommendation:** One-line fix: `case .fine: .sunriseGold` and `case .disliked: .clayRed`. Consider dropping the SF thumbs-up/thumbs-down/minus glyphs too (or replacing with plain text) — the flat colored bars carry the meaning on their own.

**Verifier:** Fully confirmed. 11-Log-BucketPicker_0_9C171F22...png shows heavily saturated system-orange ('It was fine') and system-red ('Didn't like it') capsules that visibly clash with the muted fairway-green 'Liked it' bar above them. Code matches exactly: BucketPickerView.swift:36-37 uses `case .fine: .orange` / `case .disliked: .red`, while ScoreBadge.swift:23-25 implements the identical green/gold/red semantic correctly with .fairwayGreen/.sunriseGold/.clayRed. So this is both a palette violation against the stated vintage taste AND an internal inconsistency with the app's own established score-color language, sitting in the mandatory core-ranking flow users hit on every single course log. High severity is justified: it is the loudest, most repeated aesthetic break in the core loop, and the fix is genuinely one line.


### [MEDIUM] Welcome screen pairs the custom wordmark with a stock SF-symbol golfer and an off-system CTA style

The first screen a user ever sees leads with `Image(systemName: "figure.golf")` at 72pt — the most recognizable stock Apple glyph in the sports set — directly above the genuinely distinctive Righteous wordmark with knockout golf-ball o's. The stock figure actively undercuts the brand mark below it. The CTA also uses `.borderedProminent` (system capsule) instead of the app's own PrimaryButtonStyle (14pt rounded rect), so the brand's one custom button style isn't even on the brand's front door. The screen is also stark white with a sea of empty space — no Cream, no compositional idea.

**Evidence:** Screenshot: 00-Welcome.png (SF golfer above wordmark; capsule 'Create account' button). Code: /Users/leon-an/3Wood/3Wood/Features/Auth/WelcomeView.swift:9-11 (figure.golf), :23-24 (.borderedProminent instead of .buttonStyle(.primary)).

**Recommendation:** Delete the SF golfer. Either let the wordmark stand alone (scaled up on a Cream field, tagline in DarkPine) or draw one flat 2-D companion mark in the same language as GolfBallShape — e.g. a single oversized dimpled ball, or a minimal tee/flag pictogram. Switch the CTA to .buttonStyle(.primary) so the brand button appears where it matters most.

**Verifier:** Confirmed but severity overstated. 00-Welcome.png shows exactly what is claimed: a large stock SF figure.golf glyph directly above the distinctive Righteous wordmark with dimpled golf-ball o's, and a system capsule 'Create account' button. Code matches: WelcomeView.swift:9-11 (figure.golf at 72pt), :23 (.borderedProminent). The app's own PrimaryButtonStyle (fairway-green 14pt rounded rect, /Users/leon-an/3Wood/3Wood/Core/DesignSystem/PrimaryButtonStyle.swift) exists and is used at RankResultView.swift:31 and CourseDetailView.swift:99, so the CTA inconsistency claim is accurate. However, this is a single screen seen only while signed out, the fix is trivial, and the 'sea of empty space' sub-claim is contestable under the owner's minimalist taste — generous whitespace is not itself a defect. The real offenses are the stock glyph undercutting the wordmark and the off-brand button. That is a clear improvement, not core-promise damage: medium, not high.


### [MEDIUM] Lists header uses the stock gray segmented control at the top of the app's signature screen

'My Courses' is the Beli-style heart of the product, and its mode switch is a default `UISegmentedControl` — gray track, white sliding thumb, the most 'unstyled iOS' component there is. It sits right under the large title and sets the tone for the whole screen. Both light and dark screenshots show the same generic chrome.

**Evidence:** Screenshots: 01-Lists-Played_0_07C245AF...png and dark-01-Lists-Played_0_AD1E085D...png (gray segmented control under 'My Courses'). Code: /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:23 `.pickerStyle(.segmented)`.

**Recommendation:** Replace with a flat custom toggle in the brand language: two text tabs ('Played' / 'Want to Play') with a 2pt FairwayGreen underline on the active tab and a Sand hairline running the full width beneath both — a classic vintage-editorial device. Or a Sand-filled capsule with a FairwayGreen active segment. Either is ~20 lines of SwiftUI and fully flat.

**Verifier:** Confirmed. Both 01-Lists-Played_0_07C245AF...png (light: gray track, white thumb) and dark-01-Lists-Played_0_AD1E085D...png (dark: gray track, lighter thumb) show the default UISegmentedControl directly under the 'My Courses' large title, and ListsView.swift:23 confirms `.pickerStyle(.segmented)`. One caveat tested adversarially: a stock segmented control is itself flat and minimal, so it does not violate 'flat/minimalist' — the violation is against 'vintage/distinctive', and much of the screen's generic feel actually comes from the white background (finding 1). Still, this is the mode switch at the top of the product's flagship Beli-style screen, and the proposed underline-tab replacement is squarely in the stated vintage-editorial language. Medium (clear improvement) is the right severity — not high, but more than polish given its placement.


### [MEDIUM] Leaderboard is a plain system list with ad-hoc medal colors instead of a 'clubhouse honor board' moment

A golf leaderboard is the one screen where the vintage-classic aesthetic (think clubhouse honor rolls, hand-set numerals) could sing, and it's currently an unstyled `.plain` List: default separators, SF numerals, gray chevrons. The top-3 rank colors are hardcoded RGB gold/silver/bronze rather than the palette's SunriseGold token, so even the accent bypasses the design system. The current-user highlight (fairwayGreen at 12%) is the only branded touch.

**Evidence:** Screenshot: 19-Leaderboard_0_FAE3B8C4...png (plain list, yellow-orange '1's). Code: /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:59-63 — `Color(red: 0.85, green: 0.65, blue: 0.13) // gold` etc. instead of .sunriseGold; :45 `.listStyle(.plain)`.

**Recommendation:** Use .sunriseGold for rank 1 (and muted Sand/Clay-derived tones for 2-3), set rank numerals larger in a serif or Righteous with `monospacedDigit`, put the list on Cream with Sand hairlines, and consider a flat circular badge (thin DarkPine ring, gold numeral) for the top three — a badge shape, not a trophy illustration, so it stays minimal.

**Verifier:** Verified in both cited sources. /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:61-63 hardcodes `Color(red: 0.85, green: 0.65, blue: 0.13)` gold plus RGB silver/bronze instead of the .sunriseGold token; line 45 is `.listStyle(.plain)`; line 18 sets rank numerals in system `.headline.monospacedDigit()` (SF); lines 32-34 add gray tertiary chevrons; line 36 confirms the fairwayGreen 0.12 highlight is the only branded touch. Screenshot 19-Leaderboard_0_FAE3B8C4...png matches: default white list, default separators, small yellow-orange rank numerals, gray chevrons. The repeated '1 1 1' ranks are tie behavior on seed data (a known non-issue) and the finding correctly does not rely on that. Medium is right: the screen works, but it is the single best fit for the vintage-clubhouse aesthetic and currently bypasses the design system entirely.


### [MEDIUM] Profile is 100% default iOS grouped-settings chrome with zero brand presence

The Profile tab is the weakest screen on-brand: systemGroupedBackground gray, white inset cards, system-blue-pattern layout, system red 'Sign out'/'Delete account' text, and tinted generic SF symbols (person.badge.plus, info.circle). Nothing on this screen would look different in any template app. The stat row (Played/Followers/Following) is the natural place for a brand moment and it's plain SF text.

**Evidence:** Screenshot: 06-Profile_0_C2DBDEC1...png (gray grouped background, white cards, red system destructive rows); 08-OtherProfile_0_50D39496...png shares the same chrome.

**Recommendation:** Cream page background, cards as Cream-on-Cream separated by Sand hairlines (or white cards with Sand strokes), destructive actions in ClayRed instead of system red, and set the three stat numerals in a larger DarkPine weight with small-caps labels — a scorecard-like stat strip is a period-correct golf reference that stays flat.

**Verifier:** Screenshot 06-Profile_0_C2DBDEC1...png confirms the substance: systemGroupedBackground gray page, white inset-grouped cards, 'Sign out'/'Delete account' in system red (the palette defines ClayRed #B3402F specifically for destructive), and plain SF text for the Played/Followers/Following stat row. 08-OtherProfile_0_50D39496...png shares the identical chrome. One overstatement to correct: it is not literally 'zero' brand presence — the Find friends and About SF symbols are tinted fairwayGreen, and the finding itself admits they are 'tinted generic SF symbols.' That hyperbole aside, the screen is indistinguishable from a template settings screen and clashes with the Cream/Sand 'Refined Classic' language, so the finding stands at medium.


### [MEDIUM] The pairwise comparison screen — the product's emotional core — is two gray rectangles on white

'Which did you like more?' is the interaction that defines this app, and it renders as two `.quaternary` gray rounded rects with a lowercase gray 'vs' between them. It's functional but characterless — no Cream card faces, no brand typography, nothing that makes the duel feel like a moment. The 'NEW' pill is a washed green capsule that barely registers.

**Evidence:** Screenshot: 12-Log-Comparison_0_B15DB4D4...png. Code: /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:72 `.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))`; :60 NEW tag as fairwayGreen 0.15 capsule.

**Recommendation:** Cream cards with a 1px Sand (or DarkPine) stroke; set 'VS' as a small centered roundel — a DarkPine circle with 'VS' knocked out in Righteous, echoing the wordmark's golf-ball discs; make the NEW tag a solid SunriseGold chip with DarkPine text. All flat fills and strokes, no shadow needed.

**Verifier:** Exactly as described. /Users/leon-an/3Wood/3Wood/Features/Ranking/ComparisonView.swift:72 is `.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))` and lines 56-61 render the NEW tag as a fairwayGreen-0.15 capsule; line 24-26 sets 'vs' in secondary gray. Screenshot 12-Log-Comparison_0_B15DB4D4...png shows two flat light-gray rounded rects on white with a lowercase gray 'vs' and a barely-visible washed-green NEW pill. Nothing here misreads the image, and the recommendation (flat Cream cards, strokes, no shadows) is consistent with the flat/minimalist yardstick rather than fighting it. Medium is correct: functional, but this is the app's defining interaction and it carries no brand character.


### [MEDIUM] Righteous exists only in the wordmark; the score numerals that define the product use generic SF Rounded

The brand's one display font appears exactly twice (Welcome, Feed nav). Every score — the app's currency — is SF Rounded in ScoreBadge, and the big '9.8' hero moment on the rank-result screen is the same small pill floating in a huge white void. The result screen (the payoff of the whole logging flow) has no celebratory brand treatment at all: white screen, small badge, gray caption.

**Evidence:** Screenshots: 13-Log-Result_0_32145F14...png (tiny 9.8 pill centered in empty white screen), 01-Lists-Played (SF Rounded pills). Code: /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift:11 `.font(.system(... design: .rounded ...))`; /Users/leon-an/3Wood/3Wood/Features/Ranking/RankResultView.swift.

**Recommendation:** Keep SF Rounded in small badges for legibility, but on RankResultView set the score huge (80-100pt) in Righteous on a Cream field, with '#1 of your Liked it courses' as a small-caps DarkPine line and a Sand hairline rule above/below — a vintage scorecard flourish that costs nothing in complexity. Consider Righteous for the 'My Courses' large title as a second brand touchpoint.

**Verifier:** Font claim verified by grep: 'Righteous' appears only in /Users/leon-an/3Wood/3Wood/Core/DesignSystem/Wordmark.swift, and Wordmark( is instantiated in exactly two places — Features/Auth/WelcomeView.swift:12 and Features/Feed/FeedView.swift:35 — matching 'exactly twice (Welcome, Feed nav).' ScoreBadge.swift:11 confirms SF Rounded (`design: .rounded`). RankResultView.swift:17-18 shows the payoff screen just reuses ScoreBadge with `.scaleEffect(2.2)`, and screenshot 13-Log-Result_0_32145F14...png confirms a plain white screen with a modest green pill, gray caption, and large empty voids. Minor overstatement: 'tiny 9.8 pill' — at 2.2x scale it is medium-sized, not tiny, though it still floats in a mostly empty screen (and scaleEffect-ing a badge rather than typesetting the numeral is itself a smell). The core claim — the flow's celebratory payoff has zero brand treatment while the brand's only display font sits unused — is accurate. Medium severity is appropriate.


### [LOW] Metadata chips and rank numerals use system grays instead of the warm neutral system

The Resort/Public/Private/Semi-Private capsules on Search, Lists, and Map-List are default systemGray fills with gray text, and the left-edge rank numbers in My Courses are plain gray SF digits. These small repeated elements are where 'warmth' accumulates — currently they read as unstyled placeholders.

**Evidence:** Screenshots: 03-Search-Results_0_EEF72A1C...png ('Resort'/'Public' gray chips), 16-Map-ListView_0_0A9DEA36...png (same chips), 01-Lists-Played_0_07C245AF...png (gray rank digits 1-10).

**Recommendation:** Fill the chips with Color.sand and set their text in DarkPine (light) / the sand dark-variant pairing (dark) — instant vintage-label feel, still flat. Set list rank numerals in DarkPine monospacedDigit, slightly larger, so the ranked list reads like a classic countdown.

**Verifier:** Verified against the screenshots. 03-Search-Results_0_EEF72A1C....png shows 'Resort'/'Public' capsules in default systemGray fill with gray text; 16-Map-ListView_0_0A9DEA36....png repeats the same gray 'Private'/'Semi-Private' chips on every row; 01-Lists-Played_0_07C245AF....png shows plain gray SF rank digits 1-10. On the same screens the score badges (FairwayGreen) and wordmark are fully on-palette, so the gray elements genuinely read as the unstyled outliers rather than a deliberate minimalist choice — the app's own design system (Sand/DarkPine warm neutrals) exists and is simply not applied here. Not attributable to seed data. Low severity is correctly stated: it is accumulated polish, not something that hurts users or the core promise.


### [LOW] Feed and empty states lean on default SF symbols (trophy, flag.checkered, bookmark) with no brand drawing

The Feed's leaderboard button is the stock SF trophy, row icons are flag.checkered/bookmark.fill, and empty states use figure.golf again. None are wrong functionally, but the app has exactly one custom-drawn asset (GolfBallShape) and it proves the team can draw flat vector glyphs; the generic symbol set keeps every secondary surface feeling like a template. The Feed does correctly carry the wordmark in the nav bar, which is the right instinct.

**Evidence:** Screenshot: 18-Feed_0_A9309486...png (SF trophy top-right, checkered-flag/bookmark row glyphs; note Save Password system dialog partially obscures — underlying chrome still visible). Code: /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:14,41,65.

**Recommendation:** Draw 3-4 tiny flat glyphs in the GolfBallShape idiom (pin flag, dimpled ball, simple laurel/roundel for leaderboard) as SwiftUI Shapes or a small custom symbol set, and reuse them for feed rows, empty states, and the leaderboard entry point. Keep line weight uniform and single-color (DarkPine/FairwayGreen) to stay 2-D.

**Verifier:** Verified in both code and screenshot. /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift lines 14 (figure.golf empty state), 41 (trophy toolbar icon), and 65 (flag.checkered / bookmark.fill row glyphs) match the citation exactly, and 18-Feed_0_A9309486....png shows the stock trophy and row glyphs (Save Password dialog obscures midscreen but the cited chrome is visible). The supporting claim also holds: GolfBallShape in Core/DesignSystem/Wordmark.swift:51 is the only custom-drawn Shape in the design system. One tempering point: SF Symbols are flat/2-D and are tinted fairwayGreen, so this is compatible with the minimalist half of the owner's taste — it only underserves the vintage/brand half. That makes it a legitimate but modest 'Refined Classic' polish item; low severity is right, and the recommendation (small custom flat glyph set) is proportionate.


## Color Theme

**Strengths (keep these):**

- White on FairwayGreen #1E5B33 is 8.08:1 (AAA) — the light-mode primary button, score chips, and 'Update my ranking' CTA are excellently readable (04-CourseDetail light, PrimaryButtonStyle.swift). Do not lighten this green.
- Score-band semantics are applied with perfect consistency wherever ScoreBadge is used — lists, course detail, friends' scores, feed, map pins all route through the single ScoreBadge component with one threshold definition (Core/DesignSystem/ScoreBadge.swift), so green/gold/red never contradicts itself across screens.
- A single app-wide accent via MainTabView .tint(Color.fairwayGreen) plus the AccentColor asset gives coherent brand color to tab bar, links, toggles, and nav buttons in both modes with zero per-screen drift.
- Every palette token has a properly structured light/dark pair in the asset catalog (verified in all six .colorset Contents.json files) — the infrastructure for a correct dark theme is already done; the gaps are adoption, not architecture.
- The wordmark (Righteous, dimpled golf-ball O's, fairwayGreen fill in Wordmark.swift, seen on 00-Welcome.png and the Feed header) is genuinely distinctive and on-taste for vintage/flat — keep untouched.
- The leaderboard 'me' row highlight (fairwayGreen at 12% opacity, LeaderboardView.swift line 36) reads clearly in both light and dark screenshots (19 vs dark-19) without breaking text contrast — a good pattern to reuse for other highlighted rows.
- FairwayGreen 15%-opacity capsules with fairwayGreen text (NEW tag in 12-Log-Comparison, near-me chip in CourseMapView.swift lines 126-127) are a tasteful, high-contrast flat treatment consistent with the vintage direction.


### [HIGH] White-on-SunriseGold score badges fail WCAG at 2.25:1 (light) and 1.89:1 (dark)

ScoreBadge renders mid-band scores (3.4-6.7) as white bold text on SunriseGold. Computed contrast: white on #D9A441 = 2.25:1; white on the dark variant #E3B65A = 1.89:1. Both fail AA 4.5:1 for normal text and even the 3:1 large-text bar. The score number is the app's core datum, so mid-rated courses become the hardest ones to read. No demo screenshot happens to show a gold badge (all seed scores are >=6.7 or the gray 7.5), which is why this hasn't been noticed visually.

**Evidence:** /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift lines 13 (.foregroundStyle(.white)) and 24 (case 3.4..<6.7: return .sunriseGold). Ratios computed from Assets.xcassets/SunriseGold.colorset (#D9A441 light / #E3B65A dark).

**Recommendation:** Switch the gold badge to dark text instead of darkening the gold (keeps the vintage scorecard look): DarkPine #12301C on #D9A441 computes to 6.37:1, passing AA. In dark mode use #12301C on #E3B65A (higher still). Alternatively add a per-band foreground in ScoreBadge: white for green/red, .darkPine for gold.

**Verifier:** Fully verified. ScoreBadge.swift line 13 hardcodes .foregroundStyle(.white) and line 24 maps 3.4..<6.7 to .sunriseGold. Resources/Assets.xcassets/SunriseGold.colorset confirms #D9A441 light / #E3B65A dark. I recomputed the ratios independently: white on #D9A441 = 2.25:1, white on #E3B65A = 1.89:1 — exactly as claimed, failing AA 4.5:1 and even the 3:1 large-text bar. The claim that no screenshot shows a gold badge also holds: 01-Lists-Played shows only green badges (all seed scores 6.9-9.8), so this is a latent bug for any real user with mid-rated courses. The score is the app's core datum and mid-band (3.4-6.7) is a third of the scale, so high severity is correct. The proposed fix (DarkPine on gold, 6.37:1 verified) is sound and on-taste.


### [HIGH] Cream, Sand, and DarkPine are dead tokens — the 'Refined Classic' warm base never renders

grep confirms .cream, .sand, and .darkPine appear nowhere in code outside the doc comment in Colors.swift; every screen sits on plain systemBackground/systemGray6. Light screenshots are pure white with gray cards, dark screenshots pure black. Palette presence per screen is essentially one green tint plus score chips — the warm cream/sand foundation that defines the stated vintage aesthetic is 0% present. Screens like Welcome, Comparison, and Log-Result read as generic iOS gray, not 'Refined Classic'.

**Evidence:** grep of /Users/leon-an/3Wood/3Wood for cream/sand/darkPine: only hits are comment lines 7-10 of Core/DesignSystem/Colors.swift. Visual confirmation: 01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png (pure white bg), 12-Log-Comparison_0_B15DB4D4-5F04-4A7B-9008-3B33D3C9DA3E.png (gray systemGray6 cards on white), 00-Welcome.png (white).

**Recommendation:** Adopt Cream #F7F3E8 as the app-wide screen background (List .scrollContentBackground(.hidden) + .background(Color.cream)), keep cards white or #FFFFFF-on-cream, and use Sand #E3D9C2 for hairline borders/segmented-control track. FairwayGreen on Cream is 7.29:1 and DarkPine on Cream 12.93:1, so all existing text pairings survive.

**Verifier:** Verified. Case-insensitive grep across 3Wood/*.swift finds cream/sand/darkPine only in the doc comments of Core/DesignSystem/Colors.swift lines 2-10 (the WriteReviewSheet.swift hits are substring false positives on 'whitespacesAndNewlines'/'isSaving'). The colorsets exist in Resources/Assets.xcassets (Cream, Sand, DarkPine all present) but are never referenced. Screenshots confirm the visual claim: 01-Lists-Played and 00-Welcome are pure white with only green accents; 12-Log-Comparison is systemGray6 cards on white. Against the owner's stated 'Refined Classic' vintage/warm yardstick — which is this review's yardstick — the defining warm foundation is 0% present and the app reads as stock iOS. For a color-theme review this is the central gap, and the finding verified its own contrast math (FairwayGreen on Cream 7.29:1, DarkPine on Cream 12.93:1 — both correct), so the fix is safe. High stands.


### [MEDIUM] Bucket picker abandons the palette: system .orange and .red break both semantics and contrast

The like/fine/dislike buckets are the origin of the green/gold/red score bands, but BucketPickerView colors 'It was fine' with system orange #FF9500 and 'Didn't like it' with system red #FF3B30 instead of SunriseGold and ClayRed. The screenshot shows two saturated, glossy iOS colors sitting under the muted FairwayGreen button — visually off-palette for the vintage/flat taste, and semantically inconsistent (the bucket a user taps is not the color of the badge that results). Contrast also fails: white on #FF9500 = 2.20:1, white on #FF3B30 = 3.55:1.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Ranking/BucketPickerView.swift lines 33-38 (case .fine: .orange, case .disliked: .red). Screenshot 11-Log-BucketPicker_0_9C171F22-7042-4E62-A207-D3D9D785844D.png — middle and bottom buttons are clearly system orange/red next to the muted green top button.

**Recommendation:** Use the tokens: .liked = fairwayGreen (as now), .fine = sunriseGold with DarkPine #12301C label text, .disliked = clayRed with white text (5.69:1). This makes the picker a preview of the badge colors the user will live with.

**Verifier:** Verified as real. BucketPickerView.swift lines 33-38 use .orange and .red instead of .sunriseGold/.clayRed, and screenshot 11-Log-BucketPicker shows exactly what's claimed: saturated system orange and red buttons directly under the muted FairwayGreen one — clearly off-palette for the flat/vintage taste, and semantically mismatched with the score-badge colors these buckets produce. Contrast math checks out (white on #FF9500 = 2.20:1, on #FF3B30 = 3.55:1, white on ClayRed = 5.69:1). However, high is overstated: the failure is confined to one transient screen where each button has redundant cues (position, icon, distinct hue) and large bold labels, so real-user harm is limited compared to findings 1-2. It is a clear, cheap improvement — medium.


### [MEDIUM] Leaderboard medal colors are hardcoded and the gold/silver rank numerals are near-invisible in light mode

medalColor() hardcodes gold #D9A621, silver #99999E-equivalent, bronze — bypassing the token system and shipping no dark variants. In the light screenshot the three '1' numerals are thin gold digits on white: computed 2.23:1 for gold and 2.84:1 for silver, failing even the 3:1 large-text AA bar. In dark mode the same gold on black is 9.43:1, so only light mode is broken — a mode-asymmetric readability bug on the awards signal.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift lines 59-65. Screenshot 19-Leaderboard_0_FAE3B8C4-41AC-4E06-94C2-817CC3B9B609.png — top three gold '1's are faint against white; compare dark-19-Leaderboard_0_FC03A592-48E0-4982-AF73-18937425A1AC.png where they read fine.

**Recommendation:** Tokenize as .medalGold/.medalSilver/.medalBronze asset colors with light/dark variants. Light-mode gold should be an antique brass ~#8A6A1F (5.05:1 on white — passes AA, and reads more vintage than bright gold); silver ~#6E6E73, bronze ~#7A4A1E. Keep the current brighter values as the dark variants.

**Verifier:** Verified. LeaderboardView.swift lines 59-65 hardcode Color(red:green:blue:) literals with no dark variants, bypassing the token system; the literals resolve to #D9A621 gold, #99999E silver, #B87333 bronze, matching the finding. Recomputed ratios: gold on white 2.23:1, silver 2.84:1 (both fail 3:1), bronze 3.79:1, and gold on black 9.43:1 — confirming the mode asymmetry. Screenshot 19-Leaderboard (light) shows the three gold '1' numerals visibly faint against the near-white background, while dark-19-Leaderboard shows them reading clearly. 'Near-invisible' is mildly overstated (they are legible, just low-contrast), but the core claim and the medium severity are correct. The tie display (three rank-1 entries) is seed-data behavior, not part of this finding. The antique-brass recommendation (#8A6A1F = 5.05:1, verified) also fits the vintage yardstick.


### [MEDIUM] Dark-mode FairwayGreen and ClayRed fills drop white text below 4.5:1

White on dark FairwayGreen #3E8E5C computes to 4.02:1 (light mode is 8.08:1) — this is the 'Update my ranking' primary button and every green score chip in dark mode. White on dark ClayRed #CD5A45 is 4.08:1. Both pass only via the large/bold-text exemption (badge text is 15pt bold, button label 17pt semibold), so this is borderline rather than broken, but any future normal-weight use of these fills (captions, tags) will fail AA, and the dark CTA is visibly lower-contrast than its light sibling.

**Evidence:** Ratios computed from Assets.xcassets FairwayGreen/ClayRed dark components. Compare 04-CourseDetail_0_1F5E3373-75B2-432E-9787-3994DA8F628F.png vs dark-04-CourseDetail_0_1DCC2C47-DC71-4A9A-9808-04732571EE7A.png — the dark 'Update my ranking' button is noticeably paler behind white text. Fill sites: Core/DesignSystem/PrimaryButtonStyle.swift line 10, ScoreBadge.swift line 17.

**Recommendation:** Nudge the dark variants down: FairwayGreen dark #37814F (white = 4.76:1) and ClayRed dark #C24936 (white = 4.88:1). Both stay clearly lighter than the light-mode values (so tinted text on black still passes: #37814F on black is above 4.5:1) and keep the muted, desaturated vintage character.

**Verifier:** Verified independently. Colorsets confirm FairwayGreen dark #3E8E5C and ClayRed dark #CD5A45 (Resources/Assets.xcassets/*.colorset/Contents.json), and my own WCAG computation reproduces the cited ratios: white on #3E8E5C = 4.02:1 (light #1E5B33 = 8.08:1), white on #CD5A45 = 4.08:1. Fill sites confirmed at PrimaryButtonStyle.swift line 10 (white on fairwayGreen) and ScoreBadge.swift lines 13/17. Screenshots dark-04-CourseDetail vs 04-CourseDetail visibly show the paler dark 'Update my ranking' button. The finding is actually slightly UNDERSTATED in one respect: the compact ScoreBadge uses caption2 (11pt) bold white text (ScoreBadge.swift line 11), which does not qualify for the WCAG large-text exemption, and compact badges are used across SearchView.swift:65, CourseMapView.swift:88, CourseDetailView.swift:85, OtherProfileView.swift:49 — so dark mode has genuine AA failures today, not just future risk. The proposed replacement ratios also check out (#37814F = 4.76:1, #C24936 = 4.88:1). Medium is correct.


### [MEDIUM] Destructive actions and error text use bright system red instead of ClayRed

Colors.swift documents clayRed as 'low scores, destructive emphasis', but Sign out / Delete account use role-based system red (#FF3B30 light / #FF453A dark) and auth error messages use .red. In both profile screenshots the red rows are the most saturated element on screen and clash with the muted palette — exactly the generic-iOS note the vintage direction is trying to avoid. ClayRed passes where it matters: #B3402F on white is 5.69:1.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Profile/ProfileView.swift lines 46-51 (role: .destructive buttons); Features/Auth/EmailSignInView.swift line 40 and Features/Auth/UsernameSetupView.swift line 32 (.foregroundStyle(.red)). Screenshots 06-Profile_0_C2DBDEC1-3E1E-48F0-A257-912948FF5605.png and dark-06-Profile_0_58AE60B2-E529-4E30-B61B-DCD956D65946.png — 'Sign out'/'Delete account' in vivid system red.

**Recommendation:** Keep role: .destructive for behavior but add .foregroundStyle(Color.clayRed) (or .tint(.clayRed) on the section) to the buttons, and use Color.clayRed for inline error text. Leave the system confirmation dialog alone.

**Verifier:** Verified. ProfileView.swift lines 46-51 show both 'Sign out' and 'Delete account' as role: .destructive with no tint override; EmailSignInView.swift:40 and UsernameSetupView.swift:32 both use .foregroundStyle(.red). Colors.swift line 11 explicitly documents clayRed as 'low scores, destructive emphasis', so this is a violation of the app's own design system, not an invented preference. Screenshots 06-Profile and dark-06-Profile confirm the vivid system red rows are the most saturated elements on an otherwise muted green/neutral screen — a genuine clash with the stated vintage/Refined-Classic taste. Contrast claim verified: #B3402F on white = 5.69:1, so the fix is safe. Medium (clear improvement, consistent with the owner's yardstick) is right.


### [MEDIUM] Dark theme is generic pure-black iOS, losing all vintage warmth

Every dark screenshot sits on #000000 with default dark-gray cards; the designed warm-charcoal surfaces (Cream dark #20221D, a green-tinged warm near-black, and Sand dark #35382F) never appear because the tokens are unused. Light mode at least gets warmth from the green tint; dark mode has zero palette character outside the tint color — it could be any app. The dark Cream/Sand values were clearly designed for exactly this and are wasted.

**Evidence:** dark-01-Lists-Played_0_AD1E085D-C27C-4E7E-87E7-73418F93A273.png and dark-06-Profile_0_58AE60B2-E529-4E30-B61B-DCD956D65946.png — pure black background, neutral gray cards. Token definitions present but unreferenced: Resources/Assets.xcassets/Cream.colorset and Sand.colorset dark components; zero code references.

**Recommendation:** Same fix as the light-mode background finding, and it comes for free: applying Color.cream as the scroll background automatically yields #20221D in dark mode (a warm pine-black), with Sand #35382F for separators. FairwayGreen dark on #20221D is 4.00:1 — fine for bold tinted text, but pair any normal-weight green text there with the darkened #37814F-family value from the dark-fill finding.

**Verifier:** Verified. Grep across all Swift files finds zero references to .cream or .sand outside the Colors.swift doc comment, yet both colorsets define purpose-built dark variants (Cream dark #20221D, Sand dark #35382F in Resources/Assets.xcassets). Screenshots dark-01-Lists-Played and dark-06-Profile confirm pure #000000 backgrounds with neutral gray system cards — none of the designed warm surfaces appear; the only palette presence is the green tint on icons/badges. My computed ratio for FairwayGreen dark on #20221D is 4.00:1, matching the finding's caveat. Since the product's stated identity is vintage warmth and dark mode currently 'could be any app', medium is appropriate. (The recommendation references a separate light-mode background finding not in this batch, but that does not affect validity.)


### [LOW] Gold carries two opposite meanings: 'mediocre score' and 'first place award'

In the score system, gold is the middle band — a 5.0 'it was fine' course. On the leaderboard (and the trophy toolbar icon on Feed), gold means winner/#1. Same hue family, opposite valence. Within one Feed tab a user sees gold as 'top of leaderboard' and one tap away gold as 'meh course'. This is a common Beli-style tension, but the current implementation makes it worse by using two uncoordinated golds (#D9A441 token vs hardcoded #D9A621).

**Evidence:** Core/DesignSystem/ScoreBadge.swift line 24 (gold = 3.4..<6.7 mid band) vs Features/Feed/LeaderboardView.swift line 61 (gold = rank 1). Screenshots 19-Leaderboard_0_FAE3B8C4-41AC-4E06-94C2-817CC3B9B609.png (gold = best) vs the badge semantics on 04-CourseDetail_0_1F5E3373-75B2-432E-9787-3994DA8F628F.png.

**Recommendation:** Differentiate by tone and treatment rather than abandoning either: awards use the deeper brass #8A6A1F family with an icon (trophy/laurel), mid scores keep the lighter #D9A441 chip with dark text. Distinct value + shape means the shared hue stops being ambiguous.

**Verifier:** Partially verified, severity overstated. The code facts check out: ScoreBadge.swift line 24 makes sunriseGold the mediocre 3.4–6.7 band, and LeaderboardView.swift line 61 hardcodes Color(red: 0.85, green: 0.65, blue: 0.13) = #D9A621 for rank 1, uncoordinated with the #D9A441 token; screenshot 19-Leaderboard shows gold rank numbers for the top three. However, two things weaken it. First, the cited 'trophy toolbar icon on Feed' is NOT gold — FeedView.swift line 43 tints it fairwayGreen, so part of the evidence is wrong. Second, on the leaderboard gold appears inside the universal gold/silver/bronze medal trio (lines 61-63) next to an explicit rank number, so context disambiguates it from a score chip; real-user confusion is unlikely, and Beli-style amber-for-mid is a convention the owner deliberately adopted. What remains is a legitimate token-hygiene nit (hardcode the medal gold vs the sunriseGold token) and optional tonal differentiation — polish, not a clear user-facing problem. Downgrade to low.


### [LOW] DarkPine (and its pale-mint dark flip #D7E4DA) is defined but used nowhere

The darkPine token — documented for 'headings, emphasis' — has zero call sites, so its light/dark flip from near-black green #12301C to pale mint #D7E4DA currently affects nothing. The flip itself is semantically coherent (it is a text-emphasis token, so dark-text-becomes-light is correct: 12.93:1 on Cream light, 12.23:1 on dark Cream — both AAA). The only caution is temperature: #D7E4DA is slightly cool/minty for a warm vintage dark theme, which will matter the moment it is adopted for large headings.

**Evidence:** grep for darkPine across /Users/leon-an/3Wood/3Wood returns only Core/DesignSystem/Colors.swift line 7 (comment) and the asset Resources/Assets.xcassets/DarkPine.colorset. Headings in all screenshots ('My Courses' in 01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png, 'Profile' in dark-06) render in plain system label black/white.

**Recommendation:** Actually use it: apply darkPine to large titles, section headers ('Friends' scores', 'Their courses') and the wordmark-adjacent headings. Warm the dark variant slightly toward cream — e.g. #DEE4D4 or #E0E4D6 — so dark-mode headings read parchment rather than mint.

**Verifier:** Verified all three evidence claims. (1) grep over /Users/leon-an/3Wood/3Wood returns exactly one Swift hit: the doc comment at Core/DesignSystem/Colors.swift:7 describing .darkPine as 'headings, emphasis'; no view code uses the token, so it is dead. (2) Resources/Assets.xcassets/DarkPine.colorset/Contents.json confirms the exact hex pair: light 0x12301C, dark 0xD7E4DA. (3) Screenshots confirm headings use plain system label color instead: 'My Courses' is black in 01-Lists-Played_0_07C245AF-B0F4-4746-A3D9-666BA750DB78.png and 'Profile' is white in dark-06-Profile_0_58AE60B2-E529-4E30-B61B-DCD956D65946.png. Refutation attempt fails: while the token is invisible to users today, the design-system header actively documents it as the heading color, so the mismatch between documentation and reality is a genuine hygiene issue, and the slightly cool/minty dark variant (#D7E4DA vs the warm cream/sand neutrals) is a latent temperature clash with the vintage 'Refined Classic' palette that will surface as soon as the token is adopted. The finding does not misread the screenshots, is not seed data, and does not contradict the owner's taste. Severity 'low' is correctly calibrated — no current user-facing impact, pure polish/consistency.


## Gap review: Accessibility: VoiceOver labels and Dynamic Type are completely unreviewed (and nearly absent from the code)

**Strengths (keep these):**

- The core log/rank flow is built from real Buttons with text labels and enormous tap targets: BucketPickerView uses full-width .borderedProminent buttons with Label text (BucketPickerView.swift:16-26) and the pairwise comparison cards are full-width buttons ~130pt tall carrying name + location text (ComparisonView.swift:53-75; screenshot 12-Log-Comparison_0_B15DB4D4...png) — a VoiceOver user can complete the entire ranking flow. Do not restructure these.
- Wordmark.swift:30-31 correctly collapses the decorative letters-plus-golf-ball composition into a single element with .accessibilityElement(children: .ignore) + .accessibilityLabel("3Wood") — exactly the right pattern for a custom logotype.
- Dynamic Type discipline in typography: aside from the logo (intentional fixedSize) and the decorative welcome glyph, every font in the app is a scalable text style (.headline/.subheadline/.caption...), with no hard-coded point sizes in content views — body text will scale.
- The Map feature offers a full list-mode equivalent of the map (CourseMapView.swift:132-155; screenshot 17-Map-Filtered_0_F6D40867...png), so map content is never gesture-only; the state jump menu also uses Label("State", systemImage:) so it announces correctly.
- Search rows disambiguate community scores with explicit text — the 'avg' caption under the badge and a textual 'Not rated' fallback (SearchView.swift:62-74; screenshot 03-Search-Results_0_EEF72A1C...png) — meaning is not left to color/shape alone here.
- Tab bar and profile menu use Label(title, systemImage:) throughout (MainTabView.swift:7-19, ProfileView.swift:33-43), giving correct VoiceOver names for all primary navigation.
- PrimaryButtonStyle produces full-width CTAs with 15pt vertical padding on .headline text (PrimaryButtonStyle.swift:5-13) — comfortably above 44pt and scaling with Dynamic Type.
- Empty and error states consistently use ContentUnavailableView with descriptive text and an actionable button (e.g. FeedView.swift:13-20, ListsView.swift:62-69, LogCourseFlow.swift:47-53), which VoiceOver reads well and which gives non-visual users a recovery path.


### [HIGH] Profile rows driven by onTapGesture are invisible as controls to VoiceOver

The three people-browsing surfaces (Find Friends, Followers/Following, Leaderboard) navigate to a profile via .contentShape(Rectangle()).onTapGesture on a plain HStack instead of a Button or NavigationLink. VoiceOver exposes the row as fragmented static text (username, display name, a separate 'Follow' button, and a bare 'chevron' image) with no button trait, no combined label, and no announcement that the row opens a profile. A VoiceOver user has no way to discover that leaderboard entries or friend-search results are tappable, which effectively blocks the browse-friends/leaderboard path non-visually. (The comment at FindFriendsView.swift:10-13 explains the SwiftUI hit-testing motivation, but the accessibility cost was not compensated.)

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Profile/FindFriendsView.swift:30-31, /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift:92-93, /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:37-43; screenshots /tmp/3wood-review/shots-light/07-FindFriends_0_7C80C14E-2E28-46FD-9942-8D72CF65B439.png and 19-Leaderboard_0_FAE3B8C4-41AC-4E06-94C2-817CC3B9B609.png (rows whose only affordance is a visual chevron)

**Recommendation:** Keep the tap gesture for sighted taps but add .accessibilityElement(children: .combine), .accessibilityAddTraits(.isButton), a label like 'birdie_ben, 12 courses, view profile', and .accessibilityAction to trigger the navigation. Expose the Follow button as a custom accessibility action on the combined row so both actions are reachable.

**Verifier:** Verified in code: FindFriendsView.swift:30-31, PeopleListView.swift:92-93, and LeaderboardView.swift:37-43 all use .contentShape(Rectangle()).onTapGesture on a plain HStack with no accessibility modifiers (a grep confirms the only accessibilityLabel in the whole app is on the Wordmark). Screenshots 07-FindFriends and 19-Leaderboard confirm the only visual affordance is a chevron. VoiceOver exposes these rows as fragmented static text with no button trait, so the tap-to-open-profile behavior is undiscoverable across all three people-browsing surfaces. One caveat: VoiceOver's pass-through tap on activation may still trigger the gesture if a user tries, so 'effectively blocks' slightly overstates it — but undiscoverable primary navigation on the core social feature justifies high for an accessibility review.


### [MEDIUM] ScoreBadge has no accessibility label; unrated state reads as a bare dash and sentiment is color-only

ScoreBadge is the app's core rating UI (feed, lists, course detail, friends' scores, map pins) and renders only Text("9.2") or an en dash for nil. VoiceOver announces a context-free number ('nine point two') or nothing intelligible for the dash. The liked/mid/low meaning (green/gold/red capsule) is carried by color alone with no textual or accessible equivalent — the numeric value partially compensates, but the nil case ('–') communicates nothing non-visually, and low-vision/color-blind users lose the tier signal entirely.

**Evidence:** /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift:10-27 (Text(score.map{...} ?? "–"), color switch at lines 20-27 is the only sentiment channel); visible in /tmp/3wood-review/shots-light/03-Search-Results_0_EEF72A1C-C1B4-4FD4-848B-AA8EE2FC9309.png (green 8.8 chip) and 18-Feed_0_A9309486-A162-4958-8899-C644932F7D83.png

**Recommendation:** Inside ScoreBadge add .accessibilityLabel(score.map { "score \(String(format: "%.1f", $0)) out of 10" } ?? "not rated"). Because the component is shared, one change fixes every screen. Optionally append the tier ('liked'/'fine'/'disliked') so the color coding has a non-visual equivalent.

**Verifier:** Verified: ScoreBadge.swift:10 renders Text(score.map{...} ?? "–") and lines 20-27 carry liked/mid/low tier through capsule color alone; no accessibility modifiers exist in the file. Screenshots 03-Search-Results and 18-Feed confirm the badge appears throughout core surfaces. The number is still announced, so VoiceOver users get partial information, but the nil dash is meaningless non-visually and the tier is invisible to color-blind users. Medium is correct: real gap, one shared-component fix, but not a full blocker.


### [MEDIUM] Bookmark (want-to-play) toolbar toggle conveys no state to VoiceOver

The course-detail bookmark button is icon-only; the saved/unsaved distinction is solely bookmark vs bookmark.fill. VoiceOver announces the SF Symbol default name ('Bookmark') with no toggle trait and no value, so a VoiceOver user cannot tell whether a course is already on their want-to-play list and risks silently removing it. This is the only way to add to the want-to-play list, a core feature.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:119-127 (Button { toggleBookmark } label: Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark") with no accessibility modifiers); screenshot /tmp/3wood-review/shots-light/04-CourseDetail_0_1F5E3373-75B2-432E-9787-3994DA8F628F.png (top-right glyph)

**Recommendation:** Add .accessibilityLabel("Want to play") plus .accessibilityValue(isBookmarked ? "on" : "off") (or .accessibilityAddTraits with isToggle-style phrasing, e.g. label 'Remove from want to play' / 'Add to want to play').

**Verifier:** Verified: CourseDetailView.swift:119-127 shows the icon-only Button with Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark") and no accessibility label, value, or trait; screenshot 04-CourseDetail confirms the bare glyph top-right. The saved/unsaved state genuinely has no non-visual channel, and this is the sole entry point to the want-to-play list from course detail. Medium is right — the default 'Bookmark' announcement at least conveys rough purpose, but state is unknowable and silent unbookmarking is a real risk.


### [MEDIUM] Icon-only toolbar buttons rely on SF Symbol default names, several of which are wrong or vague

Four toolbar controls are bare Image(systemName:) buttons: the Feed trophy (opens Leaderboard — announced as 'Trophy'), the Lists '+' (starts the log flow — announced as 'Add' with no object), the Map mode toggle (list.bullet/map), and the Map filter menu (line.3.horizontal.decrease.circle, whose default announcement does not say 'filter courses by type' nor that a filter is active when the .fill variant shows). The filter's active state is conveyed only by the filled glyph. Notably these buttons received accessibilityIdentifier for UI tests but no accessibilityLabel for users.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:37-44, /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:33-39, /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:157-175; screenshot /tmp/3wood-review/shots-light/22-Map-Controls_0_00C3AC51-366A-48CB-93D5-95F184C0BDC7.png (three unlabeled glyphs across the top bar)

**Recommendation:** Add explicit labels: .accessibilityLabel("Leaderboard"), .accessibilityLabel("Log a course"), .accessibilityLabel(mode == .map ? "Show list" : "Show map"), and on the filter menu .accessibilityLabel("Filter by course type") + .accessibilityValue(typeFilter.rawValue).

**Verifier:** Verified: FeedView.swift:37-44 (trophy NavigationLink with accessibilityIdentifier but no label), ListsView.swift:33-39 (bare 'plus'), CourseMapView.swift:157-175 (mode toggle and filter menu with identifiers 'mapModeToggle'/'mapFilter' but no user-facing labels; active filter conveyed only by the .fill glyph variant). Screenshot 22-Map-Controls shows the unlabeled glyphs. Two small overstatements: the Lists '+' actually has no accessibilityIdentifier either, and some of these SF Symbols carry semi-usable system labels ('Add', and the filter glyph reads roughly as 'filter' on modern iOS) — so announcements are vague rather than absent. Medium fits: clear improvement, four cheap one-line fixes, but users can partially guess the defaults.


**Reported but unverified (verifier agent stalled):**

- [medium] Map pin tap targets are ~26x20pt compact score chips, far below 44x44pt — Map annotations render a compact ScoreBadge (minWidth 26, caption2 text with 5/3pt padding) as the entire NavigationLink hit area — roughly 26-34pt wide by ~20pt tall on screen. Users with motor impairments (and everyone on a moving map) will struggle to hit them, and unrated courses show an even less distinguishable gray '–' chip. The list mode is a genuine fallback, but the map itself fails the 44pt guideline. *(Evidence: /Users/leon-an/3Wood/3Wood/Features/Map/CourseMapView.swift:85-91 (Annotation content is NavigationLink { ScoreBadge(score:, compact: true) }); /Users/leon-an/3Wood/3Wood/Core/DesignSystem/ScoreBadge.swift:14-16 (compact: minWidth 26, padding 5/3))*
- [medium] Fixed-width rank-number columns truncate at accessibility Dynamic Type sizes — Ranked-list rows pin the rank number into fixed frames: 28pt (my Played list, .headline), 32pt (Leaderboard, .headline), 24pt (other profile, .subheadline), and the feed's leading icon column is a fixed 24pt. At AX3-AX5 Dynamic Type, .headline grows past 40pt, so two-digit ranks no longer fit 24-32pt and render as '…' or clipped glyphs, making the ranking — the app's core output — unreadable for large-text users. None of these views set dynamicTypeSize caps or use ViewThatFits, and there is no minimumScaleFactor anywhere in the app. *(Evidence: /Users/leon-an/3Wood/3Wood/Features/Lists/ListsView.swift:75-78, /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:17-20, /Users/leon-an/3Wood/3Wood/Features/Profile/OtherProfileView.swift:38-41, /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:65-67; grep confirms zero minimumScaleFactor/dynamicTypeSize hits in /Users/leon-an/3Wood/3Wood)*
- [medium] RankResultView scales the score badge with scaleEffect(2.2), which overlaps neighbors at large text sizes — The log-flow result screen enlarges the ScoreBadge via .scaleEffect(2.2). scaleEffect does not participate in layout: only the unscaled badge plus 20pt vertical padding is reserved. At default sizes it happens to fit, but at accessibility Dynamic Type the .subheadline badge text roughly doubles, so the 2.2x-scaled capsule (~110pt tall) exceeds its reserved space and visually overlaps the course name above and the '#N of your ...' line below — degrading the payoff moment of the core log/rank flow for large-text users. It also renders the text blurry at 2.2x rasterization. *(Evidence: /Users/leon-an/3Wood/3Wood/Features/Ranking/RankResultView.swift:17-19 (ScoreBadge(score:).scaleEffect(2.2).padding(.vertical, 20)); screenshot /tmp/3wood-review/shots-light/13-Log-Result_0_32145F14-D4A6-4A15-868E-F370214C61F3.png shows the enlarged chip)*
- [low] Decorative images are not hidden from VoiceOver (welcome glyph, feed row icons, chevrons, detail-map snippet) — Several purely decorative or redundant images are exposed to VoiceOver: the 72pt figure.golf hero on Welcome; the feed row's leading flag.checkered/bookmark.fill icon, which duplicates the adjacent 'ranked' / 'wants to play' text; the caption-sized chevron.right affordances in Find Friends, People lists, and Leaderboard (announced as meaningless 'chevron' elements); and the non-interactive map snippet on course detail (allowsHitTesting(false) blocks touches but not VoiceOver focus on the Marker). These add navigation noise for VoiceOver users on every row. *(Evidence: /Users/leon-an/3Wood/3Wood/Features/Auth/WelcomeView.swift:9-11, /Users/leon-an/3Wood/3Wood/Features/Feed/FeedView.swift:65-67, /Users/leon-an/3Wood/3Wood/Features/Profile/FindFriendsView.swift:26-28, /Users/leon-an/3Wood/3Wood/Features/Profile/PeopleListView.swift:88-90, /Users/leon-an/3Wood/3Wood/Features/Feed/LeaderboardView.swift:32-34, /Users/leon-an/3Wood/3Wood/Features/CourseDetail/CourseDetailView.swift:104-113)*

## Gap review: The sign-in / sign-up / username-setup screens themselves — including the missing password-reset path — were never reviewed

**Strengths (keep these):**

- SessionStore's state machine correctly recovers the abandoned-mid-registration case: if the app is killed after auth signUp but before username setup, the next launch's initialSession event runs resolveProfile, finds no profiles row, and lands the user back on UsernameSetupView rather than in a broken half-state (/Users/leon-an/3Wood/3Wood/Features/Auth/SessionStore.swift:19-34, 45-56). Do not restructure this.
- Client-side username validation exactly mirrors the DB check constraint — /[a-z0-9_]{3,20}/ in UsernameSetupView.swift:14 vs '^[a-z0-9_]{3,20}$' in supabase/migrations/00020000000000_profiles.sql:6 — so format rules can never drift into confusing server-only failures.
- Rules are communicated before failure where it matters most: the username footer states '3–20 characters: lowercase letters, numbers, underscores.' upfront (UsernameSetupView.swift:26-28), and sign-up shows 'At least 6 characters.' under the password field (EmailSignInView.swift:32-36).
- Email field ergonomics are correct: .keyboardType(.emailAddress), .textContentType(.emailAddress), autocapitalization off, autocorrect off (EmailSignInView.swift:25-29); and the password contentType correctly switches between .newPassword (sign-up) and .password (sign-in) for proper iOS AutoFill/keychain behavior (line 31).
- Both submit buttons disable during flight and swap to an inline ProgressView, preventing double-submits and giving clear in-progress feedback (EmailSignInView.swift:44-53, UsernameSetupView.swift:36-45).
- The single most likely username failure — name already taken — is rewritten into a friendly, actionable message ('That username is taken — try another.') rather than raw SQL text (UsernameSetupView.swift:60-62); the mechanism should be hardened (error code, not substring), but the user-facing copy is right.
- The Welcome screen (/tmp/3wood-review/shots-light/00-Welcome.png) presents a clean, low-friction entry: one prominent 'Create account' CTA with 'Sign in' as a clearly secondary plain button, matching first-run priorities — the hierarchy is correct even though its aesthetics were reviewed separately.


### [HIGH] No forgot-password or reset flow anywhere — a forgotten password is a permanent lockout

There is no password-recovery entry point in the app. A grep for 'forgot|reset' across /Users/leon-an/3Wood/3Wood/**/*.swift returns zero hits, and EmailSignInView's sign-in form (the only place credentials are entered) has no link or button besides submit. Supabase supports resetPasswordForEmail plus a deep-link recovery flow, but none of it is wired up. Since email/password is the only auth method (Sign in with Apple is still a TODO comment in WelcomeView.swift:18-19), a user who forgets their password has no recourse at all: no in-app reset, no support email surfaced, nothing. Their played-course history, rankings, and follows are all stranded behind the lockout — directly against the app's core promise of being the durable record of every course you've played.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:22-57 (entire sign-in form; no recovery affordance); grep -rniE 'forgot|reset' over the app source returns nothing; /Users/leon-an/3Wood/3Wood/Features/Auth/WelcomeView.swift:18-28 shows email/password is the sole auth path.

**Recommendation:** Add a 'Forgot password?' button in sign-in mode that calls supa.auth.resetPasswordForEmail(email), plus a confirmation state ('Check your email'). Handle the recovery deep link (auth.session(from:) / .passwordRecovery event in SessionStore) with a simple new-password screen. This should land before hosted Supabase / TestFlight, since real users forget passwords immediately.

**Verifier:** Verified directly. /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:22-57 shows the sign-in form contains only email/password fields, an error section, and a submit button — no recovery link. A grep for 'forgot|reset|recover' across all .swift files in the app returns zero hits. WelcomeView.swift:18-28 confirms email/password is the sole auth method (Sign in with Apple is only a comment about a future milestone), and no support email is surfaced anywhere. Since the app's core promise is being the durable record of every course played, a forgotten password stranding all data justifies high severity for a pre-TestFlight release.


### [MEDIUM] Raw Supabase error strings shown verbatim to users on sign-in/sign-up failure

EmailSignInView.swift:72 assigns error.localizedDescription straight to the UI. In practice Supabase auth errors read as server-generated English strings: wrong password or unknown email both produce 'Invalid login credentials' (no hint whether the email or password is wrong, and no nudge toward 'Create account'); signing up with an existing email yields 'User already registered' with no link to switch to sign-in; rate limiting yields strings like 'For security purposes, you can only request this after N seconds.' or 'Email rate limit exceeded'. Network failures surface as verbose URLError text. These are un-localized, jargon-y, and give no next action — the exact moments (typo'd password, duplicate account) where users most need guidance.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:71-73 (catch { errorMessage = error.localizedDescription }); the same raw-fallback pattern in /Users/leon-an/3Wood/3Wood/Features/Auth/UsernameSetupView.swift:59-63.

**Recommendation:** Map known cases: AuthError with invalid-credentials → 'Email or password doesn't match. Check for typos or reset your password.'; user-already-exists on sign-up → 'You already have an account — sign in instead' with a direct link; rate limit → 'Too many attempts, wait a moment'; URLError → 'Couldn't reach the server — check your connection.' Fall back to a generic 'Something went wrong' rather than the raw string.

**Verifier:** Verified directly. EmailSignInView.swift:71-73 is exactly 'catch { errorMessage = error.localizedDescription }' with no mapping of any error case, and UsernameSetupView.swift:58-63 uses the same raw fallback for anything that isn't the duplicate-username case. Users hitting the most common failures (typo'd password, duplicate email, network error) get un-localized server jargon with no next action. Medium is correct: a clear UX improvement, but the errors are at least displayed and roughly comprehensible.


### [MEDIUM] No escape hatch from UsernameSetupView — wrong-account or persistent-failure users are trapped

UsernameSetupView is presented full-screen whenever state == .needsProfile and offers exactly one action: pick a username and submit. There is no sign-out, cancel, or back affordance anywhere in its body (lines 17-49), and it shows no indication of which email/account you're setting up. A user who signed up with a typo'd email, wants to switch to a different account, or hits a persistent server error on ProfileRepo.create has no way back to Welcome short of deleting the app. (The happy interrupted path is fine: killing the app mid-setup correctly returns here via SessionStore.resolveProfile → .needsProfile — but that same persistence is what makes the trap sticky.)

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/UsernameSetupView.swift:17-49 (Form contains only the username field, error section, and submit button; no toolbar/sign-out); /Users/leon-an/3Wood/3Wood/Features/Auth/SessionStore.swift:45-56 (resolveProfile re-lands the user here on every launch until a profile row exists).

**Recommendation:** Add a toolbar 'Sign out' (or 'Use a different account') button calling session.signOut(), and show the signed-in email ('Setting up for leon@…') so users can confirm they're on the right account before naming it.

**Verifier:** Verified directly. RootView.swift:14-16 renders UsernameSetupView as the entire UI whenever state == .needsProfile; the view body (UsernameSetupView.swift:17-49) offers only the username field, an error section, and the submit button — no toolbar, no sign-out, no cancel, and no display of the signed-in email. SessionStore.swift:45-56 re-lands the user in .needsProfile on every launch until a profile row exists, so the state persists. SessionStore.signOut() exists at line 41 but nothing in this view invokes it. A user who signed up with a typo'd email or wants a different account genuinely has no in-app way back to Welcome. Medium is the right severity: real but affects an edge slice of onboarding users, and the fix is a one-button toolbar addition.


### [MEDIUM] Sign-in submit silently disabled below 6 characters, and no email-format validation in either mode

The only gating is .disabled(isSubmitting || email.isEmpty || password.count < 6) at EmailSignInView.swift:53. Two problems: (a) the 'At least 6 characters.' footer is shown only in sign-up mode (lines 33-35), yet sign-in applies the same 6-char gate — a user who mistypes a short password on sign-in stares at a dead button with zero explanation; (b) email is only checked for isEmpty, so 'leon@gmail' or 'leon gmail.com' passes to the server and comes back as a raw error, and on sign-up a typo'd email creates an account the user can never recover (compounding the missing reset flow). There is no inline validation feedback on either field.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:32-36 (footer only when mode == .signUp) and :53 (shared disabled predicate; only email.isEmpty checked).

**Recommendation:** For sign-in, drop the 6-char gate (only require non-empty) and let the server reject — or show the reason inline. Validate basic email shape (contains '@' and a dot after it) with a gentle inline hint on sign-up, where a typo is costly. Prefer visible inline validation over silently disabled buttons.

**Verifier:** Verified against /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift. Line 53 is exactly `.disabled(isSubmitting || email.isEmpty || password.count < 6)` and the 'At least 6 characters.' footer at lines 32-36 is gated on `mode == .signUp`, so sign-in users hitting the 6-char gate get a dead button with no explanation. Email is only checked for isEmpty; submit() (lines 59-74) sends the raw string to Supabase and shows error.localizedDescription verbatim. Minor mitigation: real passwords are always ≥6 chars, so the sign-in gate only fires on mistypes — but then with zero feedback. The signup-typo'd-email case is genuinely costly because the app has no password-reset path at all. Medium severity stands.


### [LOW] Duplicate-username detection relies on fragile substring matching of the error description

UsernameSetupView.swift:60 decides whether to show 'That username is taken' by checking text.contains("duplicate") || text.contains("unique") on error.localizedDescription. This currently works because Postgres emits 'duplicate key value violates unique constraint "profiles_username_key"', but it is case-sensitive English string matching against a message the app doesn't control — a Supabase/PostgREST message change, wrapping, or capitalization ('Duplicate') breaks it, and then the user sees the raw constraint-violation SQL text instead. The structured error is available: PostgrestError carries the SQLSTATE code, and 23505 is the stable unique-violation code.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/UsernameSetupView.swift:59-63; the unique constraint it depends on is /Users/leon-an/3Wood/supabase/migrations/00020000000000_profiles.sql:6 (username text unique not null check ...).

**Recommendation:** Catch PostgrestError specifically and check error.code == "23505" for the taken-username message; keep a generic friendly fallback for everything else. Even better, add a live availability check (debounced select on profiles) so the user learns before tapping submit.

**Verifier:** Verified directly. UsernameSetupView.swift:60 does case-sensitive text.contains("duplicate") || text.contains("unique") on error.localizedDescription, and the constraint it depends on is /Users/leon-an/3Wood/supabase/migrations/00020000000000_profiles.sql:6 (username text unique not null). The fragility claim is technically accurate and checking SQLSTATE 23505 on PostgrestError would be strictly better. But severity is overstated: the check works correctly today against Postgres's stable 'duplicate key value violates unique constraint' message, and the failure mode if it ever breaks is an ugly-but-visible error string, not a lockout or silent failure. This is robustness polish — low, not medium.


### [LOW] Return key does nothing: no submitLabel or onSubmit chaining on the credential fields

Neither field in EmailSignInView has .submitLabel or .onSubmit. Standard iOS ergonomics would be email → return ('next') focuses password → return ('go') submits. As implemented, tapping return on the password field just dismisses the keyboard and the user must find the button in the Form. Same in UsernameSetupView: the username field (lines 21-23) has no submitLabel/onSubmit, so return doesn't trigger 'Let's golf'. Minor per-tap, but this is the very first interaction every user has with the app.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:25-31 (TextField/SecureField modifiers: keyboardType, textContentType, autocapitalization only); /Users/leon-an/3Wood/3Wood/Features/Auth/UsernameSetupView.swift:21-23.

**Recommendation:** Add @FocusState; email field .submitLabel(.next) with .onSubmit { focus = .password }; password .submitLabel(.go) with .onSubmit { Task { await submit() } } (guarded by the same validity check); username field .submitLabel(.go) likewise.

**Verifier:** Verified: EmailSignInView.swift lines 25-31 show only keyboardType/textContentType/autocapitalization/autocorrection modifiers — no .submitLabel, .onSubmit, or @FocusState anywhere in the file; same for UsernameSetupView.swift lines 21-23. The claim is accurate. However, severity is overstated: the submit button sits directly in the same short Form, the cost is one extra tap, and the finding itself calls it 'minor per-tap'. This is keyboard-ergonomics polish, so downgraded from medium to low.


### [LOW] No in-form switch between sign-in and sign-up; wrong-door users must back out to Welcome

Mode is a fixed let on EmailSignInView (line 16) chosen by which Welcome NavigationLink was tapped (WelcomeView.swift:20-29). A returning user who taps 'Create account' by habit gets the raw 'User already registered' error and has to figure out they should pop back and take the other link; there is no 'Already have an account? Sign in' (or inverse) affordance inside the form. Combined with the raw-error finding, the duplicate-email moment is a genuine dead end for the least technical users.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:16 (let mode: Mode; no toggle in body lines 22-57); /Users/leon-an/3Wood/3Wood/Features/Auth/WelcomeView.swift:20-29.

**Recommendation:** Add a small footer button that flips the mode in place (make mode @State seeded by an initial value), preserving the typed email. At minimum, map the user-exists error to a message containing a tappable 'Sign in instead'.

**Verifier:** Verified: EmailSignInView.swift line 16 is `let mode: Mode` (immutable, no @State toggle anywhere in the body, lines 22-57), and WelcomeView.swift lines 20-29 show the two separate NavigationLinks that hard-select the mode. Line 72 surfaces raw error.localizedDescription, so a duplicate-email attempt shows Supabase's raw 'User already registered' wording with no in-form escape hatch. Real finding. 'Dead end' is slightly overstated — Welcome is a single back-navigation away — so the original low severity is correct.


### [LOW] Username field doesn't auto-lowercase or trim; invalid input just silently disables the button

isValid is a strict wholeMatch of /[a-z0-9_]{3,20}/ (UsernameSetupView.swift:13-15). Autocapitalization is off, but a user can still shift-type 'LeonAn', paste 'Leon An', or leave a trailing space — and the 'Let's golf' button simply stays disabled with no indication of which rule failed. The footer (line 27) does state the rules upfront, which is good, but there's no live feedback connecting the current input to the disabled state, and obvious auto-fixes (lowercasing, trimming whitespace) aren't applied.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/UsernameSetupView.swift:13-15 (regex), :21-27 (field + footer), :45 (.disabled(isSubmitting || !isValid)).

**Recommendation:** Normalize input in onChange (lowercase, strip whitespace) so 'LeonAn' becomes 'leonan' instead of an error, and show a live inline hint (e.g. 'Only lowercase letters, numbers, and _' turning red) when the remaining rules fail.

**Verifier:** Verified: UsernameSetupView.swift lines 13-15 use a strict `wholeMatch(of: /[a-z0-9_]{3,20}/)`, line 45 disables the button on !isValid, and there is no onChange normalization (lowercasing/trimming) or live inline hint in the file. Autocapitalization is off (line 22) but manual shift, pasted 'Leon An', or a trailing space all silently disable 'Let's golf'. The finding fairly credits the upfront rules footer at line 27. Real; low severity is right for this onboarding polish item.


### [LOW] No reserved-username list — 'admin', 'support', '3wood' etc. are claimable

The only DB-side rules are the regex check and uniqueness (migrations/00020000000000_profiles.sql:6), and the client mirrors just the regex. Nothing prevents a user from registering 'admin', 'support', 'help', '3wood', or 'moderator', which matters once there's a public leaderboard and profile search (usernames are surfaced app-wide via the leaderboard/search RPCs in migrations 00060/00080/00100). Pre-App-Store is the cheap time to reserve these; retrofitting after someone claims 'admin' is awkward.

**Evidence:** /Users/leon-an/3Wood/supabase/migrations/00020000000000_profiles.sql:6 (check (username ~ '^[a-z0-9_]{3,20}$') and unique — no denylist); /Users/leon-an/3Wood/3Wood/Features/Auth/UsernameSetupView.swift:13-15 (client mirrors only the regex).

**Recommendation:** Add a small denylist (admin, administrator, support, help, mod, moderator, root, 3wood, official) enforced in the DB check or a before-insert trigger, mirrored client-side with a friendly 'That name is reserved' message.

**Verifier:** Verified. /Users/leon-an/3Wood/supabase/migrations/00020000000000_profiles.sql:6 contains only `unique not null check (username ~ '^[a-z0-9_]{3,20}$')` — no denylist and no before-insert trigger anywhere in the migrations. The client (UsernameSetupView.swift:13-15) validates only the same regex via wholeMatch. The exposure claim also checks out: grep confirms usernames are surfaced by the RPCs in migrations 00060 (follows), 00080 (qol/search), and 00100 (feed/leaderboard). Nothing stops a user from registering 'admin', 'support', or '3wood', all of which match the regex. Severity low is correct: it is a real but cheap-to-fix pre-launch hygiene issue with no immediate user harm.


### [LOW] .newPassword content type without passwordRules, and no show-password or confirm affordance

The sign-up SecureField uses .textContentType(.newPassword) (EmailSignInView.swift:31) — correct for AutoFill — but no UITextInputPasswordRules/.passwordRules descriptor, so iOS's suggested strong passwords don't formally know the 6-char minimum (fine today, breaks if rules tighten). There's also no reveal-password eye toggle and no confirm field; combined with the missing reset flow, a single unnoticed typo at sign-up produces an account whose password the user never actually knew.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Auth/EmailSignInView.swift:30-31 (SecureField with only textContentType; no passwordRules, no reveal toggle anywhere in body 22-57).

**Recommendation:** Add a show/hide toggle on the sign-up password field (cheaper and friendlier than a confirm field) and a passwordRules descriptor ('minlength: 6;'). This becomes lower priority once password reset exists, but one of the two mitigations should ship.

**Verifier:** Verified. EmailSignInView.swift:30-31 shows a SecureField with only `.textContentType(mode == .signUp ? .newPassword : .password)`; the entire body (lines 22-57) has no reveal toggle, no confirm field, and no passwordRules descriptor. I also confirmed the contextual claim: grep for reset/forgot/passwordRules across Features/Auth/ and Core/ returns nothing, and the Auth folder contains only EmailSignInView, SessionStore, UsernameSetupView, WelcomeView — there is genuinely no password-reset path, so a sign-up typo has no recovery route today. Minor caveat: SwiftUI's SecureField has no native .passwordRules modifier (it requires a UIKit-bridged UITextField), so that half of the recommendation is more work than implied; the show/hide toggle is the practical fix. Severity low is right — the user-hurting core issue (no reset flow) is a separate finding; this one is a supporting mitigation/polish item.


## Gap review: App Store submission readiness: privacy manifest, in-app privacy policy, export-compliance key, and metadata surface were never audited

**Strengths (keep these):**

- Account deletion is fully implemented in-app (ProfileView.swift calling the delete_account RPC, backed by supabase/migrations/00070000000000_delete_account.sql) — satisfies Guideline 5.1.1(v), the most commonly missed requirement for account-based apps.
- ODbL attribution for course data is done correctly and visibly: AboutView.swift:20-30 credits OpenGolfAPI contributors, names the license, and links both the source and the ODbL 1.0 text (confirmed in 09-About_0_4C1BB725-B7A2-4479-9707-426FF115D647.png). Do not change this.
- Version string on the About screen is read dynamically from the bundle (AboutView.swift:4-8, CFBundleShortVersionString + CFBundleVersion), so it can never drift from the archive — matches MARKETING_VERSION 1.0 / CURRENT_PROJECT_VERSION 1 in project.pbxproj (lines 434/445), which are sane for a first submission, as is the bundle identifier com.leonan.threewood (line 446).
- The location purpose string is present, specific, and honest: INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = '3Wood uses your location to show golf courses near you.' (project.pbxproj:405/433) — exactly the kind of concrete phrasing App Review wants.
- First-party code uses zero required-reason APIs (no direct UserDefaults, file timestamps, disk-space, or uptime calls anywhere in 3Wood/), keeping the eventual privacy-manifest surface minimal and delegating session storage to supabase-swift 2.52.0, which ships its own compliant manifests.
- Auth is a first-party email/password account system only (Features/Auth/ contains no third-party OAuth), so Sign in with Apple is not required for v1 under Guideline 4.8 — and WelcomeView.swift:18-19 already documents the plan to add it when the Developer account exists.
- Supabase access is centralized in a single Supa.swift entry point with repositories layered on top, so the one hardcoded-URL fix (the high-severity finding) is a one-file change rather than a scattered refactor.


### [HIGH] Release build ships pointed at localhost Supabase with demo credentials

The Supabase connection is hardcoded to the local CLI dev stack: /Users/leon-an/3Wood/3Wood/Core/Supa.swift lines 11-12 set supabaseURL = http://127.0.0.1:54321 and the anon key is the well-known 'supabase-demo' JWT. The comment (lines 7-9) admits 'swap in the hosted project's values before' shipping, but there is no build-configuration mechanism — a Release archive today produces an app that cannot load any data for App Review (Guideline 2.1 App Completeness rejection is near-certain). The plaintext-HTTP URL only works because ATS exempts loopback; there is no ATS exception in project.pbxproj, so any non-HTTPS hosted URL would also fail silently.

**Evidence:** /Users/leon-an/3Wood/3Wood/Core/Supa.swift:11-12 — `static let supabaseURL = URL(string: "http://127.0.0.1:54321")!` and the demo anon key; grep of project.pbxproj shows no NSAppTransportSecurity override.

**Recommendation:** Before archiving, inject the hosted Supabase HTTPS URL and anon key per build configuration (xcconfig values surfaced via INFOPLIST_KEY_* or a Debug/Release #if in Supa.swift). Shipping the anon key in the binary is fine (it is public by design), but the localhost URL must be impossible in a Release build — consider a compile-time assert or fatalError if the URL host is 127.0.0.1 in non-DEBUG builds.

**Verifier:** Verified by reading /Users/leon-an/3Wood/3Wood/Core/Supa.swift: lines 11-12 hardcode http://127.0.0.1:54321 and the well-known supabase-demo anon JWT, and the shared client (lines 16-19) uses them unconditionally — no #if DEBUG, no xcconfig indirection. Grep of 3Wood.xcodeproj/project.pbxproj confirms no NSAppTransportSecurity override and no per-configuration URL mechanism. A Release archive today produces an app with no reachable backend, a near-certain Guideline 2.1 rejection. This is the known 'next = hosted Supabase' work item, but for submission readiness it is the single biggest blocker. High is correct.


### [HIGH] No report, flag, or block mechanism for user-generated content (Guideline 1.2)

3Wood is a social app with UGC: free-text reviews (20-Reviews/21-WriteReview screens, supabase/migrations/00110000000000_reviews.sql), user-chosen usernames, follows, and an activity feed. Apple's Guideline 1.2 requires UGC apps to provide: a way to report offensive content, a way to block abusive users, a content filter, and published contact info. None exist: grep -rniE 'report|block|flag' over 3Wood/ matches only SF Symbol names (FeedView.swift:65 'flag.checkered', CourseMapView.swift:183 'flag', CourseDetailView.swift:26 'flag'), and the migrations directory has no reports/blocks tables (only an RLS comment in 00030000000000_courses.sql:2). Social apps with reviews and profiles are a category Apple reviews strictly; rejection risk is high.

**Evidence:** grep over /Users/leon-an/3Wood/3Wood/ and /Users/leon-an/3Wood/supabase/migrations/ (all 11 migration files listed; no report/block schema). Screenshots 20-Reviews_* and 08-OtherProfile_* in /tmp/3wood-review/shots-light show reviews and other-user profiles with no report/block affordance.

**Recommendation:** Minimum viable 1.2 compliance: (a) 'Report review' action on each review row and 'Report / Block user' on other-user profiles (context menu fits the minimalist Refined Classic style), (b) a reports table + blocked_users table in Supabase with RLS so blocked users' content is filtered client- or query-side, (c) commit to acting on reports within 24 hours, (d) EULA/terms stating no tolerance for objectionable content (ties into the missing-terms finding).

**Verifier:** Re-ran the grep myself: the only report/block/flag matches in 3Wood/ are SF Symbol names (FeedView.swift:65 'flag.checkered', CourseMapView.swift:183 'flag', CourseDetailView.swift:26 'flag'), and the 11 migrations in supabase/migrations/ contain no reports or blocked_users tables (only an unrelated RLS comment in 00030000000000_courses.sql:2, which is about read-only course data). Screenshots 20-Reviews_0_D85BDFDA-A175-48D1-9AE7-6B1F71890316.png (other users' free-text reviews, only an 'Edit' affordance for one's own) and 08-OtherProfile_0_50D39496-6602-4E1A-AC60-D7B31871E7D1.png (other-user profile with only a Following toggle) confirm no report/block UI exists. Apple enforces 1.2 strictly for social apps with free-text UGC and profiles; high severity stands.


### [HIGH] No privacy policy or terms link anywhere in the app (Guideline 5.1.1)

The app collects email addresses (email/password auth), usernames, follows, location (near-me map), and review text, but exposes no privacy policy or terms of service. grep -rniE 'privacy|terms' over 3Wood/ returns no UI hits. The natural home, AboutView (/Users/leon-an/3Wood/3Wood/Features/Profile/AboutView.swift, full file read: lines 10-38), contains only Version, Course data attribution, and an open-source link — confirmed visually in the About screenshot. Guideline 5.1.1(i) requires a privacy policy link in the app itself (and in App Store Connect metadata) for any app that collects user data; account-based apps without one are routinely rejected.

**Evidence:** /Users/leon-an/3Wood/3Wood/Features/Profile/AboutView.swift:10-38 (sections: Version, Course data, Open source — nothing else); screenshot /tmp/3wood-review/shots-light/09-About_0_4C1BB725-B7A2-4479-9707-426FF115D647.png shows the same three sections and no legal links.

**Recommendation:** Host a privacy policy and terms of service (a simple static page suffices), then add a 'Legal' section to AboutView with two Link rows, matching the existing Link style used for OpenGolfAPI/ODbL. Also add the privacy policy URL to the App Store Connect app record and to the WelcomeView sign-up flow ('By continuing you agree to...').

**Verifier:** Verified: AboutView.swift (read in full, 44 lines) contains only Version, Course data (OpenGolfAPI/ODbL links), and Open source (supabase-swift) sections; repo-wide grep for privacy|terms returns no app-code hits; screenshot 09-About_0_4C1BB725-B7A2-4479-9707-426FF115D647.png visually matches — three sections, no legal links. The app collects email (email/password auth), when-in-use location (INFOPLIST_KEY_NSLocationWhenInUseUsageDescription in pbxproj), usernames, follows, and review text. App Store Connect requires a privacy policy URL to submit at all, and 5.1.1(i) requires an in-app link for account-based apps. High is correct — this blocks submission outright.


### [MEDIUM] No support contact anywhere in the app

grep -rni 'mailto|support|contact|feedback' over 3Wood/ finds only a comment in Core/DesignSystem/Colors.swift:7. The About screen (its natural home) has no support email or link. Guideline 1.2 explicitly requires UGC apps to publish contact information so users can reach the developer, and App Store Connect requires a support URL; having it in-app avoids reviewer friction and is expected for an account-based social app.

**Evidence:** Repo-wide grep (only Colors.swift:7 comment matches); /tmp/3wood-review/shots-light/09-About_0_4C1BB725-B7A2-4479-9707-426FF115D647.png shows About with no contact row; AboutView.swift:10-38 confirms in source.

**Recommendation:** Add a 'Support' section to AboutView with a mailto: link (e.g., a dedicated support address rather than a personal one) and/or a support URL, and use the same URL in the App Store Connect support-URL field.

**Verifier:** Verified: repo-wide grep for mailto/support/contact/feedback matches only a comment in Core/DesignSystem/Colors.swift:7 (plus the Righteous font OFL text, not app UI). AboutView.swift:10-38 contains only Version, Course data, and Open source sections, and the screenshot 09-About_0_4C1BB725-B7A2-4479-9707-426FF115D647.png confirms no contact row. 3Wood hosts user-generated content (reviews), and Guideline 1.2 requires UGC apps to publish contact information users can reach; this is a genuine App Review friction/rejection vector for a pre-submission UGC app, and the fix is trivial. Medium is correctly calibrated.


### [LOW] ITSAppUsesNonExemptEncryption not set in project.pbxproj

grep of /Users/leon-an/3Wood/3Wood.xcodeproj/project.pbxproj confirms no ITSAppUsesNonExemptEncryption key in any configuration (the INFOPLIST_KEY_ block at lines 405-412 / 433-440 contains only location usage, scene manifest, launch screen, and orientation keys; GENERATE_INFOPLIST_FILE = YES at line 408 means there is no separate Info.plist to hold it). The app only uses HTTPS/standard encryption via supabase-swift, so the exemption applies, but without the key every TestFlight and App Store upload will stall on the export-compliance questionnaire in App Store Connect.

**Evidence:** project.pbxproj lines 405-412 (Debug) and 433-440 (Release): INFOPLIST_KEY_* entries with no ITSAppUsesNonExemptEncryption; repo-wide grep returns zero hits.

**Recommendation:** Add INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO to both the Debug and Release build configurations of the app target.

**Verifier:** Factually confirmed: read pbxproj lines ~400-445 — both Debug and Release buildSettings contain only location-usage, scene-manifest, launch-screen, and orientation INFOPLIST_KEY_* entries with GENERATE_INFOPLIST_FILE = YES (so no separate Info.plist could hold the key), and a repo-wide grep for ITSAppUsesNonExemptEncryption returns zero hits. However, medium overstates the impact: the missing key never causes a rejection — it only prompts a one-click export-compliance questionnaire per uploaded build in App Store Connect, and can alternatively be answered once via the ASC app-record encryption declaration. The app's HTTPS-only usage plainly qualifies for the exemption. One-line fix, workflow friction only; downgraded to low.


### [LOW] No app-level PrivacyInfo.xcprivacy privacy manifest

find over the repo shows no .xcprivacy file. Mitigating facts I verified: first-party code uses zero required-reason APIs (grep for UserDefaults, @AppStorage, file creation/modification dates, volumeAvailableCapacity, systemUptime/ProcessInfo across 3Wood/ returns no hits — session persistence is delegated to the SDK), and supabase-swift 2.52.0 (Package.resolved) ships its own per-module privacy manifests covering its UserDefaults use (Auth session storage, reason CA92.1), which Xcode aggregates at archive time. So this is unlikely to trigger an ITMS-91053 upload rejection today. However, an app-level manifest is still expected for a data-collecting app and future-proofs against Apple tightening enforcement.

**Evidence:** `find /Users/leon-an/3Wood -name "*.xcprivacy"` returns nothing; /Users/leon-an/3Wood/3Wood.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved pins supabase-swift 2.52.0; grep for required-reason APIs over 3Wood/ returns zero Swift hits.

**Recommendation:** Add 3Wood/PrivacyInfo.xcprivacy to the app target declaring: NSPrivacyTracking = false; NSPrivacyTrackingDomains = []; NSPrivacyAccessedAPITypes = [] (none used first-party); NSPrivacyCollectedDataTypes: Email Address, User ID, Other User Content (reviews/rankings), Coarse Location — each linked-to-identity = true (except location), tracking = false, purpose = App Functionality. Keep it in sync with the App Store Connect privacy nutrition label answers.

**Verifier:** Verified: `find /Users/leon-an/3Wood -name '*.xcprivacy'` returns nothing; Package.resolved pins supabase-swift 2.52.0; my own grep for required-reason APIs (UserDefaults, @AppStorage, creationDate/modificationDate, volumeAvailable*, systemUptime, ProcessInfo) over all first-party Swift exits with no matches. So the finding is factually accurate — but by its own verified mitigations it will NOT trigger an ITMS-91053 rejection: no first-party required-reason API use, the SDK ships its own per-module manifests, and supabase-swift is not on Apple's 'commonly used SDKs' list requiring signatures. The mandatory privacy disclosure at submission time is the App Store Connect nutrition-label questionnaire, not an app-level manifest. Adding one is good future-proofing hygiene, i.e. polish. Downgrade medium -> low.


### [LOW] iPhone-only portrait choice: verify iPad letterbox behavior before submission

TARGETED_DEVICE_FAMILY = 1 with UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait (project.pbxproj lines 412, 423 Debug / 440, 451 Release) is a legitimate choice and not itself a defect. The residual review risk is small but real: App Review frequently tests iPhone-only apps in iPad compatibility mode, and the app must run (letterboxed) without crashing there — the MapKit near-me flow and location permission prompt are the screens most worth a smoke test. Given the hardcoded-localhost finding, an iPad compatibility run has likely never been done against real data.

**Evidence:** /Users/leon-an/3Wood/3Wood.xcodeproj/project.pbxproj:412 (UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait), :423/:451 (TARGETED_DEVICE_FAMILY = 1).

**Recommendation:** Before submitting, run the app once on an iPad simulator in iPhone-compatibility mode against the hosted backend and confirm launch, sign-in, map/location, and review flows work. No code change expected.

**Verifier:** Verified in /Users/leon-an/3Wood/3Wood.xcodeproj/project.pbxproj (~lines 405-455): both Debug and Release configs set TARGETED_DEVICE_FAMILY = 1 and INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait, matching the citation. The finding correctly frames this as a legitimate choice, not a defect — the only ask is a one-time smoke test on an iPad in iPhone-compatibility mode, since App Review does test there and SwiftUI/MapKit apps essentially always work letterboxed. No code change expected. Low is the right severity; this is a pre-flight checklist item, not a likely failure.


## Coverage gaps the critic identified (and dispatched reviewers for)

- **Accessibility: VoiceOver labels and Dynamic Type are completely unreviewed (and nearly absent from the code)** — The color-theme dimension covered contrast only. No finding touches VoiceOver, Dynamic Type, or tap-target size. A pre-check shows the entire codebase contains exactly ONE accessibility annotation (`/Users/leon-an/3Wood/3Wood/Core/DesignSystem/Wordmark.swift:31` — .accessibilityLabel("3Wood")) and zero uses of dynamicTypeSize/minimumScaleFactor. Several confirmed findings already note icon-only, u...

- **The sign-in / sign-up / username-setup screens themselves — including the missing password-reset path — were never reviewed** — Only the signed-out Welcome screen (00-Welcome) was captured; the actual EmailSignInView form and UsernameSetupView have zero screenshot coverage and zero findings in any dimension beyond the hosted-Supabase email-confirmation dead-end. A pre-check of /Users/leon-an/3Wood/3Wood/Features/Auth/ shows grep for 'forgot|reset' returns nothing — there is no password-recovery path at all, so any user who...

- **App Store submission readiness: privacy manifest, in-app privacy policy, export-compliance key, and metadata surface were never audited** — The product is explicitly 'feature-complete v1, pre-App-Store', yet no dimension reviewed submission blockers. Pre-checks: there is NO PrivacyInfo.xcprivacy anywhere in the repo (required since May 2024 when using required-reason APIs, and reviewers now flag its absence), no ITSAppUsesNonExemptEncryption key in the pbxproj (every TestFlight/App Store upload will stall on the export-compliance ques...
