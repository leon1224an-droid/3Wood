# 3Wood — forum & Reddit promotion plan

Written 2026-08-05. Assumption stated up front: **an App Store submission follows
the current TestFlight round.** The plan is phased around that, because the single
biggest constraint right now is not a forum rule — it's that there is no public
download link.

---

## The strategy in one line

**Post the rankings, not the app.** 3Wood's output — "every muni in [metro], ranked
0–10, here's why" — is exactly the kind of post golf communities upvote. "Check out
my app" is the kind they remove. Lead with the content the product generates, put
the app in the last line. This is a real advantage most app promotion doesn't have;
build everything around it.

Corollary: **you get one launch post per community.** Spend it on a TestFlight beta
and it's gone. Hence two phases.

---

## Blockers — close these before any public post

| # | Item | Status |
|---|------|--------|
| 1 | **Supabase Pro upgrade ($25/mo)** | ⛔ OPEN — free tier auto-pauses after ~1wk idle. A post that gets *any* traction against a paused backend kills the app for every tester at once. This is a prerequisite for promoting, not a nice-to-have. |
| 2 | **Migration 00220 pushed to hosted** | ⛔ OPEN — build 5 calls `course_visits`/`log_visit`. Without it strangers land on a load-failed screen. |
| 3 | **App Review demo account** | ⛔ Re-verify it signs in before submission (see `appstore-listing.md`). Blocks Phase 2 entirely. |
| 4 | **GitHub Pages live** | ✅ VERIFIED 2026-08-05 — `/`, `/privacy.html`, `/terms.html`, `/support.html` all return 200. |
| 5 | **Custom domain** | ⚠️ Undecided. `leon1224an-droid.github.io/3Wood/` in a Reddit post reads as unfinished and is likelier to trip link filters. If you're promoting, this stops being deferrable — a $12 domain (e.g. `3wood.app`) pointed at Pages is a half-hour job and materially raises how the link reads. |

---

## The problem the plan has to survive: cold start

A stranger installs alone and finds an empty social graph. Be honest about what
day 1 gives them:

- ✅ 16,771 US courses with community ratings and a map
- ✅ Their own ranked list built in minutes (the ranking flow is genuinely fun solo)
- ✅ The leaderboard
- ❌ A feed — empty until they follow someone

**So: recruit cohorts, not individuals.** Aim at places where a *group* joins
together — a city golf sub, a buddies-trip thread, a "rank your home track" thread
where 40 people are already comparing lists. Also: seed the community ratings
yourself before launch so a solo installer sees numbers on courses, not blanks.
Course pages that read "no ratings yet" are how a first session ends.

**US-only.** 16,771 courses are US. Don't post in r/golfaus, UK, or Canadian
communities — the app is empty there and it reads as spam.

---

## Two one-liners (write for the room)

- **Beli-aware crowd** (r/golf skews younger, will know it): *"It's Beli, but for
  golf courses."*
- **Everyone else** (GolfWRX, THP — largely won't know Beli): *"You rank courses
  head-to-head instead of guessing at star ratings, and it turns that into a 0–10
  list you can compare with your buddies."*

---

## Phase 1 — now, while TestFlight-only

Goal: build posting history, recruit 20–50 beta testers, and **learn the pitch**
cheaply. Do not touch r/golf or GolfWRX yet.

⚠️ Every subreddit named below is a **candidate, not a verified target** — I can't
fetch Reddit, so confirm each one exists under that exact name and read its rules
before posting. Names drift and some of these may not exist.

| Where | Why it's safe | What to post |
|---|---|---|
| r/TestFlight, r/iosapps, r/betatesters | Beta-recruiting subs exist for exactly this; a beta link is on-topic, not spam | Short beta call, TestFlight public link |
| r/SideProject, r/indiehackers | Builder audience, tolerant of self-promo | Build story: solo dev, 16k courses, the ranking algorithm |
| Your own network / group chats | Highest conversion by far | Personal ask |
| **Your local city sub or a local golf FB group** | A cohort that plays the same courses = the feed actually fills | "Building a course-ranking app, want to see if [city] can rank our munis" |

Simultaneously, **start participating** in r/golf, GolfWRX and THP as a golfer with
zero mention of the app. Comment on course threads, answer questions, post a round.
Three to four weeks of that history is what separates a launch post that lands from
one that's auto-filtered.

---

## ⚠️ The real long pole: you need a ranked list of your own

Drafts B and C below are the two highest-value posts in this plan, and **both
require 10–22 courses in one metro that you have personally played and ranked.**
That content can't be faked or generated — the whole post is your list.

So the critical path for Phase 2 is probably **not** App Store approval. It's
whether you have that list. Check your own Played tab:

- **If you have 15+ ranked courses in one area** → you're ready, Phase 2 gates on
  Apple only.
- **If you have a handful** → this is the long pole and it starts *now*, in
  parallel with everything else. Ranking courses you've already played (from memory,
  going back years) counts and takes an evening. Ranking ones you haven't means
  playing them, which is a month or more.

