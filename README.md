# Gin Rummy (friends) — skeleton

SwiftUI iOS client + Node authoritative API + Supabase Postgres for lobbies, game state, and **append-only move logs** (`server_truth` + per-player `perspectives`).

## Prerequisites

- Xcode 15+ (iOS 17)
- Node.js 20+
- A [Supabase](https://supabase.com) project

## Environment variables

### API server ([`backend/api`](backend/api))

Create `backend/api/.env` (see `.env.example`):

| Variable | Description |
|----------|-------------|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key (server only; never ship to clients) |
| `PORT` | HTTP port (default `8787`) |
| `CORS_ORIGIN` | Optional; use `*` for local dev |

### iOS app ([`ios/GinRummyApp`](ios/GinRummyApp))

Configure in Xcode target **Info** or build settings / xcconfig:

| Key | Description |
|-----|-------------|
| `SUPABASE_URL` | Anon-safe project URL |
| `SUPABASE_ANON_KEY` | Supabase anon key |
| `GIN_API_BASE_URL` | Base URL of the API (e.g. `http://localhost:8787` dev) |

The app reads these from `Info.plist` keys of the same name.

## Database

Apply migrations in order from [`supabase/migrations`](supabase/migrations) in the Supabase SQL editor or CLI:

```bash
npx supabase db push   # if using Supabase CLI linked project
```

> **Lobby ready flow** (migration [`20260517000000_lobby_ready.sql`](supabase/migrations/20260517000000_lobby_ready.sql))
> adds a `ready` boolean to `lobby_players`. Both seats must tap **Ready up** in the
> waiting room — the server auto-creates the game when both flip true. Apply this
> migration before deploying the latest API/iOS build, otherwise `/lobbies/:code/ready`
> will fail with `column "ready" does not exist`.

## Run API locally

```bash
cd backend/api
npm install
cp .env.example .env   # fill in Supabase keys (optional: GINRUMMY_BOT_USER_ID for solo test bot)
npm run dev
```

### Solo test bot (no second phone)

- Apply migration [`supabase/migrations/20260426000001_test_bot.sql`](supabase/migrations/20260426000001_test_bot.sql) in the SQL editor.
- In the iOS lobby, turn on **Solo: play vs test bot**, then **Start vs test bot**. The host is seat `0`; seat `1` is a server-driven bot that **passes** on the upcard offer, then on its turn **draws** from stock and **discards** the last card in hand — declaring **gin / big gin** whenever the engine requires it (and auto-`ackHandOver`, `layoffDone` on knock). Bot moves are stored in `game_moves` with `actor_user_id = null`.

## Rules engine tests

```bash
cd backend/rules
npm install
npm test
```

## API unit tests (bot + chat moderation)

```bash
cd backend/api
npm install
npm test
```

## iOS app

Open [`ios/GinRummyApp/GinRummyApp.xcodeproj`](ios/GinRummyApp/GinRummyApp.xcodeproj) in Xcode, set your bundle ID and signing team, add `Info.plist` values above, then run on a simulator or device.

### Invite links

Invite links shared from the lobby are **HTTPS** URLs served by the API itself:
`https://<api-domain>/join/<CODE>`. They're tappable in iMessage (custom
`ginrummy://` links are not), and the page bounces the friend into the
installed app via `ginrummy://join/<CODE>`, with the code + instructions as a
fallback. The link domain comes from `GIN_INVITE_WEB_BASE_URL` in `Info.plist`
(falls back to `GIN_API_BASE_URL` when it's HTTPS).

Test the whole two-player flow (create lobby → text link → tap → join → both
ready → game starts) hermetically, no live Supabase needed:

```bash
cd backend/api
npm run test:invite-link
```

### Universal links (optional upgrade)

The landing page works without any Apple setup. To make links open the app
*directly* from Messages (skipping the Safari hop), configure Universal Links:

1. Host **AASA** (no file extension) at `https://<your-domain>/.well-known/apple-app-site-association` with JSON like:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "<TEAMID>.com.ginrummy.GinRummyApp",
        "paths": ["/join/*"]
      }
    ]
  }
}
```

2. In Xcode: **Signing & Capabilities** → **Associated Domains** → `applinks:<your-domain>` (replace `example.com` in [`GinRummyApp.entitlements`](ios/GinRummyApp/GinRummyApp/GinRummyApp.entitlements) and set your **Team** in the target).
3. Set **GIN_INVITE_WEB_BASE_URL** in `Info.plist` to `https://<your-domain>` (no trailing slash) so ShareLink uses HTTPS invites.

For local development the app registers the custom URL scheme `ginrummy://join/<code>` (see `CFBundleURLTypes` in [`Info.plist`](ios/GinRummyApp/GinRummyApp/Info.plist)).

## Security notes

- Clients use the **anon** key + user JWT; they **never** receive the service role key.
- Inserts into `game_moves` are restricted to the service role (API server only).
- `submit_move` validates the user is a participant before applying intents.
