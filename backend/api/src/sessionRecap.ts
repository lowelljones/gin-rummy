import type { ServerTruth } from "../../rules/src/types.js";

/** One scored hand within a match (from hand_episodes). */
export type HandScoreRecap = {
  hand_index: number;
  winner_seat: 0 | 1;
  points_awarded: number;
  scores_after: [number, number];
};

export type SessionMatchRecap = {
  match_number: number;
  game_id: string;
  status: "active" | "completed" | "abandoned";
  phase: string;
  created_at: string;
  updated_at: string;
  race_target: number;
  scores: [number, number];
  hands_won: [number, number];
  winner_seat: 0 | 1 | null;
  betting_raw: number | null;
  betting_bucket: number | null;
  is_current: boolean;
  hand_scores: HandScoreRecap[];
};

export type SessionTotals = {
  completed_matches: number;
  match_wins: [number, number];
  total_betting_raw: number;
  total_buckets: number;
};

export type SessionRecapPayload = {
  lobby: { id: string; invite_code: string; status: string };
  players: Array<{
    seat: number;
    user_id: string;
    display_name: string;
    is_self: boolean;
  }>;
  matches: SessionMatchRecap[];
  totals: SessionTotals;
};

export function matchWinnerFromScores(scores: [number, number], raceTarget: number): 0 | 1 | null {
  if (scores[0] >= raceTarget) return 0;
  if (scores[1] >= raceTarget) return 1;
  return null;
}

export type SessionGameRow = {
  id: string;
  status: string;
  server_truth: ServerTruth;
  created_at: string;
  updated_at: string;
};

export type HandEpisodeRow = {
  game_id: string;
  hand_index: number;
  deal_index: number;
  winner_seat: 0 | 1 | null;
  points_awarded: number;
  scores_after: [number, number];
};

/** Collapse episodes to one row per scored hand_index (latest deal wins on ties). */
export function buildHandScoresFromEpisodes(episodes: HandEpisodeRow[]): HandScoreRecap[] {
  const latestByHand = new Map<number, { deal: number; row: HandScoreRecap }>();
  for (const ep of episodes) {
    if (ep.points_awarded <= 0 || ep.winner_seat === null) continue;
    const row: HandScoreRecap = {
      hand_index: ep.hand_index,
      winner_seat: ep.winner_seat,
      points_awarded: ep.points_awarded,
      scores_after: [ep.scores_after[0], ep.scores_after[1]],
    };
    const prev = latestByHand.get(ep.hand_index);
    if (!prev || ep.deal_index >= prev.deal) {
      latestByHand.set(ep.hand_index, { deal: ep.deal_index, row });
    }
  }

  return [...latestByHand.values()]
    .map((v) => v.row)
    .sort((a, b) => a.hand_index - b.hand_index);
}

export function attachHandScoresToMatches(
  matches: Omit<SessionMatchRecap, "hand_scores">[],
  episodes: HandEpisodeRow[],
): SessionMatchRecap[] {
  const byGame = new Map<string, HandEpisodeRow[]>();
  for (const ep of episodes) {
    const list = byGame.get(ep.game_id) ?? [];
    list.push(ep);
    byGame.set(ep.game_id, list);
  }

  return matches.map((m) => ({
    ...m,
    hand_scores: buildHandScoresFromEpisodes(byGame.get(m.game_id) ?? []),
  }));
}

export function buildSessionRecapFromGames(
  games: SessionGameRow[],
  currentGameId: string | null,
  episodes: HandEpisodeRow[] = [],
): { matches: SessionMatchRecap[]; totals: SessionTotals } {
  const sorted = [...games].sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
  );

  const baseMatches: Omit<SessionMatchRecap, "hand_scores">[] = [];
  const matchWins: [number, number] = [0, 0];
  let totalRaw = 0;
  let totalBuckets = 0;
  let completed = 0;

  sorted.forEach((g, idx) => {
    const truth = g.server_truth;
    const scores: [number, number] = [truth.scores[0], truth.scores[1]];
    const handsWon: [number, number] = [truth.handsWon[0], truth.handsWon[1]];
    const raceTarget = truth.raceTarget;

    const settled =
      g.status === "completed" && truth.phase === "matchOver" && truth.bettingRaw !== null;
    const winner = settled ? matchWinnerFromScores(scores, raceTarget) : null;

    if (winner !== null) {
      matchWins[winner] += 1;
      completed += 1;
    }

    const raw = settled ? truth.bettingRaw : null;
    const bucket = settled ? truth.bettingBucket : null;
    if (raw !== null) totalRaw += raw;
    if (bucket !== null) totalBuckets += bucket;

    baseMatches.push({
      match_number: idx + 1,
      game_id: g.id,
      status: g.status as SessionMatchRecap["status"],
      phase: truth.phase,
      created_at: g.created_at,
      updated_at: g.updated_at,
      race_target: raceTarget,
      scores,
      hands_won: handsWon,
      winner_seat: winner,
      betting_raw: raw,
      betting_bucket: bucket,
      is_current: currentGameId !== null && currentGameId === g.id,
    });
  });

  const matches = attachHandScoresToMatches(baseMatches, episodes);

  return {
    matches,
    totals: {
      completed_matches: completed,
      match_wins: matchWins,
      total_betting_raw: totalRaw,
      total_buckets: totalBuckets,
    },
  };
}
