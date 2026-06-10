/**
 * End-to-end test of the invite-link flow as experienced by two humans
 * texting each other:
 *
 *   1. Host signs in, creates a lobby, and "copies" the HTTPS share link
 *      (exactly the URL the iOS share panel produces).
 *   2. Friend "taps" the link: GET /join/:code must return a friendly HTML
 *      page (not a 404 JSON error) containing the ginrummy:// bounce link.
 *   3. Friend's app receives ginrummy://join/CODE, previews the lobby,
 *      joins it, and both players ready up.
 *   4. The lobby transitions to in_game with a real gameId for both seats.
 *
 * Also verifies a bad/expired code returns the friendly "invite not found"
 * page instead of a dead end.
 *
 * Run: npx tsx invite-link-e2e.ts   (expects the API on http://127.0.0.1:8799
 * or set API. Uses .env Supabase creds to provision throwaway users.)
 */
import "dotenv/config";
import { createClient } from "@supabase/supabase-js";

const API = process.env.API ?? "http://127.0.0.1:8799";
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const ANON_KEY = process.env.SUPABASE_ANON_KEY!;

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

let failures = 0;
function check(name: string, cond: boolean, detail?: string) {
  if (cond) {
    console.log(`  PASS  ${name}`);
  } else {
    failures++;
    console.error(`  FAIL  ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

async function makeUser(label: string): Promise<{ id: string; token: string }> {
  const email = `e2e-invite-${label}-${Date.now()}@example.com`;
  const password = `Test-${Math.random().toString(36).slice(2)}-9x`;
  const { data: created, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error || !created.user) throw new Error(`createUser(${label}): ${error?.message}`);

  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(`signIn(${label}): ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { access_token: string };
  return { id: created.user.id, token: json.access_token };
}

async function api(path: string, token?: string, init?: RequestInit) {
  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init?.headers ?? {}),
    },
  });
  const text = await res.text();
  let body: unknown = text;
  try {
    body = JSON.parse(text);
  } catch {
    /* HTML responses stay as text */
  }
  return { status: res.status, body, text, contentType: res.headers.get("content-type") ?? "" };
}

/** Mirror of the iOS AppModel.parseInviteCode logic for both URL forms. */
function parseInviteCode(url: string): string | null {
  const scheme = url.match(/^ginrummy:\/\/join\/([A-Za-z0-9]+)/);
  if (scheme) return scheme[1].toUpperCase();
  const path = url.match(/\/join\/([A-Za-z0-9]+)/);
  if (path) return path[1].toUpperCase();
  return null;
}

