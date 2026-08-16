# App Store Connect — iOS App Version page (v1.0)

Copy/paste fields for the **1.0** version page. Facts pulled from the current build:
bundle ID `com.lowelljones.GinRummyApp`, `MARKETING_VERSION = 1.0`,
`CURRENT_PROJECT_VERSION = 10`, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), portrait only,
iOS 17.0+, backend at `https://gin-rummy-production.up.railway.app`.

---

## Resubmission status

1.0 (10) was **rejected** on 15 Aug 2026 under **guideline 2.1 (Information Needed)** — no
code defect, App Review wants a demo video and a filled-in Notes field. See
[Review notes](#review-notes) and [Demo video](#demo-video) below. Build 10 itself was not
faulted; the design issue from build 9 is fixed.

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

A second account is optional now — Gin Bot greets the player at the start of every solo
game, so Report and Block are reachable without one. Create a second only if you want the
reviewer to be able to test a real two-player table.

**Do not** leave this blank hoping Sign in with Apple covers it. Reviewers do use Sign in with
Apple, but a broken or hidden path is a common rejection, and the email/password account
guarantees they get in.

## Review notes

1.0 (10) was rejected on 15 Aug 2026 under **Guideline 2.1 — Information Needed**: App Review
asked for a demo video plus seven written items in the Notes field. Rewritten below to answer
their seven numbered items in their order, so a reviewer can tick them off. **Exactly 4,000
characters, which is the cap**, so if you expand a placeholder, trim the same amount elsewhere.

Fill in before pasting: the video link, both demo accounts, and the device list in item 2.

```
1. DEMO VIDEO: [unlisted YouTube/Vimeo link]
Shows launch, sign-in, a full hand vs. the bot, chat, reporting and blocking, the
scorecard, and account deletion.
User-generated content: the only UGC is text chat between the two players at a table.
Long-press any message from the other player for "Report Message" (harassment, hate, spam,
inappropriate, other; the dialog states reports are reviewed within 24 hours) and "Block
<name>", which hides their messages immediately. Blocked players are listed under Profile >
Account settings and can be unblocked there or in chat. Server-side moderation runs on every
message and display name: length cap, profanity rejection, rate limiting. Both sign-up paths
link the Terms of Service and Privacy Policy, and Profile > Account settings > Delete
account removes the account and its data.
Permission prompts: none. The app requests no location, contacts, camera, microphone,
photos, notifications, or App Tracking Transparency, and ships no usage-description strings,
as it calls no protected API. The only system sheet is Apple's own Sign in with Apple
dialog. We collect an email address, display name, and gameplay/chat history, for app
functionality only — never tracking or advertising.

2. TESTED ON
- <iPhone model>, iOS <version> (physical device)
- <iPad Air 11-inch (M3), iPadOS 26 — physical device, iPhone compatibility window; the
  previous review's setup>
- iPhone SE (3rd gen) and iPhone 17 Pro, iOS <version>, Simulator
iPhone-only (TARGETED_DEVICE_FAMILY = 1), portrait only, iOS 17.0+.

3. WHAT IT DOES AND WHO IT'S FOR
A two-player online gin rummy game for people who already have someone to play with: you
text one person a link, they tap it, and you're at the table. It also keeps score for an
in-person game played with real cards. Audience: adults and teens who know gin rummy.
No gambling of any kind — "match points" and "tiers" at match end are ordinary gin scoring
units shown as plain numbers, with no wagering, currency, purchase, or payout. No ads or
in-app purchases.

4. SETUP AND ACCESS
Sign-in required. Demo account — <email> / <password>. Sign in with Apple also works
(unreliable in the Simulator, normal on a physical device signed into iCloud). Second
account for two-player testing: <email> / <password>.
- FULL GAME, ONE DEVICE: home screen > "Play bot". No second player needed. Runs the whole
  loop: deal, down-card phase, draw/discard, knock, gin, layoffs, scoring, match end at 125.
- CHAT AND SAFETY TOOLS: speech-bubble icon in the top bar of any game. Gin Bot, the
  practice opponent, opens every solo game with a greeting — long-press it for "Report
  Message" and "Block". No second device needed.
- TWO PLAYERS: "Create a table" gives an invite link,
  https://gin-rummy-production.up.railway.app/join/<CODE>. A Universal Link: with the app
  installed it opens the game directly, otherwise the page shows the code. Open it on the
  second device, then both tap "Ready up".
- IN-PERSON SCORECARD: home screen > "Score a game by hand". Needs no opponent or network.

5. EXTERNAL SERVICES
Railway hosts our Node API, the authoritative game server. Supabase provides Postgres,
authentication, and realtime updates. Sign in with Apple is an optional sign-in method. Chat
and display-name filtering uses "obscenity", an open-source word list running inside our own
API; no text leaves our servers. The iOS app contains no third-party SDKs, and there are no
analytics, ad networks, payment processors, AI services, or data providers.

6. REGIONAL DIFFERENCES
None — the app behaves identically in every region and storefront. English only, with no
geo-gated features, content, pricing, or availability.

7. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable: gin rummy is a traditional public-domain card game, and this is not a
gambling product or regulated service. All artwork, including the card faces and app icon,
was produced for this app. No third-party trademarks or licensed content is used.
```

## Demo video

App Review asked for a video of the core features. Notes can't hold a file — upload the
recording as an **unlisted YouTube or Vimeo** video and paste the link into item 1 above
(also attach it in the Resolution Center reply if it's under the attachment limit).

Record on a **physical iPhone** (Settings > Control Center > Screen Recording), one
continuous take, portrait, roughly 3–5 minutes. Delete and reinstall the app first so the
recording starts from a cold, signed-out launch.

One device is enough for the whole recording. Gin Bot posts a greeting when each solo game
is created (`insertBotGreeting`, wired into `createBotGameInLobby`), and `GameChatBubble`
offers Report/Block on any message where `fromSelf` is false — so the bot's line is
long-pressable exactly like a human opponent's.

Shot list:

1. **Cold launch** — springboard, tap the icon, let the auth screen load. Show the Terms of
   Service and Privacy Policy line under the sign-up form.
2. **Sign in** — email + password with demo account 1. If you also show Sign in with Apple,
   let Apple's system sheet appear on camera; that is the only system prompt the app raises.
   Say aloud or caption: no other permission prompts exist.
3. **Solo game** — "Play bot", then play a hand end to end: down-card offer, draws and
   discards, a knock or gin, the layoff screen, hand scoring, and the running match score.
4. **Chat** — speech-bubble icon in the top bar. Gin Bot's greeting is already waiting.
   Send a message of your own so both sides of the conversation are visible.
5. **Report** — long-press Gin Bot's message, "Report Message", show the five reasons and
   the "reviewed within 24 hours" line, submit one, show the confirmation.
6. **Block** — long-press it again, "Block Gin Bot", confirm, and show the message
   disappearing and the blocked banner.
7. **Unblock** — Profile > Account settings > Blocked players, unblock, show the list empty.
8. **Scorecard** — back to home, "Score a game by hand", enter a hand or two so the tally
   updates. Makes clear this half works with no network game.
9. **Profile** — record, win rate, and the game log.
10. **Account deletion** — Account settings > Delete account, show the confirmation dialog.
    Cancel rather than confirm if you want to keep the demo account; showing the dialog is
    what they're asking for. (If you do delete it, recreate it and update the credentials.)

Don't narrate over ambiguity: if a step is slow, let it run rather than cutting, since jump
cuts read as hiding something.
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
