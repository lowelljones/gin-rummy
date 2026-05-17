import "dotenv/config";
import cors from "@fastify/cors";
import Fastify from "fastify";
import { createClient } from "@supabase/supabase-js";
import {
  applyIntent,
  buildPerspective,
  buildPerspectives,
  createNewMatch,
  type Intent,
  type ServerTruth,
} from "../../rules/src/index.js";
import { computeTestBotIntent, hasTestBotWork } from "./bot.js";
import { assertChatRateAllowed, moderateChatText } from "./chatModeration.js";

const PORT = Number(process.env.PORT ?? "8787");
/* Railway's internal healthcheck and service-to-service network is IPv6, so when running
 * under Railway we must bind to `::` (dual-stack) — `0.0.0.0` listens IPv4-only and the
 * unexposed-service healthcheck will fail. Locally we keep `0.0.0.0` so the iPhone can
 * reach the Mac over LAN IPv4. Override either side with an explicit HOST env if needed. */
const HOST = process.env.HOST ?? (process.env.RAILWAY_ENVIRONMENT_NAME ? "::" : "0.0.0.0");
const SUPABASE_URL = process.env.SUPABASE_URL ?? "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const ANON_KEY = process.env.SUPABASE_ANON_KEY ?? "";
const CORS = process.env.CORS_ORIGIN ?? "*";
const BOT_USER_ID = process.env.GINRUMMY_BOT_USER_ID ?? "00000000-0000-0000-0000-000000000001";

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.warn("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const authClient = createClient(SUPABASE_URL, ANON_KEY || SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const app = Fastify({ logger: true });
await app.register(cors, { origin: CORS === "*" ? true : CORS });

// Wrap any promise (typically a Supabase call) so it can never hang the route.
// On timeout, rejects with a TimeoutError that includes the step label so logs
// pinpoint exactly which await stalled.
class TimeoutError extends Error {
  constructor(public label: string, public ms: number) {
    super(`Timed out after ${ms}ms at step "${label}"`);
    this.name = "TimeoutError";
  }
}

function withTimeout<T>(p: PromiseLike<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new TimeoutError(label, ms)), ms);
    Promise.resolve(p).then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      }
    );
  });
}

const SUPABASE_STEP_TIMEOUT_MS = Number(process.env.SUPABASE_STEP_TIMEOUT_MS ?? "8000");

function randomInvite(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (let i = 0; i < 8; i++) s += chars[Math.floor(Math.random() * chars.length)];
  return s;
}

async function userFromAuthHeader(h: string | undefined): Promise<{ id: string; email?: string } | null> {
  if (!h?.startsWith("Bearer ")) return null;
  const token = h.slice("Bearer ".length).trim();
  if (!token) return null;
  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? undefined };
}

function rng(): () => number {
  return Math.random;
}

function seatForUser(game: { seat_for_user: Record<string, number> }, userId: string): 0 | 1 | null {
  const s = game.seat_for_user[userId];
  if (s === 0 || s === 1) return s as 0 | 1;
  return null;
}

async function ensureProfile(userId: string, email?: string) {
  const name = email?.split("@")[0] ?? "Player";
  await admin.from("profiles").upsert({ id: userId, display_name: name }, { onConflict: "id" });
}

async function ensureHand(gameId: string, truth: ServerTruth): Promise<string> {
  const { data: row } = await admin
    .from("hands")
    .select("id")
    .eq("game_id", gameId)
    .eq("index", truth.handIndex)
    .maybeSingle();

  if (row?.id) return row.id;

  const { data: inserted, error } = await admin
    .from("hands")
    .insert({
      game_id: gameId,
      index: truth.handIndex,
      dealer_seat: truth.dealer,
    })
    .select("id")
    .single();

  if (error) throw error;
  return inserted!.id as string;
}

