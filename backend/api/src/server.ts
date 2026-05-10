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

const PORT = Number(process.env.PORT ?? "8787");
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

async function processTestBotIfNeeded(gameId: string) {
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
  const maxSteps = 200;

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

/**
 * Lobby status / latest game lookup. Used by the joiner to poll for the host
 * pressing Start; once the lobby moves to in_game we surface the active gameId
 * so the joiner can transition to the table without an extra "I'm here" round-trip.
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

  let gameId: string | null = null;
  if (lobby.status === "in_game" || lobby.status === "closed") {
    const { data: game } = await admin
      .from("games")
      .select("id")
      .eq("lobby_id", lobby.id)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    gameId = (game?.id as string | undefined) ?? null;
  }

  return {
    lobby: { id: lobby.id, invite_code: lobby.invite_code, status: lobby.status },
    gameId,
  };
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

app.post("/lobbies/:code/start", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const code = (req.params as { code: string }).code.toUpperCase();
  const { data: lobby } = await admin.from("lobbies").select("id, status, created_by").eq("invite_code", code).maybeSingle();
  if (!lobby) return reply.code(404).send({ error: "Lobby not found" });
  if (lobby.created_by !== user.id) return reply.code(403).send({ error: "Only host can start" });

  const withBot = (req.body as { bot?: boolean } | null)?.bot === true;

  const { data: players, error: pErr } = await admin
    .from("lobby_players")
    .select("user_id, seat")
    .eq("lobby_id", lobby.id)
    .order("seat", { ascending: true });

  if (pErr || !players) {
    return reply.code(500).send({ error: pErr?.message ?? "players query failed" });
  }

  if (withBot) {
    if (players.length !== 1) {
      return reply.code(400).send({ error: "Solo test bot: lobby must have only the host" });
    }
  } else if (players.length !== 2) {
    return reply.code(400).send({ error: "Need two players" });
  }

  const p0 = withBot
    ? (players[0] as { user_id: string; seat: number })
    : (players.find((p) => p.seat === 0) as (typeof players)[0]);
  const p1 = withBot
    ? ({ user_id: BOT_USER_ID, seat: 1 } as { user_id: string; seat: number })
    : (players.find((p) => p.seat === 1) as (typeof players)[0]);

  const truth = createNewMatch(`lobby-${lobby.id}`, rng());
  const handId = crypto.randomUUID();

  const { data: game, error: gErr } = await admin
    .from("games")
    .insert({
      lobby_id: lobby.id,
      status: "active",
      race_target: truth.raceTarget,
      player_ids: [p0.user_id, p1.user_id] as [string, string],
      is_bot_game: withBot,
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
    testBot: withBot,
  };
});

app.get("/games/:id/state", async (req, reply) => {
  const user = await userFromAuthHeader(req.headers.authorization);
  if (!user) return reply.code(401).send({ error: "Unauthorized" });

  const id = (req.params as { id: string }).id;
  await processTestBotIfNeeded(id);

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

await app.listen({ port: PORT, host: "0.0.0.0" });
console.log(`Gin API listening on http://localhost:${PORT}`);
