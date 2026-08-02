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
Rank every course you play, follow your friends, and settle the "best track in town" debate with receipts. Your golf crew's new clubhouse is open.
```

## Description (4000 chars max)
```
Golf is meant to be shared — and 3Wood is where your rounds live.

3Wood is a social course-ranking app for golfers. Instead of shouting star ratings into the void, you build a personal 0–10 ranking of every course you've played, follow your friends, and see the game through your crew's eyes.

RANK, DON'T RATE
Logging a course takes seconds: say whether you liked it, thought it was fine, or didn't love it, then answer a few quick head-to-head matchups against courses you've already played. 3Wood turns your choices into a personal 0–10 score for every course — no agonizing over whether something is "4 stars."

A FEED OF REAL ROUNDS
Your home feed shows the courses your friends play, save, and love. Tap any friend to see their full ranked list, their followers, and how their scores stack up against yours.

EVERY COURSE, EVERYONE'S TAKE
Open any of 16,000+ US courses to see the community rating, your friends' individual scores side by side, and written reviews from people you actually know.

FIND YOUR FOURSOME
Match your contacts to find friends already on 3Wood, invite the rest with your personal link, and race the leaderboard to see who's played the most.

PLAN THE NEXT ONE
Search by name or city, explore the map, and keep a Want-to-Play list so the next buddies trip plans itself.

Whether you're chasing the top 100 or just arguing about the best muni in town, 3Wood keeps score.

Course data © OpenGolfAPI contributors (ODbL).
Privacy policy: https://leon1224an-droid.github.io/3Wood/privacy.html
Terms: https://leon1224an-droid.github.io/3Wood/terms.html
```

## Keywords (100 chars max, comma-separated, no spaces)
```
golf,course,rankings,tracker,social,friends,rounds,tee,scorecard,beli,rate,leaderboard,map
```
(93 chars)

## Category
- Primary: Sports
- Secondary: Social Networking

## App Privacy questionnaire notes
- Contact Info → Email Address: collected, linked to identity (account).
- Contact Info → Phone Number: optional, linked, used for app functionality
  (friend matching). Numbers from the user's address book are transmitted for
  matching but NOT stored (only the user's own linked number is stored).
- Contacts: accessed on-device with permission; names never leave the device.
- User Content: reviews, rankings (linked to identity).
- Identifiers: User ID (linked).
- No tracking, no ads, no data sold.

## Screenshots plan (6.9" required set)
Use the marketing set in docs/img/ as the storyboard: score reveal (hero),
feed, course detail, friend profile, ranked list, map. Re-capture on
"iPhone 17 Pro Max" simulator for final 1320×2868 assets before submission.

## Review notes (for App Review)
- Demo account (hosted): `appreview@example.com` / `3WoodReview2026`
  (username @demo_reviewer, pre-seeded with a ranked course, a bookmark,
  and a review).
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
