import {
  type CardId,
  deadwoodValue,
  parseRank,
  parseSuit,
  rankOrderLow,
} from "./cards.js";

export interface Meld {
  type: "set" | "run";
  cards: CardId[];
}

function sortCards(cards: CardId[]): CardId[] {
  return [...cards].sort();
}

function isValidSet(cards: CardId[]): boolean {
  if (cards.length < 3 || cards.length > 4) return false;
  const ranks = new Set(cards.map(parseRank));
  if (ranks.size !== 1) return false;
  const suits = cards.map(parseSuit);
  if (new Set(suits).size !== cards.length) return false;
  return true;
}

function isValidRun(cards: CardId[]): boolean {
  if (cards.length < 3) return false;
  const suit = parseSuit(cards[0]!);
  if (!cards.every((c) => parseSuit(c) === suit)) return false;
  const orders = [...new Set(cards.map(rankOrderLow))].sort((a, b) => a - b);
  if (orders.length !== cards.length) return false;
  for (let i = 1; i < orders.length; i++) {
    if (orders[i] !== orders[i - 1]! + 1) return false;
  }
  return true;
}

export function isValidMeld(meld: Meld): boolean {
  const cs = meld.cards;
  if (meld.type === "set") return isValidSet(cs);
  return isValidRun(cs);
}

export interface Partition {
  melds: Meld[];
  deadwood: CardId[];
}

function deadwoodSum(deadwood: CardId[]): number {
  return deadwood.reduce((s, c) => s + deadwoodValue(c), 0);
}

function subsetsOfSize(arr: CardId[], k: number): CardId[][] {
  const res: CardId[][] = [];
  function rec(start: number, chosen: CardId[]) {
    if (chosen.length === k) {
      res.push([...chosen]);
      return;
    }
    for (let i = start; i < arr.length; i++) {
      chosen.push(arr[i]!);
      rec(i + 1, chosen);
      chosen.pop();
    }
  }
  rec(0, []);
  return res;
}

/** Enumerate meld partitions; return minimum deadwood sum and one optimal partition. */
export function bestDeadwood(hand: CardId[]): { sum: number; partition: Partition } {
  if (new Set(hand).size !== hand.length) {
    throw new Error("Hand contains duplicate cards");
  }

  const cards = sortCards(hand);
  let best: { sum: number; partition: Partition } = {
    sum: Infinity,
    partition: { melds: [], deadwood: [...hand] },
  };

  function dfs(remaining: CardId[], meldsSoFar: Meld[]) {
    if (remaining.length === 0) {
      if (0 < best.sum) {
        best = { sum: 0, partition: { melds: meldsSoFar, deadwood: [] } };
      }
      return;
    }

    if (remaining.length < 3) {
      const s = deadwoodSum(remaining);
      if (s < best.sum) {
        best = { sum: s, partition: { melds: meldsSoFar, deadwood: [...remaining] } };
      }
      return;
    }

    for (let len = Math.min(4, remaining.length); len >= 3; len--) {
      for (const combo of subsetsOfSize(remaining, len)) {
        const setM: Meld = { type: "set", cards: sortCards(combo) };
        const runM: Meld = { type: "run", cards: sortCards(combo) };
        for (const meld of [setM, runM]) {
          if (!isValidMeld(meld)) continue;
          const used = new Set(meld.cards);
          const rest = remaining.filter((c) => !used.has(c));
          dfs(rest, [...meldsSoFar, meld]);
        }
      }
    }

    const s = deadwoodSum(remaining);
    if (s < best.sum) {
      best = { sum: s, partition: { melds: meldsSoFar, deadwood: [...remaining] } };
    }
  }

  dfs(cards, []);

  if (!Number.isFinite(best.sum)) {
    best = { sum: deadwoodSum(cards), partition: { melds: [], deadwood: [...cards] } };
  }

  return best;
}

