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
- [ ] Upload screenshots from `docs/appstore/screenshots/` (6.9" set).
- [ ] Support URL: `https://leon1224an-droid.github.io/3Wood/support.html`
      Marketing URL: `https://leon1224an-droid.github.io/3Wood/`
      Privacy Policy URL: `https://leon1224an-droid.github.io/3Wood/privacy.html`
- [ ] App Privacy questionnaire: answers in `docs/appstore-listing.md`.
- [ ] Age rating questionnaire: all "None" → 4+ (user-generated content questions: has UGC, has moderation/report/block, has contact info collection = phone optional).
- [ ] Review notes: demo account `appreview@example.com` / `3WoodReview2026`; mention report/block moderation and that Contacts is optional.
- [ ] **(user)** Upgrade Supabase to Pro (or verify free-tier project is un-paused and warm) before the review window.
- [ ] Submit. Typical first-review turnaround: 24–48h.

## Post-approval

- [ ] Release manually (recommended) after a final TestFlight sanity pass.
- [ ] Rotate the Supabase DB password if not already done.
- [ ] Point invite links / marketing at the App Store page (add the real badge + link on docs/index.html).
