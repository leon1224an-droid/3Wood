# TestFlight / App Store submission checklist

Everything below the "user" lines is scriptable — run through this top to
bottom on upload day. Prereq: Apple Developer enrollment approved.

## One-time setup (after Apple approves)

- [ ] **(user)** Sign in to App Store Connect, accept agreements (Agreements, Tax, Banking → free apps only need the free-app agreement).
- [ ] **(user)** Xcode → Settings → Accounts → add Apple ID → confirm the team appears.
- [ ] Set the team on the 3Wood target (Signing & Capabilities → Team; automatic signing).
- [ ] App Store Connect → My Apps → "+" → New App:
  - Platform iOS, Name `3Wood: Social Golf Rankings`, primary language English (U.S.)
  - Bundle ID `com.leonan.threewood`, SKU `threewood-ios`
- [ ] Register the bundle id happens automatically with Xcode-managed signing.

## Every upload

- [ ] Bump `MARKETING_VERSION` (user-facing, e.g. 1.0) and `CURRENT_PROJECT_VERSION` (build number, always increases).
- [ ] Confirm Release config points at hosted Supabase (Supa.swift — the precondition guard catches this too).
- [ ] Unit + UI suites green against local stack.
- [ ] Archive: Product → Archive in Xcode (or `xcodebuild archive -scheme 3Wood -destination 'generic/platform=iOS'`).
- [ ] Distribute → App Store Connect → Upload (export compliance is pre-answered by `ITSAppUsesNonExemptEncryption=NO`).
- [ ] Wait for processing (~15 min), then TestFlight tab → add internal testers (your Apple ID) → install via TestFlight app.

## Before submitting for App Review

- [ ] Paste listing copy from `docs/appstore-listing.md` (name/subtitle/promo/description/keywords).
- [ ] Upload screenshots (6.9" set). The set in `docs/appstore/screenshots/` was **re-captured 2026-08-05** (commit 97e5d36) against the current build — all six verified 1320×2868, the correct 6.9" geometry. No re-capture needed.
- [ ] Support URL: `https://leon1224an-droid.github.io/3Wood/support.html`
      Marketing URL: `https://leon1224an-droid.github.io/3Wood/`
      Privacy Policy URL: `https://leon1224an-droid.github.io/3Wood/privacy.html`
- [ ] App Privacy questionnaire: answers in `docs/appstore-listing.md`.
- [ ] Age rating questionnaire. UGC now includes user-uploaded PHOTOS as well as reviews and comments — answer the user-generated-content questions accordingly (has UGC, has moderation/report/block, has blocking). Expect a rating above 4+; Apple raises it for apps with unmoderated-at-scale UGC.
- [ ] App Privacy (nutrition labels) must include **Photos or Videos** — added to PrivacyInfo.xcprivacy; the ASC questionnaire is separate and must match.
- [ ] Review notes: demo account `3woodapp+review@gmail.com` (@demo_golfer) — password is in App Store Connect, NOT in this repo (it's public). **Verify it signs in before every submission**: reviewers test account deletion, which is what killed the previous demo account.
- [ ] Mention report/block moderation covering reviews, comments AND photos; note Contacts and Location are both optional.
- [ ] **(user)** Upgrade Supabase to Pro (or verify free-tier project is un-paused and warm) before the review window.
- [ ] Submit. Typical first-review turnaround: 24–48h.

## Post-approval

- [ ] Release manually (recommended) after a final TestFlight sanity pass.
- [ ] Rotate the Supabase DB password if not already done.
- [ ] Point invite links / marketing at the App Store page (add the real badge + link on docs/index.html).