async function processTestBotIfNeeded(gameId: string, opts?: { maxSteps?: number }) {
  const { data: row, error } = await admin
    .from("games")
    .select("id, status, server_truth, move_seq, lobby_id, is_bot_game")
    .eq("id", gameId)
    .maybeSingle();

  if (error || !row) return;
  if (!row.is_bot_game) return;
  if (row.status !== "active") return;

  let state = row.server_truth as ServerTruth;
  let seq = Number(row.move_seq);
  const lobbyId = (row as { lobby_id: string | null }).lobby_id;
  /** GET /state polls frequently — cap work per request so the client sees JSON quickly; POST /move keeps default high for immediate bot replies after human intents. */
  const maxSteps = opts?.maxSteps ?? 200;

  for (let i = 0; i < maxSteps; i++) {
    if (state.phase === "matchOver") {
      await admin
        .from("games")
        .update({ status: "completed", server_truth: state })
        .eq("id", gameId);
      if (lobbyId) {
        await admin.from("lobbies").update({ status: "closed" }).eq("id", lobbyId);
      }
      return;
    }
    if (!hasTestBotWork(state)) return;

    const intent = computeTestBotIntent(state);
    if (!intent) {
      app.log.warn({ gameId, phase: state.phase, turn: state.currentTurn }, "Test bot: no intent");
      return;
    }
    const outcome = applyIntent(state, intent, rng());
    if (!outcome.ok) {
      app.log.warn({ gameId, err: outcome.error, intent: intent.type }, "Test bot: illegal intent");
      return;
    }
    state = outcome.state;
    seq += 1;
    const handId = await ensureHand(gameId, state);

    const nextStatus: "active" | "completed" = state.phase === "matchOver" ? "completed" : "active";
    const { error: uErr } = await admin
      .from("games")
      .update({ server_truth: state, move_seq: seq, current_hand_id: handId, status: nextStatus })
      .eq("id", gameId);
    if (uErr) {
      app.log.error(uErr);
      return;
    }

    const perspectives = buildPerspectives(state);
    const { error: mErr } = await admin.from("game_moves").insert({
      game_id: gameId,
      hand_id: handId,
      seq,
      actor_user_id: null,
      intent_type: intent.type,
      intent_payload: intent as unknown as Record<string, unknown>,
      server_truth: state as unknown as Record<string, unknown>,
      perspectives: perspectives as unknown as Record<string, unknown>,
    });
    if (mErr) {
      app.log.error(mErr);
      return;
    }
    if (lobbyId && state.phase === "matchOver") {
      await admin.from("lobbies").update({ status: "closed" }).eq("id", lobbyId);
    }
    if (state.phase === "matchOver") return;
  }
  app.log.warn({ gameId }, "Test bot: max steps (still active)");
}

