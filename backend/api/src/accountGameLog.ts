import type { ServerTruth } from "../../rules/src/types.js";
import { matchWinnerFromScores } from "./sessionRecap.js";

/**
 * Per-player match history ("game log") shown on the profile screen: who you
 * played, whether you won, the score, the betting tier, and how many hands
 * the match ran. Pure builder so it can be unit-tested without Supabase.
 */

export type AccountGameLogEntry = {
  game_id: string;
  status: "completed" | "abandoned";
  created_at: string;
  updated_at: string;
  is_bot_game: boolean;
  opponent_user_id: string | null;
  opponent_display_name: string;
  my_score: number;
  opponent_score: number;
  hands_played: number;
  /** true you won, false you lost, null no result (abandoned before the end). */
  i_won: boolean | null;
  /** For abandoned games: whether you were the one who left. */
  i_abandoned: boolean | null;
  betting_raw: number | null;
  betting_bucket: number | null;
};

/** Aggregates cover completed human matches only — practice-bot games are
 * listed in the log but never counted toward the record. */
export type AccountGameLogTotals = {
  completed_games: number;
  wins: number;
  losses: number;
  /** Signed sum of betting tiers from this player's perspective. */
  net_buckets: number;
  hands_played: number;
};

export type AccountGameLogPayload = {
  games: AccountGameLogEntry[];
  totals: AccountGameLogTotals;
};

export type AccountGameRow = {
  id: string;
  status: string;
  created_at: string;
  updated_at: string;
  seat_for_user: Record<string, number>;
  server_truth: ServerTruth;
  abandoned_by?: string | null;
  is_bot_game?: boolean | null;
};

export function buildAccountGameLog(params: {
  userId: string;
  botUserId: string;
  rows: AccountGameRow[];
  displayNames: Record<string, string>;
}): AccountGameLogPayload {
  const { userId, botUserId, rows, displayNames } = params;

  const entries: AccountGameLogEntry[] = [];
  const totals: AccountGameLogTotals = {
    completed_games: 0,
    wins: 0,
    losses: 0,
    net_buckets: 0,
    hands_played: 0,
  };

  for (const row of rows) {
    if (row.status !== "completed" && row.status !== "abandoned") continue;

    const mySeat = row.seat_for_user[userId];
    if (mySeat !== 0 && mySeat !== 1) continue;
    const oppSeat = 1 - mySeat;

    let opponentUserId: string | null = null;
    for (const [uid, seat] of Object.entries(row.seat_for_user)) {
      if (seat === oppSeat) opponentUserId = uid;
    }

    const isBot = row.is_bot_game === true || opponentUserId === botUserId;
    const opponentName = isBot
      ? "Practice bot"
      : (opponentUserId && displayNames[opponentUserId]) || "Player";

    const truth = row.server_truth;
    const scores: [number, number] = [truth.scores[0], truth.scores[1]];
    const handsPlayed = truth.handsWon[0] + truth.handsWon[1];

    const winner =
      row.status === "completed" ? matchWinnerFromScores(scores, truth.raceTarget) : null;
    const iWon = winner === null ? null : winner === mySeat;

    const iAbandoned =
      row.status === "abandoned" ? (row.abandoned_by ?? null) === userId : null;

    entries.push({
      game_id: row.id,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      is_bot_game: isBot,
      opponent_user_id: opponentUserId,
      opponent_display_name: opponentName,
      my_score: scores[mySeat],
      opponent_score: scores[oppSeat],
      hands_played: handsPlayed,
      i_won: iWon,
      i_abandoned: iAbandoned,
      betting_raw: truth.bettingRaw ?? null,
      betting_bucket: truth.bettingBucket ?? null,
    });

    if (iWon !== null && !isBot) {
      totals.completed_games += 1;
      totals.hands_played += handsPlayed;
      if (iWon) totals.wins += 1;
      else totals.losses += 1;
      if (truth.bettingBucket != null) {
        totals.net_buckets += iWon ? truth.bettingBucket : -truth.bettingBucket;
      }
    }
  }

  // Newest first.
  entries.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());

  return { games: entries, totals };
}