/** Best deadwood after drawing to 11 and discarding exactly one card. */
export function bestAfterDiscard11(hand11: CardId[]): {
  bestSum: number;
  discard: CardId;
  partition10: Partition;
} {
  if (hand11.length !== 11) throw new Error("Expected 11 cards");
  let bestSum = Infinity;
  let bestDiscard = hand11[0]!;
  let bestPart: Partition = { melds: [], deadwood: [] };

  for (const d of hand11) {
    const ten = hand11.filter((c) => c !== d);
    if (ten.length !== 10) continue;
    const { sum, partition } = bestDeadwood(ten);
    if (sum < bestSum) {
      bestSum = sum;
      bestDiscard = d;
      bestPart = partition;
    }
  }
  return { bestSum, discard: bestDiscard, partition10: bestPart };
}

/** True if all 11 cards can be partitioned into valid melds (EO / big gin). */
export function isBigGin11(hand11: CardId[]): boolean {
  if (hand11.length !== 11) return false;

  function canPartition(remaining: CardId[]): boolean {
    if (remaining.length === 0) return true;
    if (remaining.length < 3) return false;
    for (let len = Math.min(remaining.length, 4); len >= 3; len--) {
      for (const combo of subsetsOfSize(remaining, len)) {
        const setM: Meld = { type: "set", cards: sortCards(combo) };
        const runM: Meld = { type: "run", cards: sortCards(combo) };
        for (const meld of [setM, runM]) {
          if (!isValidMeld(meld)) continue;
          const used = new Set(meld.cards);
          const rest = remaining.filter((c) => !used.has(c));
          if (canPartition(rest)) return true;
        }
      }
    }
    return false;
  }

  return canPartition([...hand11]);
}

export interface LayoffResult {
  /** Knocker melds after opponent layoffs. */
  melds: Meld[];
  /** Opponent melds formed from the cards they kept. */
  opponentMelds: Meld[];
  /** Opponent cards that remain unmelded (these count against the opponent). */
  opponentDeadwood: CardId[];
  /** Deadwood sum of `opponentDeadwood`. */
  unmelded: number;
}

/**
 * Optimal opponent response to a knock: choose the layoff sequence onto the knocker's
 * melds (order matters when extending runs card by card) and the partition of the kept
 * cards into the opponent's own melds that together minimize the unmelded total. A
 * naive greedy attach can hurt the opponent — e.g. laying off the 5 from a 5-6-7 run
 * onto the knocker's set of 5s strands the 6 and 7 as deadwood.
 */
export function bestLayoff(knockerMelds: Meld[], opponentCards: CardId[]): LayoffResult {
  const cloneMelds = (ms: Meld[]): Meld[] => ms.map((m) => ({ ...m, cards: [...m.cards] }));
  let best: LayoffResult | null = null;
  const visited = new Set<string>();

  function visit(melds: Meld[], remaining: CardId[]): void {
    if (best !== null && best.unmelded === 0) return;
    const key =
      melds.map((m) => m.cards.join(",")).join("|") + "#" + [...remaining].sort().join(",");
    if (visited.has(key)) return;
    visited.add(key);

    const { sum, partition } = bestDeadwood(remaining);
    if (best === null || sum < best.unmelded) {
      best = {
        melds: cloneMelds(melds),
        opponentMelds: cloneMelds(partition.melds),
        opponentDeadwood: [...partition.deadwood],
        unmelded: sum,
      };
    }

    for (let i = 0; i < remaining.length; i++) {
      const card = remaining[i]!;
      for (let mi = 0; mi < melds.length; mi++) {
        const base = melds[mi]!;
        const trialCards =
          base.type === "run"
            ? [...base.cards, card].sort((a, b) => rankOrderLow(a) - rankOrderLow(b))
            : [...base.cards, card];
        const trial: Meld = { type: base.type, cards: trialCards };
        if (!isValidMeld(trial)) continue;
        const nextMelds = melds.map((m, j) => (j === mi ? trial : m));
        visit(
          nextMelds,
          remaining.filter((_, j) => j !== i),
        );
      }
    }
  }

  visit(cloneMelds(knockerMelds), [...opponentCards]);
  return best!;
}