app.post("/lobbies", async (req, reply) => {
  const reqLog = req.log;
  reqLog.info({ hasAuth: Boolean(req.headers.authorization) }, "POST /lobbies hit");
  try {
    reqLog.info("before auth lookup");
    const user = await withTimeout(
      userFromAuthHeader(req.headers.authorization),
      SUPABASE_STEP_TIMEOUT_MS,
      "auth.getUser"
    );
    reqLog.info({ userId: user?.id ?? null }, "after auth lookup");
    if (!user) return reply.code(401).send({ error: "Unauthorized" });

    reqLog.info({ userId: user.id }, "before profiles.upsert");
    await withTimeout(ensureProfile(user.id, user.email), SUPABASE_STEP_TIMEOUT_MS, "profiles.upsert");
    reqLog.info({ userId: user.id }, "after profiles.upsert");

    let code = randomInvite();
    for (let i = 0; i < 5; i++) {
      reqLog.info({ attempt: i, code }, "before lobbies.invite_code clash check");
      const { data: clash, error: clashErr } = await withTimeout(
        admin.from("lobbies").select("id").eq("invite_code", code).maybeSingle(),
        SUPABASE_STEP_TIMEOUT_MS,
        `lobbies.select(invite_code) attempt=${i}`
      );
      reqLog.info(
        { attempt: i, code, clashId: clash?.id ?? null, err: clashErr?.message ?? null },
        "after lobbies.invite_code clash check"
      );
      if (clashErr) {
        return reply.code(500).send({ error: `lobbies clash check failed: ${clashErr.message}` });
      }
      if (!clash) break;
      code = randomInvite();
    }

    reqLog.info({ code, createdBy: user.id }, "before lobbies.insert");
    const { data: lobby, error } = await withTimeout(
      admin
        .from("lobbies")
        .insert({ invite_code: code, created_by: user.id, status: "open" })
        .select("id, invite_code, status")
        .single(),
      SUPABASE_STEP_TIMEOUT_MS,
      "lobbies.insert"
    );
    reqLog.info(
      { lobbyId: lobby?.id ?? null, err: error?.message ?? null },
      "after lobbies.insert"
    );

    if (error) return reply.code(500).send({ error: error.message });
    if (!lobby) return reply.code(500).send({ error: "lobbies.insert returned no row" });

    reqLog.info({ lobbyId: lobby.id, userId: user.id }, "before lobby_players.insert");
    const { error: lpErr } = await withTimeout(
      admin.from("lobby_players").insert({ lobby_id: lobby.id, user_id: user.id, seat: 0 }),
      SUPABASE_STEP_TIMEOUT_MS,
      "lobby_players.insert"
    );
    reqLog.info({ lobbyId: lobby.id, err: lpErr?.message ?? null }, "after lobby_players.insert");
    if (lpErr) return reply.code(500).send({ error: `lobby_players insert failed: ${lpErr.message}` });

    reqLog.info({ lobbyId: lobby.id, code: lobby.invite_code }, "returning lobby response");
    return { lobby };
  } catch (e) {
    if (e instanceof TimeoutError) {
      reqLog.error({ step: e.label, ms: e.ms }, "POST /lobbies timed out");
      return reply
        .code(504)
        .send({ error: `Upstream timeout at "${e.label}" (${e.ms}ms). Check Supabase reachability.` });
    }
    const msg = e instanceof Error ? e.message : String(e);
    reqLog.error({ err: msg }, "POST /lobbies unexpected error");
    return reply.code(500).send({ error: `POST /lobbies failed: ${msg}` });
  }
});

/** Public-ish preview so invite links can show the host display name without joining yet. */
app.get("/lobbies/:code/preview", async (req, reply) => {
  const code = (req.params as { code: string }).code.toUpperCase();
  const { data: lobby, error: lErr } = await admin
    .from("lobbies")
    .select("id, status, created_by")
    .eq("invite_code", code)
    .maybeSingle();
  if (lErr || !lobby) return reply.code(404).send({ error: "Lobby not found" });

  const { data: profile } = await admin
    .from("profiles")
    .select("display_name")
    .eq("id", lobby.created_by)
    .maybeSingle();

  const hostDisplayName = (profile?.display_name as string | undefined)?.trim()
    ? (profile?.display_name as string)
    : "Someone";

  return {
    invite_code: code,
    status: lobby.status as string,
    host_display_name: hostDisplayName,
  };
});

type LobbyPlayerRow = {
  user_id: string;
  seat: number;
  ready: boolean;
};

type LobbyPlayerPublic = {
  seat: number;
  user_id: string;
  display_name: string;
  ready: boolean;
  is_self: boolean;
};

async function fetchLobbyPlayersWithNames(
  lobbyId: string,
  selfId: string
): Promise<LobbyPlayerPublic[]> {
  const { data: rows } = await admin
    .from("lobby_players")
    .select("user_id, seat, ready")
    .eq("lobby_id", lobbyId)
    .order("seat", { ascending: true });
  const players = (rows ?? []) as LobbyPlayerRow[];
  if (players.length === 0) return [];
  const names = await displayNamesForUserIds(players.map((p) => p.user_id));
  return players.map((p) => ({
    seat: Number(p.seat),
    user_id: p.user_id,
    display_name: names[p.user_id] ?? "Player",
    ready: Boolean(p.ready),
    is_self: p.user_id === selfId,
  }));
}

