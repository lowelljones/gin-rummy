import type { Seat } from "./types.js";
import { deadwoodValue, type CardId } from "./cards.js";
import { bestDeadwood, isValidMeld, type Meld } from "./melds.js";

export function deadwoodTotal(cards: CardId[]): number {
  return cards.reduce((s, c) => s + deadwoodValue(c), 0);
}

/** Gin: 25 + opponent's unmelded total. Pass only the opponent's UNMELDED cards. */
export function scoreGin(opponentUnmelded: CardId[]): number {
  return 25 + deadwoodTotal(opponentUnmelded);
}

/** EO (11-card gin): 50 + opponent's unmelded total. Pass only the opponent's UNMELDED cards. */
export function scoreEO(opponentUnmelded: CardId[]): number {
  return 50 + deadwoodTotal(opponentUnmelded);
}

/**
 * Compare final unmelded piles after layoffs and the opponent's own melds are resolved.
 * Lower total wins the difference; a non-knocker win adds the 25-point "Cut".
 * Ties go to the defender as a Cut (25 points, zero difference).
 */
export function resolveKnockFinal(params: {
  knocker: Seat;
  knockerDeadwood: CardId[];
  opponentDeadwood: CardId[];
}): { winner: Seat; points: number } {
  const { knocker, knockerDeadwood, opponentDeadwood } = params;
  const kDead = deadwoodTotal(knockerDeadwood);
  const oDead = deadwoodTotal(opponentDeadwood);
  if (oDead <= kDead) {
    return { winner: (1 - knocker) as Seat, points: kDead - oDead + 25 };
  }
  return { winner: knocker, points: oDead - kDead };
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
