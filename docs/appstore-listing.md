# 3Wood — App Store listing copy

Working copy for App Store Connect. Character limits noted per field.

## Name (30 chars max)
```
3Wood: Social Golf Rankings
```
(27 chars)

## Subtitle (30 chars max)
```
Golf is meant to be shared.
```
(27 chars — doubles as the brand slogan)

Alternates considered: "Share your golf adventures" (26), "Rank courses. Rally friends." (28), "Your rounds, your rankings" (26).

## Promotional text (170 chars max, editable without review)
```
Rank every course you play, tag your playing partners, react to your friends' rounds, and settle the "best track in town" debate with receipts.
```
(143 chars)

## Description (4000 chars max) — rewritten 2026-08-05
The previous version described a July build: it never mentioned photos,
reactions, comments, tagging playing partners, alerts or round history, which
are now most of what makes the app social.
```
Golf is meant to be shared — and 3Wood is where your rounds live.

3Wood is a social course-ranking app for golfers. Instead of shouting star ratings into the void, you build a personal 0–10 ranking of every course you've played, follow your friends, and see the game through your crew's eyes.

RANK, DON'T RATE
Logging a course takes seconds. Say whether you liked it, thought it was fine, or didn't love it, then answer a few quick head-to-head matchups against courses you've already played. 3Wood turns those choices into a personal 0–10 score for every course — no agonizing over whether something is "4 stars."

PLAYED IT WITH THE CREW
Tag the friends you played with as you log the round. Your list stays yours, but the round is shared.

A FEED THAT TALKS BACK
Your home feed shows the courses your friends play, save, and love — and you can actually respond. React with a golf-native set (a flag for a great track, an eagle for the shot of the day, a skull for a blow-up round), leave a comment, and @mention whoever needs to see it. Alerts keep you on top of new followers, reactions, and replies.

EVERY COURSE, EVERYONE'S TAKE
Open any of 16,000+ US courses to see the community rating, your friends' individual scores side by side, written reviews from people you actually know, and photos from the golfers who've played it.

KEEP THE RECEIPTS
Every round is dated. Check in again each time you play a course, and watch your week-by-week streak build as you keep adding new tracks.

FIND YOUR FOURSOME
Match your contacts to find friends already on 3Wood, invite the rest with your personal link, and climb the weekly and all-time leaderboards.

PLAN THE NEXT ONE
Search by name or city, explore the map, and keep a Want-to-Play list so the next buddies trip plans itself.

Whether you're chasing the top 100 or just arguing about the best muni in town, 3Wood keeps score.

Course data © OpenGolfAPI contributors (ODbL).
Privacy policy: https://leon1224an-droid.github.io/3Wood/privacy.html
Terms: https://leon1224an-droid.github.io/3Wood/terms.html
```
(2061 chars)

## Keywords (100 chars max, comma-separated, no spaces)
```
golf,course,rankings,tracker,social,friends,rounds,tee,scorecard,rate,leaderboard,map,photos
```
(92 chars. "beli" was removed — it is a competitor's app name, and
third-party trademarks in metadata are a well-known rejection reason.)

## Category
- Primary: Sports
- Secondary: Social Networking

## App Privacy questionnaire — answer key
For each row: "Yes, we collect this data" → Linked to the user → purpose
**App Functionality** → NOT used for tracking.

| Category | Item |
|---|---|
| Contact Info | Email Address |
| Contact Info | Phone Number (optional, friend matching) |
| Contact Info | Name |
| User Content | **Photos or Videos** (course photos) |
| User Content | Other User Content (reviews, comments, rankings) |
| Identifiers | User ID |

Answer **No** to everything else. The two that look wrong but aren't:
- **Contacts → No.** Names never leave the device; only phone numbers are sent
  for matching, and they are not stored.
- **Location → No.** Used on-device to centre the map; never sent to the backend.

No tracking, no ads, no data sold, no data broker.

## Age rating questionnaire — answer key
Everything **None** except:
- **User Generated Content → Yes** (photos, reviews, comments).
- When asked about moderation: yes — report and block on all three, plus
  server-side filtering of blocked users' content.
- Unrestricted Web Access → No.

Expect **12+**, not 4+. Apple raises the rating for any UGC app regardless of
moderation quality. Listing copy must not claim it suits all ages.

## Detail behind the answers
- Contact Info → Email Address: collected, linked to identity (account).
- Contact Info → Phone Number: optional, linked, used for app functionality
  (friend matching). Numbers from the user's address book are transmitted for
  matching but NOT stored (only the user's own linked number is stored).
- Contacts: accessed on-device with permission; names never leave the device.
- User Content: reviews, rankings (linked to identity).
- Identifiers: User ID (linked).
- No tracking, no ads, no data sold.

## Screenshots (6.9" required set) — CURRENT as of 2026-08-05
`docs/appstore/screenshots/`, 1320×2868, captured on iPhone 17 Pro Max from the
four-tab build: 1-feed (reactions visible), 2-score-reveal, 3-course-detail,
4-explore-map (Pebble Beach with score pins), 5-my-courses, 6-comments.

Recipe, if they need recapturing after a UI change:
```
UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID"
xcrun simctl status_bar "$UDID" override --time "9:41" --cellularMode active \
  --cellularBars 4 --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl privacy "$UDID" grant contacts com.leonan.threewood
xcrun simctl privacy "$UDID" grant location-always com.leonan.threewood
xcrun simctl location "$UDID" set 36.5725,-121.9486
xcodebuild -project 3Wood.xcodeproj -scheme 3Wood -destination "id=$UDID" \
  -resultBundlePath /tmp/store.xcresult test
xcrun xcresulttool export attachments --path /tmp/store.xcresult --output-path /tmp/shots
```
Only ONE simulator may be booted during the run — a second booted device makes
most of the suite fail for no code reason.

## Review notes (for App Review)
- Demo account (hosted): `3woodapp+review@gmail.com`, username **@demo_golfer**.
  Seeded 2026-08-02 and verified signing in: Pebble Beach 9.2, Spyglass Hill
  7.5, Torrey Pines North 5.0, Bethpage bookmarked, one review on Pebble.
  **The password is not recorded here — this repo is public.** It goes in App
  Store Connect, in two separate places depending on the review:
  - **TestFlight** → Test Information → *Beta App Review Information* →
    sign-in required + username/password.
  - **App Store submission** → Distribution → the version (e.g. "1.0 Prepare
    for Submission") → *App Review Information* → Sign-In Required. This
    section does not exist until an App Store version has been created, so
    don't go hunting for it during a TestFlight-only phase.

  (It is NOT under "App Information" — that page is name/subtitle/category.
  The previous account, `appreview@example.com`, stopped authenticating and its
  password was committed here in plaintext; don't repeat either mistake.)
  **Re-check this account signs in before every submission.** Reviewers are
  asked to test account deletion (5.1.1(v)), and the app's own Delete Account
  button will remove it — if that happens, recreate it and update this note.
- UGC moderation: report + block on all user content (Guideline 1.2) — reports
  reviewed within 24 hours via Supabase dashboard.
- Contacts permission is optional; all features work without it except
  "Find from contacts."
```


## User-generated content (update 2026-08-02)

3Wood now carries three kinds of user-generated content: course reviews, comments
on activity, and **course photos**. All three are reportable in-app (Report action
on each item), users can be blocked, and blocked users' content is filtered
server-side. Photos are re-encoded on device before upload, which strips EXIF —
no location metadata leaves the phone with an image. Mention all three in the App
Review notes, not just reviews.