async function findLatestGameId(lobbyId: string): Promise<string | null> {
  const { data: game } = await admin
    .from("games")
    .select("id")
    .eq("lobby_id", lobbyId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (game?.id as string | undefined) ?? null;
}

type LobbyStatusPayload = {
  lobby: { id: string; invite_code: string; status: string };
  gameId: string | null;
  guest_joined: boolean;
  you_seat: number | null;
  players: LobbyPlayerPublic[];
  both_ready: boolean;
};

async function buildLobbyStatusPayload(
  lobby: { id: string; invite_code: string; status: string },
  selfId: string
): Promise<LobbyStatusPayload> {
  const players = await fetchLobbyPlayersWithNames(lobby.id, selfId);
  const guestJoined = players.some((p) => p.seat === 1);
  const you = players.find((p) => p.is_self);
  const seat0 = players.find((p) => p.seat === 0);
  const seat1 = players.find((p) => p.seat === 1);
  const bothReady = Boolean(seat0?.ready && seat1?.ready);

  let gameId: string | null = null;
  if (lobby.status === "in_game" || lobby.status === "closed") {
    gameId = await findLatestGameId(lobby.id);
  }

  return {
    lobby,
    gameId,
    guest_joined: guestJoined,
    you_seat: you ? you.seat : null,
    players,
    both_ready: bothReady,
  };
}

/**
 * Try to atomically transition an "open" lobby to "in_game" and create the game row.
 * Returns the resulting gameId (newly created or one another writer already created),
 * or null when the lobby isn't ready to start (e.g. only one player, not both ready,
 * or the lobby has been closed). Used by POST /lobbies/:code/ready when both seats
 * have flipped ready=true, so neither client needs an explicit "Start" press.
 */
async function tryStartHumanGameIfReady(lobbyId: string): Promise<string | null> {
  const { data: players } = await admin
    .from("lobby_players")
    .select("user_id, seat, ready")
    .eq("lobby_id", lobbyId)
    .order("seat", { ascending: true });
  const seats = (players ?? []) as LobbyPlayerRow[];
  const seat0 = seats.find((p) => Number(p.seat) === 0);
  const seat1 = seats.find((p) => Number(p.seat) === 1);
  if (!seat0 || !seat1) return null;
  if (!seat0.ready || !seat1.ready) return null;

  // Atomic "claim the start" — only one concurrent caller updates the row.
  const { data: claimed, error: claimErr } = await admin
    .from("lobbies")
    .update({ status: "in_game" })
    .eq("id", lobbyId)
    .eq("status", "open")
    .select("id")
    .maybeSingle();
  if (claimErr) {
    app.log.error({ err: claimErr.message, lobbyId }, "ready: lobby claim failed");
    return findLatestGameId(lobbyId);
  }
  if (!claimed) {
    // Someone else already transitioned the lobby — return whatever game they created.
    return findLatestGameId(lobbyId);
  }

  const truth = createNewMatch(`lobby-${lobbyId}`, rng());
  const handId = crypto.randomUUID();
  const { data: game, error: gErr } = await admin
    .from("games")
    .insert({
      lobby_id: lobbyId,
      status: "active",
      race_target: truth.raceTarget,
      player_ids: [seat0.user_id, seat1.user_id] as [string, string],
      is_bot_game: false,
      seat_for_user: { [seat0.user_id]: 0, [seat1.user_id]: 1 },
      server_truth: truth,
      move_seq: 0,
      current_hand_id: handId,
    })
    .select("id")
    .single();

  if (gErr || !game) {
    app.log.error({ err: gErr?.message ?? "no row", lobbyId }, "ready: game insert failed");
    // Roll the lobby back so a retry can re-attempt.
    await admin.from("lobbies").update({ status: "open" }).eq("id", lobbyId).eq("status", "in_game");
    return null;
  }

  await admin.from("hands").insert({
    id: handId,
    game_id: game.id,
    index: truth.handIndex,
    dealer_seat: truth.dealer,
  });

  return game.id as string;
}

/**
 * Lobby status / latest game lookup. Both the host and the joiner poll this
 * while sitting in the waiting room — they see each other's display name,
 * the per-seat ready flag, and once `gameId` is non-null they transition to
 * the table.
 */
app.get("/lobbies/:code", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });
  const code = (req.params as { code: string }).code.toUpperCase();
  const { data: lobby, error: lErr } = await admin
    .from("lobbies")
    .select("id, invite_code, status, created_by")
    .eq("invite_code", code)
    .maybeSingle();
  if (lErr || !lobby) return reply.code(404).send({ error: "Lobby not found" });

  const isCreator = lobby.created_by === user.id;
  const { data: membership } = await admin
    .from("lobby_players")
    .select("seat")
    .eq("lobby_id", lobby.id)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!isCreator && !membership) return reply.code(403).send({ error: "Not a member" });

  return buildLobbyStatusPayload(
    { id: lobby.id, invite_code: lobby.invite_code, status: lobby.status },
    user.id
  );
});