Doing this also seeds community ratings, so strangers who install don't land on
course pages that read "no ratings yet" — which is how a first session ends.

## Phase 2 — the week the App Store link is live

Sequence these **one per week**, not all at once. Blasting the same link across a
dozen communities in a few days is what triggers site-wide Reddit filtering.

| Community | Size / audience | Rules as verified | Angle |
|---|---|---|---|
| **r/golf** | ~2M, the big one. Skews younger, Beli-aware | ⚠️ **Rules not machine-readable — open the sidebar and read them yourself before posting.** Reported to be strongly anti-self-promo; assume a mod-approval requirement until you've read otherwise | Week 4+. Content post: *"I ranked all 22 munis in [metro] 0–10"* with the list in the post body. App mentioned once, at the bottom |
| **GolfWRX → "Courses, Memberships and Travel"** | Huge, gear-and-course obsessives, older | ✅ Verified: *"no unauthorized commercial postings… no advertising, promotional materials, or commercial solicitations except with prior consent."* Also a 75-post threshold on classifieds — treat it as the cultural bar generally | **Message a mod first and ask permission.** They do grant it; posting cold gets you banned. Build post count first |
| **The Hackers Paradise (THP)** | Large, very community-driven, review/testing culture | ⚠️ Couldn't verify rules text — read their forum rules thread. Culture is heavily "introduce yourself first" | Post an intro, participate a month, then ask a mod about sharing. THP runs member testing programs — a *"want 20 THP members to beta the next build"* framing fits their norms unusually well |
| **Golf Club Atlas** | Small, but your single highest-value audience — course-ranking obsessives | ✅ Verified: accounts are **staff-approved**, registration is paid, and *"non-architecture threads & posts will be deleted"*; spam = account removal | **Never post the app here.** Join, discuss architecture, be a real member. Value is credibility and product insight, not installs. If it ever comes up, it comes up in conversation |
| **MyGolfSpy forum** | Mid-size, data/testing-minded | ⚠️ Verify | Same pattern as THP: participate, then ask |
| **City subs** (r/Seattle, r/Austin, …) + local golf groups | Small but *cohort-shaped* — the cold-start fix | ⚠️ Per-sub; most allow local content | *"Ranked every public course in [city] — arguments welcome."* Best conversion-per-post of anything here |

---

## Reddit account hygiene — the #1 silent failure

A new account posting a link gets filtered invisibly. You'll think the post is live;
nobody sees it. Before Phase 2:

1. **Check your account's age and karma.** Under ~3 months or under ~100 comment
   karma, build both first. Comment for weeks before you ever post a link.
2. **Read each sub's actual rules page** (sidebar → Rules). I could not fetch these
   — Reddit blocks automated access — so this is genuinely on you, and it takes two
   minutes per sub.
3. **Prefer text posts over link posts.** Many subs filter link posts automatically;
   a text post with the link in the body usually passes.
4. **Message mods first** anywhere the rules are ambiguous. "I built a free golf app,
   is a post about it allowed, and where?" Mods say yes far more often than people
   expect, and it converts a ban risk into a sanctioned post.
5. **Keep a 10:1 ratio** — ten ordinary comments for every self-promotional post.
   This is the actual heuristic Reddit's spam filters and mods use.
6. Reply to every comment on your post for the first 6 hours. Engagement in the
   first hour decides whether it ever leaves /new.

---

## Draft posts

### A. Phase 1 — beta recruiting (r/TestFlight, r/iosapps)

