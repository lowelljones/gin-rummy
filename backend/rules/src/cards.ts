export const SUITS = ["S", "H", "D", "C"] as const;
export type Suit = (typeof SUITS)[number];

export const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K"] as const;
export type Rank = (typeof RANKS)[number];

export type CardId = `${Rank}${Suit}`;

const RANK_INDEX: Record<Rank, number> = {
  A: 1,
  "2": 2,
  "3": 3,
  "4": 4,
  "5": 5,
  "6": 6,
  "7": 7,
  "8": 8,
  "9": 9,
  T: 10,
  J: 11,
  Q: 12,
  K: 13,
};

/** Ace-low run order (A=1 … K=13). */
export function rankOrderLow(card: CardId): number {
  return RANK_INDEX[parseRank(card)];
}

/** Deadwood / knock comparison value: A=1, 2–9 face, T/J/Q/K=10. */
export function deadwoodValue(card: CardId): number {
  const r = parseRank(card);
  if (r === "T" || r === "J" || r === "Q" || r === "K") return 10;
  if (r === "A") return 1;
  return RANK_INDEX[r];
}

/** Cut comparison: suit strength S>H>D>C, ace-high rank. */
export function suitStrength(suit: Suit): number {
  const order: Record<Suit, number> = { S: 4, H: 3, D: 2, C: 1 };
  return order[suit];
}

export function cutRankStrength(card: CardId): number {
  const r = parseRank(card);
  if (r === "A") return 14;
  return RANK_INDEX[r];
}

export function compareCutCards(a: CardId, b: CardId): number {
  // Rank is primary; suit is tie-breaker.
  const ra = cutRankStrength(a);
  const rb = cutRankStrength(b);
  if (ra !== rb) return ra - rb;
  const sa = suitStrength(parseSuit(a));
  const sb = suitStrength(parseSuit(b));
  return sa - sb;
}

export function parseRank(card: CardId): Rank {
  return card[0] as Rank;
}

export function parseSuit(card: CardId): Suit {
  return card[1] as Suit;
}

export function buildDeck(): CardId[] {
  const deck: CardId[] = [];
  for (const s of SUITS) {
    for (const r of RANKS) {
      deck.push(`${r}${s}` as CardId);
    }
  }
  return deck;
}

export function shuffleDeck(deck: CardId[], rng: () => number): CardId[] {
  const copy = [...deck];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

export function upcardKnockValue(card: CardId | null): number | null {
  if (!card) return null;
  if (parseRank(card) === "A") return null;
  return deadwoodValue(card);
}