/**
 * Toggle the caller's ready flag in the lobby waiting room. When both seats
 * are ready, this handler atomically transitions the lobby to in_game and
 * creates the game; the caller and the other player (via polling) both pick
 * up the new gameId and move to the table.
 *
 * Body: { ready: boolean } — explicit value for idempotence (clients that
 * tap twice quickly don't accidentally un-ready themselves).
 */
app.post("/lobbies/:code/ready", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const code = (req.params as { code: string }).code.toUpperCase();
  const { data: lobby, error: lErr } = await admin
    .from("lobbies")
    .select("id, invite_code, status, created_by")
    .eq("invite_code", code)
    .maybeSingle();
  if (lErr || !lobby) return reply.code(404).send({ error: "Lobby not found" });

  const { data: membership } = await admin
    .from("lobby_players")
    .select("seat")
    .eq("lobby_id", lobby.id)
    .eq("user_id", user.id)
    .maybeSingle();
  // /ready toggles the caller's lobby_players row, so they must have one.
  // The creator is auto-inserted by POST /lobbies, but defensively reject if missing.
  if (!membership) return reply.code(403).send({ error: "Not a member" });

  if (lobby.status !== "open") {
    // Already started — just return the current state so the client can
    // transition into the game on its next poll cycle.
    return buildLobbyStatusPayload(
      { id: lobby.id, invite_code: lobby.invite_code, status: lobby.status },
      user.id
    );
  }

  const body = (req.body ?? {}) as { ready?: unknown };
  const ready = body.ready === undefined ? true : Boolean(body.ready);

  const { error: rErr } = await admin
    .from("lobby_players")
    .update({ ready })
    .eq("lobby_id", lobby.id)
    .eq("user_id", user.id);
  if (rErr) return reply.code(500).send({ error: rErr.message });

  if (ready) {
    await tryStartHumanGameIfReady(lobby.id);
  }

  // Re-read lobby (its status may have flipped to in_game) so the payload
  // includes the freshly-created gameId for the caller.
  const { data: lobbyAfter } = await admin
    .from("lobbies")
    .select("id, invite_code, status")
    .eq("id", lobby.id)
    .single();

  return buildLobbyStatusPayload(
    lobbyAfter ?? { id: lobby.id, invite_code: lobby.invite_code, status: lobby.status },
    user.id
  );
});

app.post("/lobbies/:code/join", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });
  await ensureProfile(user.id, user.email);

  const code = (req.params as { code: string }).code.toUpperCase();
  const { data: lobby, error: lErr } = await admin
    .from("lobbies")
    .select("id, status")
    .eq("invite_code", code)
    .maybeSingle();

  if (lErr || !lobby) return reply.code(404).send({ error: "Lobby not found" });
  if (lobby.status !== "open") return reply.code(400).send({ error: "Lobby not open" });

  const { data: existing } = await admin.from("lobby_players").select("seat, user_id").eq("lobby_id", lobby.id);
  if (existing?.some((p) => p.user_id === user.id)) {
    return { ok: true, seat: existing!.find((p) => p.user_id === user.id)!.seat };
  }
  if (existing?.some((p) => p.seat === 1)) {
    return reply.code(400).send({ error: "Lobby full" });
  }

  const { error: jErr } = await admin.from("lobby_players").insert({ lobby_id: lobby.id, user_id: user.id, seat: 1 });
  if (jErr) return reply.code(500).send({ error: jErr.message });

  return { ok: true, seat: 1 };
});

