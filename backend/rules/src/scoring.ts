import type { Seat } from "./types.js";
import { deadwoodValue, type CardId } from "./cards.js";
import { applyLayoffsGreedy, bestDeadwood, isValidMeld, type Meld } from "./melds.js";

export function deadwoodTotal(cards: CardId[]): number {
  return cards.reduce((s, c) => s + deadwoodValue(c), 0);
}

/** End-of-hand race points (knock undercut bonus included in basePoints from resolveKnockScoring). */
export function scoreGin(opponentDeadwood: CardId[]): number {
  return 25 + deadwoodTotal(opponentDeadwood);
}

export function scoreEO(opponentDeadwood: CardId[]): number {
  return 50 + deadwoodTotal(opponentDeadwood);
}

/** After manual layoffs: compare deadwood piles only. */
export function resolveKnockFinal(params: {
  knocker: Seat;
  knockerDeadwood: CardId[];
  opponentDeadwood: CardId[];
}): { winner: Seat; points: number } {
  const { knocker, knockerDeadwood, opponentDeadwood } = params;
  const kDead = deadwoodTotal(knockerDeadwood);
  const oDead = deadwoodTotal(opponentDeadwood);
  if (oDead < kDead) {
    return { winner: (1 - knocker) as Seat, points: kDead - oDead + 25 };
  }
  return { winner: knocker, points: oDead - kDead };
}

/** Greedy auto-layoff scoring (used for tests / bots). */
export function resolveKnockScoring(params: {
  knocker: Seat;
  knockerMelds: Meld[];
  knockerDeadwood: CardId[];
  opponentHand: CardId[];
}): { winner: Seat; loser: Seat; basePoints: number; undercutBonus: number } {
  const { knocker, knockerMelds, knockerDeadwood, opponentHand } = params;
  const { opponentDeadwood } = applyLayoffsGreedy(knockerMelds, opponentHand);
  const kDead = deadwoodTotal(knockerDeadwood);
  const oDead = deadwoodTotal(opponentDeadwood);
  if (oDead < kDead) {
    return {
      winner: (1 - knocker) as Seat,
      loser: knocker,
      basePoints: kDead - oDead,
      undercutBonus: 25,
    };
  }
  return {
    winner: knocker,
    loser: (1 - knocker) as Seat,
    basePoints: oDead - kDead,
    undercutBonus: 0,
  };
}

export function computeBettingSettlement(params: {
  winner: Seat;
  loser: Seat;
  finalScores: [number, number];
  handsWon: [number, number];
}): { raw: number; bucket: number } {
  const { winner, loser, finalScores, handsWon } = params;
  const wScore = finalScores[winner];
  const lScore = finalScores[loser];
  const shutoutBonus = lScore === 0 ? 100 : 0;
  const netHands = handsWon[winner] - handsWon[loser];
  const raw = wScore - lScore + 100 + shutoutBonus + 25 * netHands;
  const bucket = bettingBucket(raw);
  return { raw, bucket };
}

export function bettingBucket(raw: number): number {
  if (raw < 150) return 1;
  return 2 + Math.floor((raw - 150) / 100);
}

/** Validate knocker's claimed layout matches cards and achieves optimal deadwood. */
export function validateKnockerLayout(hand10: CardId[], melds: Meld[], deadwood: CardId[]): boolean {
  const allMeldCards = melds.flatMap((m) => m.cards);
  const all = sortUnique([...allMeldCards, ...deadwood]);
  const h = sortUnique([...hand10]);
  if (all.length !== h.length || all.length !== 10) return false;
  for (let i = 0; i < all.length; i++) {
    if (all[i] !== h[i]) return false;
  }
  for (const m of melds) {
    if (!isValidMeld(m)) return false;
  }
  const dwSum = deadwoodTotal(deadwood);
  const best = bestDeadwood(hand10);
  return dwSum === best.sum;
}

function sortUnique(c: CardId[]): CardId[] {
  return [...new Set(c)].sort();
}
