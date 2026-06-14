import type { HandEpisodeOutcome, Intent, Seat, ServerTruth } from "../../rules/src/index.js";

/** Row shape for public.hand_episodes (API insert). */
export interface HandEpisodeRow {
  game_id: string;
  deal_index: number;
  hand_index: number;
  dealer_seat: Seat;
  non_dealer_seat: Seat;
  knock_check_card: string | null;
  outcome: HandEpisodeOutcome;
  winner_seat: Seat | null;
  closer_seat: Seat | null;
  points_awarded: number;
  scores_before: [number, number];
  scores_after: [number, number];
  opening_hands: { "0": string[]; "1": string[] };
  result: Record<string, unknown> | null;
  started_at_move_seq: number | null;
  ended_at_move_seq: number;
}

/** Denormalized columns on game_moves (pre-move deal context). */
export interface MoveAnalyticsFields {
  actor_seat: Seat | null;
  deal_index: number;
  hand_index: number;
  phase: ServerTruth["phase"];
  stock_count: number;
}

function actorSeatFromIntent(intent: Intent): Seat | null {
  if ("seat" in intent && (intent.seat === 0 || intent.seat === 1)) {
    return intent.seat;
  }
  return null;
}

function openingHandsJson(deal: NonNullable<ServerTruth["currentDeal"]>): HandEpisodeRow["opening_hands"] {
  return {
    "0": [...deal.openingHands[0]],
    "1": [...deal.openingHands[1]],
  };
}

function buildEpisodeRow(
  gameId: string,
  prev: ServerTruth,
  next: ServerTruth,
  deal: NonNullable<ServerTruth["currentDeal"]>,
  outcome: HandEpisodeOutcome,
  winner: Seat | null,
  closer: Seat | null,
  points: number,
  moveSeq: number,
): HandEpisodeRow {
  const result = next.lastHandResult;
  return {
    game_id: gameId,
    deal_index: deal.dealIndex,
    hand_index: deal.handIndex,
    dealer_seat: deal.dealer,
    non_dealer_seat: deal.nonDealer,
    knock_check_card: deal.knockCheckCard,
    outcome,
    winner_seat: winner,
    closer_seat: closer,
    points_awarded: points,
    scores_before: [...deal.scoresAtStart] as [number, number],
    scores_after: [...next.scores] as [number, number],
    opening_hands: openingHandsJson(deal),
    result: result ? (JSON.parse(JSON.stringify(result)) as Record<string, unknown>) : null,
    started_at_move_seq: deal.startedAtMoveSeq ?? null,
    ended_at_move_seq: moveSeq,
  };
}

/**
 * Detect a completed deal from the transition across one applied intent.
 * Returns null when no terminal event occurred or when legacy state lacks currentDeal.
 */
export function detectHandEpisodeClose(
  gameId: string,
  prev: ServerTruth,
  next: ServerTruth,
  intent: Intent,
  moveSeq: number,
): HandEpisodeRow | null {
  const deal = prev.currentDeal;
  if (!deal) return null;

  if (intent.type === "respondRedeal" && intent.accept && prev.redeal?.status === "pending") {
    return buildEpisodeRow(gameId, prev, next, deal, "mutualRedeal", null, null, 0, moveSeq);
  }

  if (next.voidFlash === "playedThrough") {
    return buildEpisodeRow(gameId, prev, next, deal, "playedThrough", null, null, 0, moveSeq);
  }

  const enteredHandOver = prev.phase !== "handOver" && prev.phase !== "matchOver";
  const nowTerminal = next.phase === "handOver" || next.phase === "matchOver";
  if (enteredHandOver && nowTerminal && next.lastHandResult) {
    const hr = next.lastHandResult;
    return buildEpisodeRow(
      gameId,
      prev,
      next,
      deal,
      hr.kind,
      hr.winner,
      hr.closer,
      hr.points,
      moveSeq,
    );
  }

  return null;
}

/** Stamp the first move seq on a newly dealt layout (engine leaves this null at deal time). */
export function stampDealStartMoveSeq(truth: ServerTruth, moveSeq: number): ServerTruth {
  const deal = truth.currentDeal;
  if (!deal || deal.startedAtMoveSeq != null) return truth;
  return {
    ...truth,
    currentDeal: { ...deal, startedAtMoveSeq: moveSeq },
  };
}

/** Pre-move context for game_moves denormalized columns. */
export function moveAnalyticsFields(prev: ServerTruth, intent: Intent): MoveAnalyticsFields {
  return {
    actor_seat: actorSeatFromIntent(intent),
    deal_index: prev.dealIndex,
    hand_index: prev.handIndex,
    phase: prev.phase,
    stock_count: prev.stock.length,
  };
}