/**
 * Solo bot game starter (`bot: true` required). Human-vs-human games go through
 * POST /lobbies/:code/ready and are auto-created when both seats are ready, so
 * this endpoint is bot-only now — older clients that POST without `bot: true`
 * are rejected with 400 to prevent a stale UI from racing the ready flow and
 * double-creating a game for the same lobby.
 */
app.post("/lobbies/:code/start", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const code = (req.params as { code: string }).code.toUpperCase();
  const { data: lobby } = await admin.from("lobbies").select("id, status, created_by").eq("invite_code", code).maybeSingle();
  if (!lobby) return reply.code(404).send({ error: "Lobby not found" });
  if (lobby.created_by !== user.id) return reply.code(403).send({ error: "Only host can start" });
  if (lobby.status !== "open") return reply.code(400).send({ error: "Lobby already started" });

  const withBot = (req.body as { bot?: boolean } | null)?.bot === true;
  if (!withBot) {
    return reply.code(400).send({
      error: "Human matches now use the ready-up flow. Tap Ready in the lobby instead.",
    });
  }

  const { data: players, error: pErr } = await admin
    .from("lobby_players")
    .select("user_id, seat")
    .eq("lobby_id", lobby.id)
    .order("seat", { ascending: true });

  if (pErr || !players) {
    return reply.code(500).send({ error: pErr?.message ?? "players query failed" });
  }

  if (players.length !== 1) {
    return reply.code(400).send({ error: "Solo test bot: lobby must have only the host" });
  }

  const p0 = players[0] as { user_id: string; seat: number };
  const p1 = { user_id: BOT_USER_ID, seat: 1 } as { user_id: string; seat: number };

  const truth = createNewMatch(`lobby-${lobby.id}`, rng());
  const handId = crypto.randomUUID();

  const { data: game, error: gErr } = await admin
    .from("games")
    .insert({
      lobby_id: lobby.id,
      status: "active",
      race_target: truth.raceTarget,
      player_ids: [p0.user_id, p1.user_id] as [string, string],
      is_bot_game: true,
      seat_for_user: { [p0.user_id]: 0, [p1.user_id]: 1 },
      server_truth: truth,
      move_seq: 0,
      current_hand_id: handId,
    })
    .select("id, server_truth, seat_for_user, is_bot_game")
    .single();

  if (gErr || !game) return reply.code(500).send({ error: gErr?.message ?? "game insert failed" });

  await admin.from("hands").insert({
    id: handId,
    game_id: game.id,
    index: truth.handIndex,
    dealer_seat: truth.dealer,
  });

  await admin.from("lobbies").update({ status: "in_game" }).eq("id", lobby.id);

  await processTestBotIfNeeded(game.id);

  const { data: gameAfter } = await admin
    .from("games")
    .select("server_truth, seat_for_user")
    .eq("id", game.id)
    .single();

  const finalTruth = (gameAfter?.server_truth as ServerTruth) ?? (game.server_truth as ServerTruth);
  const seat = seatForUser(game as { seat_for_user: Record<string, number> }, user.id)!;
  return {
    gameId: game.id,
    perspective: buildPerspective(finalTruth, seat),
    testBot: true,
  };
});

app.get("/games/:id/state", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const id = (req.params as { id: string }).id;
  await processTestBotIfNeeded(id, { maxSteps: 12 });

  const { data: game, error } = await admin
    .from("games")
    .select("id, server_truth, seat_for_user, move_seq, status")
    .eq("id", id)
    .maybeSingle();

  if (error || !game) return reply.code(404).send({ error: "Game not found" });

  const seat = seatForUser(game as { seat_for_user: Record<string, number> }, user.id);
  if (seat === null) return reply.code(403).send({ error: "Not a participant" });

  const truth = game.server_truth as ServerTruth;
  return {
    perspective: buildPerspective(truth, seat),
    moveSeq: game.move_seq,
    status: game.status,
    betting:
      truth.phase === "matchOver"
        ? { raw: truth.bettingRaw, bucket: truth.bettingBucket }
        : null,
  };
});

const CHAT_PAGE = 100;

type ChatRow = { id: string; user_id: string; body: string; created_at: string };

