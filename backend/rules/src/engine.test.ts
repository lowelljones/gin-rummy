import { describe, expect, it } from "vitest";
import type { CardId } from "./cards.js";
import { applyIntent } from "./engine.js";
import type { ServerTruth } from "./types.js";

/**
 * Build a synthetic mid-hand state where seat 0 holds 11 cards and is poised to
 * knock by discarding `6C`. After that discard, the only optimal partition has
 * deadwood exactly 5, matching `knockCheckCard = 5S` (knock value 5).
 *
 *   Seat 0 (11): AS 2S 3S | 7H 8H 9H | KC KD KH | 5C 6C
 *   Seat 1 (10): 4S 6H KS  2D 3C 4C 5D 8C 8D 9C
 *
 * Seat 1's `4S`, `6H`, `KS` should auto-lay-off onto seat 0's three melds when
 * seat 1 ends layoff; the rest stay deadwood (sum 39 vs knocker's 5 → knocker
 * wins by 34).
 */
function buildKnockReadyState(knockCheckCard: CardId = "5S"): ServerTruth {
  const hand0: CardId[] = [
    "AS",
    "2S",
    "3S",
    "7H",
    "8H",
    "9H",
    "KC",
    "KD",
    "KH",
    "5C",
    "6C",
  ];
  const hand1: CardId[] = [
    "4S",
    "6H",
    "KS",
    "2D",
    "3C",
    "4C",
    "5D",
    "8C",
    "8D",
    "9C",
  ];
  const seenBy: Record<string, [boolean, boolean]> = {};
  for (const c of hand0) seenBy[c] = [true, false];
  for (const c of hand1) seenBy[c] = [false, true];
  seenBy["JS"] = [true, true];

  return {
    version: 1,
    phase: "play",
    handIndex: 0,
    dealer: 1,
    nonDealer: 0,
    scores: [0, 0],
    handsWon: [0, 0],
    raceTarget: 125,
    stock: ["3D", "4D"],
    discard: ["JS"],
    hands: [hand0, hand1],
    currentTurn: 0,
    cut: null,
    lastCutResult: null,
    upcardOffer: null,
    knockCheckCard,
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy,
  };
}

describe("knock without explicit layout", () => {
  it("server fills in the optimal layout when client omits it", () => {
    const s = buildKnockReadyState("5S");
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    expect(out.state.phase).toBe("knockLayoff");
    expect(out.state.knock).not.toBeNull();
    expect(out.state.knock!.knocker).toBe(0);
    expect(out.state.knock!.layoffTurn).toBe(1);
    expect(out.state.knock!.knockerDeadwood).toEqual(["5C"]);
    expect(out.state.knock!.knockerMelds).toHaveLength(3);
    /* Knocker hand is now the 10 melded+deadwood cards (6C went to discard). */
    expect(out.state.hands[0]).toHaveLength(10);
    expect(out.state.hands[0]).not.toContain("6C");
    expect(out.state.discard.at(-1)).toBe("6C");
  });

  it("rejects knock when the best layout exceeds the knock-card value", () => {
    const s = buildKnockReadyState("3S"); /* knockVal=3, our best deadwood is 5 */
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.error).toMatch(/Knock requires deadwood ≤ 3/);
  });

  it("allows knock when the best layout's deadwood is strictly below the knock-card value", () => {
    /* knockCheckCard=TS → knockVal=10; our best deadwood is 5, so 5 ≤ 10 should knock cleanly. */
    const s = buildKnockReadyState("TS");
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    expect(out.state.phase).toBe("knockLayoff");
    expect(out.state.knock!.knockerDeadwood).toEqual(["5C"]);
  });

  it("forbids knocking when the knock card is an Ace", () => {
    const s = buildKnockReadyState("AH"); /* upcardKnockValue(Ace) → null */
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.error).toMatch(/Ace/);
  });
});

describe("layoffDone applies legal layoffs greedily before resolving", () => {
  it("attaches opponent's 4S/6H/KS onto the knocker's melds, then awards 34 to the knocker", () => {
    const s = buildKnockReadyState("5S");
    const knockOut = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(knockOut.ok).toBe(true);
    if (!knockOut.ok) return;

    const doneOut = applyIntent(
      knockOut.state,
      { type: "layoffDone", seat: 1 },
      () => 0.5,
    );
    expect(doneOut.ok).toBe(true);
    if (!doneOut.ok) return;

    /* Match isn't over (34 < 125), so we land on handOver with seat 0 winning. */
    expect(doneOut.state.phase).toBe("handOver");
    expect(doneOut.state.lastHandWinner).toBe(0);
    expect(doneOut.state.lastHandPoints).toBe(34);
    expect(doneOut.state.scores).toEqual([34, 0]);
    expect(doneOut.state.knock).toBeNull();
    expect(doneOut.state.hands[0]).toEqual([]);
    expect(doneOut.state.hands[1]).toEqual([]);
  });
});

describe("ackHandOver advances to the next deal until match end", () => {
  it("after a handOver awaits ack, then deals the next hand", () => {
    const s = buildKnockReadyState("5S");
    const k = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(k.ok).toBe(true);
    if (!k.ok) return;
    const d = applyIntent(k.state, { type: "layoffDone", seat: 1 }, () => 0.5);
    expect(d.ok).toBe(true);
    if (!d.ok) return;
    expect(d.state.phase).toBe("handOver");

    const ack = applyIntent(d.state, { type: "ackHandOver" }, () => 0.42);
    expect(ack.ok).toBe(true);
    if (!ack.ok) return;
    /* Winner of the prior hand (seat 0) deals the next; non-dealer leads upcardOffer. */
    expect(ack.state.phase).toBe("upcardOffer");
    expect(ack.state.handIndex).toBe(1);
    expect(ack.state.dealer).toBe(0);
    expect(ack.state.nonDealer).toBe(1);
    expect(ack.state.currentTurn).toBe(1);
    expect(ack.state.hands[0]).toHaveLength(10);
    expect(ack.state.hands[1]).toHaveLength(10);
    expect(ack.state.discard).toHaveLength(1);
  });
});
