# App Store Connect — iOS App Version page (v1.1)

Copy/paste fields for the **1.1** version page. Facts pulled from the current build:
bundle ID `com.lowelljones.GinRummyApp`, `MARKETING_VERSION = 1.1`, iPhone-only
(`TARGETED_DEVICE_FAMILY = 1`), portrait only, iOS 17.0+, backend at
`https://gin-rummy-production.up.railway.app`.

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

**Not yet produced — this is the one item on your list that still needs work.**

Required for this app (iPhone-only, portrait):

| Size class | Pixels (portrait) | Required? |
|---|---|---|
| 6.9" (iPhone 17 Pro Max / 16 Pro Max) | 1320 × 2868 or 1290 × 2796 | **Yes** |
| 6.5" (iPhone 11 Pro Max style) | 1242 × 2688 | Optional — Apple scales the 6.9" set down |
| iPad | — | Not needed, `TARGETED_DEVICE_FAMILY = 1` |

Three to five shots is plenty. Suggested order:

1. **The table mid-hand** — your hand fanned out, discard pile, opponent across the table. This is the money shot.
2. **Home screen** — "Create a table / Join with code / Play bot", showing how quickly a game starts.
3. **Hand end / scorecard** — the outcome pinned above the scoring breakdown.
4. **Manual scorecard** — the in-person scoring feature; it differentiates the app.
5. **Profile / game log** — win rate and match history.

I can capture these from the Simulator (iPhone 17 Pro Max gives 1320 × 2868 natively) once
there's a demo account to sign in with — say the word and I'll build, launch, and grab them.

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

- **App name and subtitle** live on the *App Information* page, not here. The build's
  `PRODUCT_NAME` resolves to `GinRummyApp`, and there's no `CFBundleDisplayName` — so the
  home-screen name under the icon will read "GinRummyApp", not "Gin Rummy". Worth setting
  `CFBundleDisplayName` to `Gin Rummy` in `Info.plist` before the build you submit.
- **Age rating** — the in-game chat means you'll answer "yes" to unrestricted web/user
  content questions; expect 12+ or higher. Answer the gambling questions **No**: there is no
  real-money or simulated-currency gambling.
- **Privacy nutrition labels** — declare email address and user ID linked to identity for
  app functionality; not used for tracking.
- **Privacy policy URL** (App Information page):
  `https://gin-rummy-production.up.railway.app/privacy` — verified live, and its contents
  line up with the nutrition labels above (email, display name, gameplay/chat data; manual
  scorecard stays on-device).