async function displayNamesForUserIds(userIds: string[]): Promise<Record<string, string>> {
  const unique = [...new Set(userIds)];
  if (unique.length === 0) return {};
  const { data: profiles } = await admin.from("profiles").select("id, display_name").in("id", unique);
  const map: Record<string, string> = {};
  for (const id of unique) {
    map[id] = "Player";
  }
  for (const row of profiles ?? []) {
    const id = row.id as string;
    const raw = (row.display_name as string | undefined)?.trim();
    map[id] = raw && raw.length > 0 ? raw : "Player";
  }
  return map;
}

function formatChatRows(rows: ChatRow[], selfId: string, names: Record<string, string>) {
  return rows.map((r) => ({
    id: r.id,
    userId: r.user_id,
    displayName: names[r.user_id] ?? "Player",
    body: r.body,
    createdAt: r.created_at,
    fromSelf: r.user_id === selfId,
  }));
}

app.get("/games/:id/chat", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const id = (req.params as { id: string }).id;
  const { data: game, error: gErr } = await admin
    .from("games")
    .select("id, seat_for_user")
    .eq("id", id)
    .maybeSingle();

  if (gErr || !game) return reply.code(404).send({ error: "Game not found" });
  if (seatForUser(game as { seat_for_user: Record<string, number> }, user.id) === null) {
    return reply.code(403).send({ error: "Not a participant" });
  }

  const afterRaw = (req.query as { after?: string }).after?.trim();

  let rows: ChatRow[] = [];

  if (afterRaw) {
    const t = Date.parse(afterRaw);
    if (Number.isNaN(t)) {
      return reply.code(400).send({ error: "Invalid after timestamp" });
    }
    const afterIso = new Date(t).toISOString();
    const { data, error } = await admin
      .from("game_chat_messages")
      .select("id, user_id, body, created_at")
      .eq("game_id", id)
      .gt("created_at", afterIso)
      .order("created_at", { ascending: true })
      .limit(CHAT_PAGE);
    if (error) return reply.code(500).send({ error: error.message });
    rows = (data ?? []) as ChatRow[];
  } else {
    const { data, error } = await admin
      .from("game_chat_messages")
      .select("id, user_id, body, created_at")
      .eq("game_id", id)
      .order("created_at", { ascending: false })
      .limit(CHAT_PAGE);
    if (error) return reply.code(500).send({ error: error.message });
    rows = ((data ?? []) as ChatRow[]).slice().reverse();
  }

  const names = await displayNamesForUserIds(rows.map((r) => r.user_id));
  return { messages: formatChatRows(rows, user.id, names) };
});

app.post("/games/:id/chat", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const id = (req.params as { id: string }).id;
  const { data: game, error: gErr } = await admin
    .from("games")
    .select("id, seat_for_user, status")
    .eq("id", id)
    .maybeSingle();

  if (gErr || !game) return reply.code(404).send({ error: "Game not found" });
  if (game.status !== "active" && game.status !== "completed") {
    return reply.code(400).send({ error: "Game not available" });
  }
  if (seatForUser(game as { seat_for_user: Record<string, number> }, user.id) === null) {
    return reply.code(403).send({ error: "Not a participant" });
  }

  const mod = moderateChatText((req.body as { text?: unknown })?.text);
  if (!mod.ok) {
    return reply.code(400).send({ error: mod.error, code: mod.code });
  }

  const rl = assertChatRateAllowed(user.id, id);
  if (!rl.ok) {
    return reply.code(429).send({ error: rl.error, code: "rate_limited" });
  }

  const { data: inserted, error: insErr } = await admin
    .from("game_chat_messages")
    .insert({ game_id: id, user_id: user.id, body: mod.text })
    .select("id, user_id, body, created_at")
    .single();

  if (insErr || !inserted) {
    return reply.code(500).send({ error: insErr?.message ?? "insert failed" });
  }

  const row = inserted as ChatRow;
  const names = await displayNamesForUserIds([row.user_id]);
  return {
    message: formatChatRows([row], user.id, names)[0],
  };
});