async function main() {
  console.log(`Invite link E2E against ${API}\n`);

  const host = await makeUser("host");
  const friend = await makeUser("friend");
  let lobbyId: string | null = null;

  try {
    // --- 1. Host creates lobby (same call the iOS app makes) ---
    const create = await api("/lobbies", host.token, { method: "POST", body: "{}" });
    check("host creates lobby", create.status === 200, `status=${create.status} body=${create.text.slice(0, 200)}`);
    const lobby = (create.body as { lobby?: { id: string; invite_code: string } }).lobby;
    if (!lobby) throw new Error("no lobby in create response");
    lobbyId = lobby.id;
    const code = lobby.invite_code;

    // The exact link the iOS share panel now copies / shares:
    const sharedLink = `${API}/join/${code}`;
    console.log(`\n  Host texts friend: ${sharedLink}\n`);

    // --- 2. Friend taps the HTTPS link (no auth — Safari hit) ---
    const page = await api(`/join/${code}`);
    check("tapped link returns 200 HTML page", page.status === 200 && page.contentType.includes("text/html"),
      `status=${page.status} type=${page.contentType}`);
    check("page contains app bounce link", page.text.includes(`ginrummy://join/${code}`));
    check("page shows host invite copy", page.text.includes("invited you to Gin Rummy"));
    check("page shows the invite code", page.text.includes(code));
    check("page never leaks raw JSON error", !page.text.includes('"error"'));

    // --- 3. Friend's phone opens ginrummy://join/CODE; app parses the code ---
    const bounce = page.text.match(/ginrummy:\/\/join\/[A-Z0-9]+/)?.[0] ?? "";
    const parsed = parseInviteCode(bounce);
    check("app parses code from bounce link", parsed === code, `parsed=${parsed}`);
    // Same parser must also handle the https link directly (Universal Links path)
    check("app parses code from https link too", parseInviteCode(sharedLink) === code);

    // --- 4. Friend previews + joins (InviteAcceptView flow) ---
    const preview = await api(`/lobbies/${code}/preview`);
    check("friend sees invite preview", preview.status === 200 &&
      (preview.body as { status?: string }).status === "open", `status=${preview.status}`);

    const join = await api(`/lobbies/${code}/join`, friend.token, { method: "POST", body: "{}" });
    check("friend joins lobby", join.status === 200, `status=${join.status} body=${join.text.slice(0, 200)}`);

    // --- 5. Both ready up; game must start ---
    const hostReady = await api(`/lobbies/${code}/ready`, host.token, {
      method: "POST",
      body: JSON.stringify({ ready: true }),
    });
    check("host readies up", hostReady.status === 200, `status=${hostReady.status}`);

    const friendReady = await api(`/lobbies/${code}/ready`, friend.token, {
      method: "POST",
      body: JSON.stringify({ ready: true }),
    });
    const friendPayload = friendReady.body as { gameId?: string | null };
    check("friend readies up", friendReady.status === 200, `status=${friendReady.status}`);
    check("game starts for friend", typeof friendPayload.gameId === "string" && friendPayload.gameId.length > 0,
      `gameId=${friendPayload.gameId}`);

    const hostStatus = await api(`/lobbies/${code}`, host.token);
    const hostPayload = hostStatus.body as { gameId?: string | null };
    check("host poll sees same game", hostPayload.gameId === friendPayload.gameId,
      `host=${hostPayload.gameId} friend=${friendPayload.gameId}`);

    // --- 6. Bad / expired code still gets a friendly page ---
    const bad = await api(`/join/ZZZZ9999`);
    check("bad code returns HTML (not raw 404 JSON)", bad.contentType.includes("text/html"), `type=${bad.contentType}`);
    check("bad code page explains the problem", bad.text.includes("doesn't match an active lobby"));

    // Joining the now-started lobby via a re-tapped link should not 500
    const lateJoinPage = await api(`/join/${code}`);
    check("re-tapped link after start still renders", lateJoinPage.status === 200 &&
      lateJoinPage.text.includes("already started"), `status=${lateJoinPage.status}`);
  } finally {
    // --- Cleanup: throwaway users + their lobby/game rows ---
    try {
      if (lobbyId) {
        const { data: games } = await admin.from("games").select("id").eq("lobby_id", lobbyId);
        for (const g of games ?? []) {
          await admin.from("hands").delete().eq("game_id", g.id);
          await admin.from("game_chat_messages").delete().eq("game_id", g.id);
        }
        await admin.from("games").delete().eq("lobby_id", lobbyId);
        await admin.from("lobby_players").delete().eq("lobby_id", lobbyId);
        await admin.from("lobbies").delete().eq("id", lobbyId);
      }
      await admin.from("profiles").delete().in("id", [host.id, friend.id]);
      await admin.auth.admin.deleteUser(host.id);
      await admin.auth.admin.deleteUser(friend.id);
      console.log("\n  (cleanup done)");
    } catch (e) {
      console.warn(`  cleanup warning: ${(e as Error).message}`);
    }
  }

  console.log(failures === 0 ? "\nALL CHECKS PASSED" : `\n${failures} CHECK(S) FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("E2E crashed:", e);
  process.exit(1);
});
