# App Store Connect — iOS App Version page (v1.0)

Copy/paste fields for the **1.0** version page. Facts pulled from the current build:
bundle ID `com.lowelljones.GinRummyApp`, `MARKETING_VERSION = 1.0`,
`CURRENT_PROJECT_VERSION = 10`, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), portrait only,
iOS 17.0+, backend at `https://gin-rummy-production.up.railway.app`.

---

## Resubmission status

1.0 (9) was **rejected** on 12 Aug 2026 under guideline 4 (Design) — "portions of the buttons
are cut off screen", reviewed on an iPad Air 11" (M3) running iPadOS 26.5.2. Submission ID
`35483edc-b3e0-43c8-a236-2a7a3a306ccb`.

A rejection leaves the 1.0 version page editable in place, so **this is still the 1.0 page** —
don't create a 1.1. Swap build 9 for build 10, reply in the Messages thread, and resubmit.
There is no "What's New" field to fill in; that only appears for updates to a released version.

Fixed in build 10:

- On iPadOS this iPhone-only app runs in a compatibility window with a **375 × 721 pt** canvas
  — shorter than any modern iPhone. The play table's fixed heights overflowed it and pushed the
  bottom bar off-screen. Every vertical dimension now derives from the available height.
- Propose redeal moved into the pinned action bar; it used to be a second bar stacked beneath.
- Layoff screen: the unmelded-card row now wraps (it was laying out ~630 pt wide in a 375 pt
  window), and "Done — lock it in" is pinned instead of below the fold.
- Same overflow affected **iPhone SE** (375 × 667). Verified fixed on both.

Suggested reply to App Review:

```
Thanks for the detail — the screenshot made this easy to reproduce. On iPadOS our iPhone-only
app runs in a compatibility window with a 375 x 721 pt canvas, and our table layout used fixed
heights tuned for a taller iPhone, so the bottom controls overflowed. Build 10 sizes the whole
table from the available height, and the buttons that were stacked at the bottom are now a
single bar. Verified on iPad Air 11" (iPadOS 26) and iPhone SE.

To test a full game solo, tap "Play bot" on the home screen — no second player needed.
```

---

## Description

> 1,358 characters — limit 4,000.

```
Gin Rummy is a two-player card game for people who already have someone to play with.

Send a friend a link, they tap it, and you're at the table. No lobby of strangers, no timers pushing you around, no coin store.

PLAY A FRIEND
Create a table and share the invite link in Messages. Tapping it opens the game straight on their phone. Both players ready up and the hand is dealt.

PRACTICE ANY TIME
No one free? Play a hand against the built-in bot to warm up or learn the flow.

THE RULES, PLAYED PROPERLY
• Sets and runs, ten-card hands, draw or take the discard
• The down card sets the knock limit — an ace down card means no knocking that hand
• Gin scores 25 plus your opponent's unmelded count; EO scores 50 plus
• First to 125 takes the match, and the last winner deals

KEEP SCORE AT THE KITCHEN TABLE
Playing with real cards? The built-in scorecard tallies hands, deadwood, and match points for an in-person game — no online table needed.

YOUR RECORD
Every finished match lands in your game log with the score, the hands won, and your running win rate.

TALK A LITTLE TRASH
Chat at the table while you play. Block anyone whose messages you'd rather not see, or report a message and we'll review it.

Sign in with Apple or an email address. No ads. No in-app purchases. No real-money play — the match points are just how gin has always been scored.
```

## Keywords

> 95 characters — limit 100. Comma-separated, no spaces after commas. Words already in the
> app name ("gin", "rummy") are indexed from the title, so they're deliberately left out.

```
card game,2 player,cards with friends,melds,knock,deadwood,scorecard,multiplayer,online,classic
```

## Support URL

```
https://gin-rummy-production.up.railway.app/privacy
```

Verified live (HTTP 200, ~5.2 KB, last updated June 26, 2026) with a
`mailto:lowellwjones@gmail.com` contact link on the page — good enough for the Support URL
field, since Apple's bar is a working page where a user can reach you.

`/terms` is also live (HTTP 200). `/support` returns 404 — there's no such route today. If
you'd prefer a purpose-built support page, adding one beside the existing `/privacy` and
`/terms` handlers in `backend/api/src/server.ts` is a small change, but it isn't blocking.

## Marketing URL (optional)

Leave blank — there's no marketing site.

## Promotional text (optional)

> 104 characters — limit 170. Editable without submitting a new build.

```
Text a friend a link and you're dealt in. Real gin rummy, house rules intact, no coins and no strangers.
```

## Copyright

```
2026 Lowell Jones
```

## App Store screenshots

**Done** — captured on device and checked in under `docs/app-store/screenshots/`:

| Size class | Pixels (portrait) | Files | Required? |
|---|---|---|---|
| 6.9" (iPhone 17 Pro Max / 16 Pro Max) | 1290 × 2796 | 4, in `6.9-inch/` | **Yes** |
| 6.5" (iPhone 11 Pro Max style) | 1242 × 2688 | 4, in `6.5-inch/` | Optional — Apple scales the 6.9" set down |
| iPad | — | — | Not needed, `TARGETED_DEVICE_FAMILY = 1` |