app.post("/games/:id/move", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const id = (req.params as { id: string }).id;
  const { data: game, error } = await admin
    .from("games")
    .select("id, server_truth, seat_for_user, move_seq, current_hand_id, status, lobby_id, is_bot_game")
    .eq("id", id)
    .maybeSingle();

  if (error || !game) return reply.code(404).send({ error: "Game not found" });
  if (game.status !== "active") return reply.code(400).send({ error: "Game not active" });

  const seat = seatForUser(game as { seat_for_user: Record<string, number> }, user.id);
  if (seat === null) return reply.code(403).send({ error: "Not a participant" });

  const body = req.body as { intent?: unknown };
  let scoped: Intent;
  try {
    scoped = parseClientIntent(body, seat);
  } catch (e) {
    return reply.code(400).send({ error: e instanceof Error ? e.message : "Bad intent" });
  }
  const truth = game.server_truth as ServerTruth;
  const outcome = applyIntent(truth, scoped, rng());

  if (!outcome.ok) return reply.code(400).send({ error: outcome.error });

  const newTruth = outcome.state;
  const nextSeq = Number(game.move_seq) + 1;
  const handId = await ensureHand(id, newTruth);

  const humanStatus: "active" | "completed" = newTruth.phase === "matchOver" ? "completed" : "active";
  await admin
    .from("games")
    .update({
      server_truth: newTruth,
      move_seq: nextSeq,
      current_hand_id: handId,
      status: humanStatus,
    })
    .eq("id", id);

  const perspectives = buildPerspectives(newTruth);

  const { error: mErr } = await admin.from("game_moves").insert({
    game_id: id,
    hand_id: handId,
    seq: nextSeq,
    actor_user_id: user.id,
    intent_type: scoped.type,
    intent_payload: scoped as unknown as Record<string, unknown>,
    server_truth: newTruth as unknown as Record<string, unknown>,
    perspectives: perspectives as unknown as Record<string, unknown>,
  });

  if (mErr) return reply.code(500).send({ error: mErr.message });

  if (newTruth.phase === "matchOver") {
    const lobbyId = (game as { lobby_id?: string }).lobby_id;
    if (lobbyId) {
      await admin.from("lobbies").update({ status: "closed" }).eq("id", lobbyId);
    }
  } else if ((game as { is_bot_game?: boolean }).is_bot_game) {
    await processTestBotIfNeeded(id);
  }

  const { data: after } = await admin
    .from("games")
    .select("server_truth, move_seq, status")
    .eq("id", id)
    .single();

  const finalTruth = (after?.server_truth as ServerTruth) ?? newTruth;
  const finalSeq = after ? Number(after.move_seq) : nextSeq;

  return {
    perspective: buildPerspective(finalTruth, seat),
    moveSeq: finalSeq,
    betting: finalTruth.phase === "matchOver" ? { raw: finalTruth.bettingRaw, bucket: finalTruth.bettingBucket } : null,
  };
});

function parseClientIntent(body: { intent?: unknown }, seat: 0 | 1): Intent {
  const raw = body?.intent;
  if (!raw || typeof raw !== "object" || !("type" in raw)) {
    throw new Error("intent required");
  }
  const t = (raw as { type: string }).type;
  if (t === "cutPick") {
    const r = raw as { index?: unknown };
    if (r.index === undefined) throw new Error("cutPick requires index (0..faceDownRemaining-1)");
    const index = Math.floor(Number(r.index));
    if (!Number.isFinite(index)) throw new Error("cutPick: invalid index");
    return { type: "cutPick", seat, index };
  }
  return normalizeIntentSeat(raw as Intent, seat);
}

function normalizeIntentSeat(intent: Intent, seat: 0 | 1): Intent {
  switch (intent.type) {
    case "cutPick":
    case "upcardTake":
    case "upcardPass":
    case "drawStock":
    case "takeDiscard":
    case "discard":
    case "declareBigGin":
    case "layoffDone":
    case "layoffAttach":
      return { ...intent, seat };
    case "ackHandOver":
      return intent;
    default:
      return intent;
  }
}

app.get("/health", async () => ({ ok: true }));

await app.listen({ port: PORT, host: HOST });
console.log(`Gin API listening on ${HOST} port ${PORT}`);
