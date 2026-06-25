import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildPerspective,
  type ServerTruth,
} from "../../rules/src/index.js";

export type RematchStatusPayload = {
  lobby_invite_code: string;
  players: Array<{
    seat: number;
    user_id: string;
    display_name: string;
    ready: boolean;
    is_self: boolean;
  }>;
  both_ready: boolean;
  is_bot_game: boolean;
  next_game_id: string | null;
};

export type GameStatePayload = {
  perspective: ReturnType<typeof buildPerspective>;
  moveSeq: number;
  status: string;
  leftBySeat: number | null;
  opponentDisplayName: string;
  betting: { raw: number; bucket: number } | null;
  rematch: RematchStatusPayload | null;
  lobbyInviteCode: string | null;
};

type GameRow = {
  id: string;
  server_truth: ServerTruth;
  seat_for_user: Record<string, number>;
  move_seq: number;
  status: string;
  abandoned_by?: string | null;
  lobby_id?: string | null;
  is_bot_game?: boolean;
};

export type SnapshotSyncDeps = {
  admin: SupabaseClient;
  botUserId: string;
  opponentDisplayNameForGame: (seatMap: Record<string, number>, selfId: string) => Promise<string>;
  findLobbyInviteCode: (lobbyId: string) => Promise<string | null>;
  buildRematchStatus: (
    lobbyId: string,
    currentGameId: string,
    selfId: string,
    isBotGame: boolean,
  ) => Promise<RematchStatusPayload | null>;
  tryStartRematchIfReady?: (lobbyId: string) => Promise<unknown>;
  log?: { warn: (obj: object, msg: string) => void };
};

function seatForUser(seatMap: Record<string, number>, userId: string): 0 | 1 | null {
  const s = seatMap[userId];
  if (s === 0 || s === 1) return s as 0 | 1;
  return null;
}

export async function buildGameStatePayloadForUser(
  game: GameRow,
  userId: string,
  deps: SnapshotSyncDeps,
  opts?: { tryRematchStart?: boolean },
): Promise<GameStatePayload | null> {
  const seatMap = game.seat_for_user;
  const seat = seatForUser(seatMap, userId);
  if (seat === null) return null;

  const truth = game.server_truth;
  const abandonedBy = game.abandoned_by ?? null;
  const leftBySeat =
    game.status === "abandoned" && abandonedBy !== null
      ? seatMap[abandonedBy] ?? null
      : null;
  const lobbyId = game.lobby_id ?? null;
  const isBotGame = Boolean(game.is_bot_game);
  const lobbyInviteCode = lobbyId ? await deps.findLobbyInviteCode(lobbyId) : null;

  let rematch: RematchStatusPayload | null = null;
  if (truth.phase === "matchOver" && lobbyId) {
    if (opts?.tryRematchStart && deps.tryStartRematchIfReady) {
      const probe = await deps.buildRematchStatus(lobbyId, game.id, userId, isBotGame);
      if (probe?.both_ready && !probe.next_game_id) {
        await deps.tryStartRematchIfReady(lobbyId);
      }
    }
    rematch = await deps.buildRematchStatus(lobbyId, game.id, userId, isBotGame);
  }

  const oppName = await deps.opponentDisplayNameForGame(seatMap, userId);

  return {
    perspective: buildPerspective(truth, seat),
    moveSeq: Number(game.move_seq),
    status: game.status,
    leftBySeat: leftBySeat === 0 || leftBySeat === 1 ? leftBySeat : null,
    opponentDisplayName: oppName,
    betting:
      truth.phase === "matchOver" && truth.bettingRaw != null && truth.bettingBucket != null
        ? { raw: truth.bettingRaw, bucket: truth.bettingBucket }
        : null,
    rematch,
    lobbyInviteCode,
  };
}

/** Upsert per-player snapshot rows so Realtime can push seat-filtered state. */
export async function syncPlayerGameSnapshots(
  gameId: string,
  deps: SnapshotSyncDeps,
  opts?: { tryRematchStart?: boolean },
): Promise<void> {
  const { data: game, error } = await deps.admin
    .from("games")
    .select("id, server_truth, seat_for_user, move_seq, status, abandoned_by, lobby_id, is_bot_game")
    .eq("id", gameId)
    .maybeSingle();

  if (error || !game) {
    deps.log?.warn({ gameId, err: error?.message }, "snapshot sync: game not found");
    return;
  }

  const row = game as GameRow;
  const seatMap = row.seat_for_user;
  const userIds = Object.keys(seatMap).filter((uid) => uid !== deps.botUserId);

  for (const userId of userIds) {
    const payload = await buildGameStatePayloadForUser(row, userId, deps, opts);
    if (!payload) continue;

    const { error: upsertErr } = await deps.admin.from("player_game_snapshots").upsert(
      {
        game_id: gameId,
        user_id: userId,
        move_seq: payload.moveSeq,
        perspective: payload.perspective as unknown as Record<string, unknown>,
        status: payload.status,
        left_by_seat: payload.leftBySeat,
        betting: payload.betting,
        opponent_display_name: payload.opponentDisplayName,
        rematch: payload.rematch,
        lobby_invite_code: payload.lobbyInviteCode,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "game_id,user_id" },
    );

    if (upsertErr) {
      deps.log?.warn({ gameId, userId, err: upsertErr.message }, "snapshot sync: upsert failed");
    }
  }
}

/** Refresh snapshots for completed matchOver games when lobby ready flags change. */
export async function syncRematchSnapshotsForLobby(lobbyId: string, deps: SnapshotSyncDeps): Promise<void> {
  const { data: games } = await deps.admin
    .from("games")
    .select("id, server_truth, status")
    .eq("lobby_id", lobbyId)
    .in("status", ["completed", "active"])
    .order("created_at", { ascending: false })
    .limit(4);

  for (const g of games ?? []) {
    const truth = g.server_truth as ServerTruth;
    if (truth.phase !== "matchOver") continue;
    await syncPlayerGameSnapshots(g.id as string, deps, { tryRematchStart: true });
  }
}