Both sets, in upload order: `01-table`, `02-down-card`, `03-match-end`, `04-scorecard`.

These predate build 10 and are still accurate: the layout work only changed how the table
sizes itself on short canvases, and on a 6.9" phone it renders the same. Propose redeal now
sits inside the action bar rather than in a strip below it — same position on screen, so the
shots don't mislead. No reshoot needed for this submission.

## App icon

Supplied by the build — `Assets.xcassets/AppIcon.appiconset/gin_rummy_icon_1024x1024.png`,
verified 1024 × 1024, no alpha channel. Nothing to upload manually.

## App Review contact information

```
First name:    Lowell
Last name:     Jones
Phone number:  <your number, with country code — e.g. +1 555 123 4567>
Email:         lowellwjones@gmail.com
```

`lowellwjones@gmail.com` is the address already published on the app's privacy page, so it's
consistent with what a reviewer sees in the app. Swap in `levs313@gmail.com` if you'd rather
review mail land there.

## Sign-in required?

**Yes** — check "Sign-in required" and fill in demo credentials below.

## Demo account credentials

```
Username: <demo email you create>
Password: <demo password>
```

You need to create this yourself before submitting — the app has an email/password signup
path on the auth screen (minimum 6 characters), so register one throwaway account on a real
device or the Simulator against the production backend and paste it here. Something like
`appreview@…` with a simple password is fine.

**Do not** leave this blank hoping Sign in with Apple covers it. Reviewers do use Sign in with
Apple, but a broken or hidden path is a common rejection, and the email/password account
guarantees they get in.

## Review notes

```
Gin Rummy is a two-player online card game. Everything below is reachable without a second
device or a second person.

REVIEWING WITHOUT A SECOND PLAYER
From the home screen, tap "Play bot" to start a full match against a server-driven opponent.
This exercises the complete game loop — dealing, the down-card phase, drawing, discarding,
knocking, gin, scoring, and match end — with one device and one account.

The "Score a game" card on the home screen opens the in-person scorecard, which works with
no opponent and no network game at all.

MULTIPLAYER (OPTIONAL)
"Create a table" produces an invite link of the form
https://gin-rummy-production.up.railway.app/join/<CODE>. It's a Universal Link: with the app
installed it opens the game directly; otherwise the same URL shows a landing page with the
code. To test with two devices, create a table on one, open the link on the other, and both
tap "Ready up".

NO REAL-MONEY PLAY
The app shows "match points" and "tiers" at the end of a match. These are ordinary gin rummy
scoring units, displayed as numbers only. There is no wagering, no currency, no purchase, no
payout, and no connection to any payment system. There are no in-app purchases and no ads.

USER-GENERATED CONTENT
Players can chat during a game. The app has: server-side filtering of chat text (length
limits, profanity rejection, rate limiting), per-message reporting with a stated 24-hour
review commitment, and user blocking from within chat. Blocked players are managed in
Account settings, where they can also be unblocked.

ACCOUNT DELETION
Profile > Account settings > Delete account permanently removes the account and its game
data from within the app, with a confirmation step.

SIGN IN
Sign in with Apple and email/password are both supported. Demo credentials are provided
above. Note that Sign in with Apple can be unreliable in the iOS Simulator; on a physical
device signed into iCloud it works normally.

ACCOUNT INFRASTRUCTURE
Backend API on Railway, Postgres and auth via Supabase. The app stores an email address, a
display name, and game history. No location, contacts, photos, tracking, or advertising
identifiers are collected.
```

---

## Not on the version page, but worth checking before you submit

- **App name and subtitle** live on the *App Information* page, not here. ~~The build's
  `PRODUCT_NAME` resolves to `GinRummyApp` and there's no `CFBundleDisplayName`~~ — **done**,
  `Info.plist` sets `CFBundleDisplayName` to `Gin Rummy`, so that's what appears under the icon.
- **Age rating** — the in-game chat means you'll answer "yes" to unrestricted web/user
  content questions; expect 12+ or higher. Answer the gambling questions **No**: there is no
  real-money or simulated-currency gambling.
- **Privacy nutrition labels** — declare email address and user ID linked to identity for
  app functionality; not used for tracking.
- **Privacy policy URL** (App Information page):
  `https://gin-rummy-production.up.railway.app/privacy` — verified live, and its contents
  line up with the nutrition labels above (email, display name, gameplay/chat data; manual
  scorecard stays on-device).
- **Export compliance** — no longer prompts on upload. `Info.plist` declares
  `ITSAppUsesNonExemptEncryption = false`; the app uses only standard HTTPS, which is exempt.
- **Build number** — `CFBundleVersion` is bound to `CURRENT_PROJECT_VERSION` in the pbxproj.
  Bump it there for every upload. It was previously bound to `MARKETING_VERSION`, which built
  as "1.0" and would have been rejected on arrival as not greater than the existing build 9.
- **Terms agreement** — both account-creation paths (Sign in with Apple on the landing screen,
  and the email sign-up form) now show "By continuing, you agree to our Terms of Service and
  Privacy Policy" with tappable links, for the user-generated-content guideline.