> **[iOS] 3Wood — rank the golf courses you've played, Beli-style (free beta)**
>
> I got tired of star ratings meaning nothing, so I built a golf course app that
> works like Beli: you say whether you liked a course, then answer a few quick
> head-to-head matchups against courses you've already played, and it turns that
> into a personal 0–10 score for every course.
>
> 16,771 US courses in there. You can follow friends, see their scores next to
> yours on any course page, keep a want-to-play list, and there's a map.
>
> TestFlight: [link]
>
> Solo dev, first app, actively fixing things — feedback goes straight into the
> next build. iOS 17+, US courses only right now.

### B. Phase 2 — the content post for r/golf (the important one)

> **I ranked all 22 public courses in the [metro] area 0–10. Come tell me I'm wrong.**
>
> I've been playing every public track around [metro] for the past two years and
> finally sat down and ranked them head-to-head instead of trying to guess star
> ratings. Full list, best to worst:
>
> 1. **[Course]** — 9.2 — [one honest sentence: what makes it]
> 2. **[Course]** — 8.7 — [one sentence]
> 3. …
>
> [Keep going. All 22. This is the post — the list IS the content.]
>
> A few opinions I'll defend: [the spicy one]. And [course] at #14 will annoy
> people, but [reason].
>
> What am I sleeping on?
>
> *(For what it's worth, the head-to-head thing worked so well I built it into a
> free app — 3Wood, on the App Store. But mostly I want to know which one of these
> I've got badly wrong.)*

**Why this shape works:** the list is genuinely useful without the app, it invites
argument (which is upvotes), and the plug is one parenthetical at the end. Note that
mods remove whole posts — they don't edit out the plug — so if the last paragraph
crosses a line you lose the entire post and your one shot at that community. That's
the real argument for asking a mod first anywhere the rules are ambiguous.

### C. Phase 2 — city sub (the cohort play)

> **Ranked every public course in [city] — want to see if we can build a real list**
>
> [Same list format, shorter — top 10.]
>
> I built a little app for this because I wanted to compare my list against my
> buddies' and there was no good way to do it. If a few of you rank yours, we'd
> have an actual [city] golfer consensus instead of the same three Google reviews
> from 2019. Free, no ads: [link]
>
> Either way — what's the most underrated muni here?

### D. Phase 2 — GolfWRX / THP, **after** mod permission

> **Built a course-ranking app after arguing with my group about the best track in town**
>
> Long-time lurker, [N] posts here. Over the last year I built an iOS app for
> ranking courses you've played. The idea: instead of star ratings, you rank courses
> head-to-head against each other — the same way you'd actually argue about it — and
> it produces a 0–10 list. 16,771 US courses, you can follow your regular group and
> see everyone's scores side by side on a course page.
>
> No ads, no subscription, nothing sold. I'm a solo developer and a 14 handicap.
>
> [link]
>
> Mods, thank you for the OK to post this. Happy to answer anything about how the
> ranking math works — that part was the fun problem.

---

## What to measure — use the `?ref` machinery you already built

`Invite.link` already appends `?ref=username`, and `docs/index.html` already renders
a greeting banner off it. **Use a distinct ref per post** — `?ref=rgolf`,
`?ref=wrx`, `?ref=austin`, `?ref=thp` — and you get true per-community attribution
from landing-page traffic, which is far better than App Store Connect's coarse
source buckets. Costs nothing; just remember to vary the link.

Track per post: landing hits by ref, installs in the following 48h, signups
(Supabase `profiles` count), and **how many rank ≥3 courses** — that last one is the
only number that tells you the pitch matched reality. A post that drives 200 installs
and 4 completed rankings means the landing experience is broken, not that the post
failed.

Also watch: if a post lands, Supabase load spikes. See blocker #1.

## One thing promotion changes about your workload

`appstore-listing.md` commits to reviewing reported content within 24 hours, and the
app now carries three kinds of UGC (reviews, comments, photos). Ten friends are
self-policing; two hundred strangers from r/golf are not. Budget for checking the
reports queue in the Supabase dashboard daily during any active promotion push.

---

## Ordered next actions

1. Upgrade Supabase to Pro. Nothing else in this plan is safe without it.
2. Push migration 00220 to hosted, then distribute build 5 to the Friends group.
3. Decide the domain. Buy it, point it at Pages, ship the URL change in the next build.
4. Create/verify the Reddit account; start commenting in r/golf as a golfer. No links.
5. Post draft A to r/TestFlight this week. Learn what people ask.
6. Rank your own local courses in the app — you need the list in draft B to be real,
   and it seeds community ratings for everyone who installs after.
7. Submit to the App Store. Phase 2 starts the day it's approved.
