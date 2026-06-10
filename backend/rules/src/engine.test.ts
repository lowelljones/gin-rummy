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
function makePlayState(opts: {
  hand0: CardId[];
  hand1: CardId[];
  stock: CardId[];
  discard: CardId[];
  knockCheckCard: CardId;
  scores?: [number, number];
  handsWon?: [number, number];
}): ServerTruth {
  const seenBy: Record<string, [boolean, boolean]> = {};
  for (const c of opts.hand0) seenBy[c] = [true, false];
  for (const c of opts.hand1) seenBy[c] = [false, true];
  for (const c of opts.discard) seenBy[c] = [true, true];

  return {
    version: 1,
    phase: "play",
    handIndex: 0,
    dealer: 1,
    nonDealer: 0,
    scores: opts.scores ?? [0, 0],
    handsWon: opts.handsWon ?? [0, 0],
    raceTarget: 125,
    stock: [...opts.stock],
    discard: [...opts.discard],
    hands: [[...opts.hand0], [...opts.hand1]],
    currentTurn: 0,
    cut: null,
    lastCutResult: null,
    upcardOffer: null,
    knockCheckCard: opts.knockCheckCard,
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy,
  };
}

function buildKnockReadyState(knockCheckCard: CardId = "5S"): ServerTruth {
  return makePlayState({
    hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"],
    hand1: ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"],
    stock: ["3D", "4D"],
    discard: ["JS"],
    knockCheckCard,
  });
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

  it("rejects knock when deadwood is above the knock-card value", () => {
    const s = buildKnockReadyState("3S"); /* knockVal=3, our best deadwood is 5 */
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.error).toMatch(/Knock requires deadwood exactly 3/);
  });

  it("rejects knock when deadwood is below the knock-card value (equality knock)", () => {
    /* knockCheckCard=TS → knockVal=10; best deadwood is 5, must equal 10 to knock. */
    const s = buildKnockReadyState("TS");
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.error).toMatch(/Knock requires deadwood exactly 10/);
  });

  it("rejects knock when deadwood is strictly less than knock value", () => {
    const s = buildKnockReadyState("7S"); /* knockVal=7, best deadwood is 5 */
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.error).toMatch(/Knock requires deadwood exactly 7/);
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
    expect(out.error).toMatch(/first upcard is an Ace/);
  });

  it("forbids knock on Ace first upcard even when unmelded would be exactly 1", () => {
    const s = makePlayState({
      hand0: ["2S", "3S", "4S", "5H", "6H", "7H", "8D", "8C", "8S", "AH", "2C"],
      hand1: ["9S", "TS", "JS", "QS", "KS", "3D", "4D", "5D", "6D", "7D"],
      stock: ["9C", "TD"],
      discard: ["AS"],
      knockCheckCard: "AS",
    });

    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "2C", knock: true, gin: false },
      () => 0.5,
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.error).toMatch(/first upcard is an Ace/);
  });
});

describe("gin and EO score only the opponent's unmelded cards", () => {
  it("gin awards 25 + opponent unmelded (opponent's own melds don't count)", () => {
    const s = makePlayState({
      hand0: ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S", "KD"],
      hand1: ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      stock: ["6D", "7D"],
      discard: ["KS"],
      knockCheckCard: "KS",
    });
    const out = applyIntent(
      s,
      { type: "discard", seat: 0, card: "KD", knock: false, gin: true },
      () => 0.5,
    );
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    /* Opponent melds 9S-TS-JS and QC/QD/QH; unmelded 2D+3D+4C+5C = 14 → 25 + 14 = 39. */
    expect(out.state.phase).toBe("handOver");
    expect(out.state.lastHandWinner).toBe(0);
    expect(out.state.lastHandPoints).toBe(39);
    expect(out.state.scores).toEqual([39, 0]);
  });

  it("EO (11-card gin) awards 50 + opponent unmelded", () => {
    const s = makePlayState({
      hand0: ["2S", "3S", "4S", "5H", "6H", "7H", "8H", "9C", "9D", "9H", "9S"],
      hand1: ["TS", "JS", "QS", "KC", "KD", "KH", "AD", "2D", "3C", "4C"],
      stock: ["5D", "6D"],
      discard: ["TD"],
      knockCheckCard: "TD",
    });
    const out = applyIntent(s, { type: "declareBigGin", seat: 0 }, () => 0.5);
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    /* Opponent melds TS-JS-QS and KC/KD/KH; unmelded AD+2D+3C+4C = 10 → 50 + 10 = 60. */
    expect(out.state.phase).toBe("handOver");
    expect(out.state.lastHandWinner).toBe(0);
    expect(out.state.lastHandPoints).toBe(60);
    expect(out.state.scores).toEqual([60, 0]);
  });
});

describe("knock resolution counts only true unmelded totals", () => {
  it("undercut: opponent lower after layoffs and own melds wins difference + 25 Cut", () => {
    const s = makePlayState({
      hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"],
      hand1: ["4S", "6H", "KS", "TD", "JD", "QD", "2D", "3D", "4D", "2C"],
      stock: ["9C", "TC"],
      discard: ["JS"],
      knockCheckCard: "5S",
    });
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
    /* 4S/6H/KS lay off onto the knocker's melds; TD-JD-QD and 2D-3D-4D are the
       opponent's own melds; only 2C (2) is unmelded. 2 < knocker's 5 → opponent
       wins (5 - 2) + 25 Cut = 28. */
    expect(d.state.phase).toBe("handOver");
    expect(d.state.lastHandWinner).toBe(1);
    expect(d.state.lastHandPoints).toBe(28);
    expect(d.state.scores).toEqual([0, 28]);
  });

  it("does not lay off a card when keeping the opponent's own meld is better", () => {
    const s = makePlayState({
      hand0: ["5C", "5D", "5H", "9H", "TH", "JH", "KC", "KD", "KH", "7C", "2C"],
      hand1: ["5S", "6S", "7S", "2D", "3D", "4D", "8C", "9C", "TC", "QD"],
      stock: ["3H", "4H"],
      discard: ["8D"],
      knockCheckCard: "7D",
    });
    const k = applyIntent(
      s,
      { type: "discard", seat: 0, card: "2C", knock: true, gin: false },
      () => 0.5,
    );
    expect(k.ok).toBe(true);
    if (!k.ok) return;
    const d = applyIntent(k.state, { type: "layoffDone", seat: 1 }, () => 0.5);
    expect(d.ok).toBe(true);
    if (!d.ok) return;
    /* 5S could attach to the knocker's 5C/5D/5H set, but that would strand 6S+7S (13).
       Keeping the 5S-6S-7S run leaves only QD (10) unmelded → knocker wins 10 - 7 = 3. */
    expect(d.state.lastHandWinner).toBe(0);
    expect(d.state.lastHandPoints).toBe(3);
    expect(d.state.scores).toEqual([3, 0]);
  });
});

describe("match end at 125 with betting settlement", () => {
  it("crossing the race target sets matchOver and computes raw/bucket", () => {
    const s = buildKnockReadyState("5S");
    s.scores = [100, 20];
    s.handsWon = [2, 1];
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
    /* +34 → 134 ≥ 125. Raw = (134 - 20) + 100 + 25 × (3 - 1) = 264 → bucket 3. */
    expect(d.state.phase).toBe("matchOver");
    expect(d.state.scores).toEqual([134, 20]);
    expect(d.state.handsWon).toEqual([3, 1]);
    expect(d.state.bettingRaw).toBe(264);
    expect(d.state.bettingBucket).toBe(3);

    const ack = applyIntent(d.state, { type: "ackHandOver" }, () => 0.5);
    expect(ack.ok).toBe(false);
    if (ack.ok) return;
    expect(ack.error).toMatch(/Match is over/);
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

describe("mutual redeal", () => {
  it("accepting voids the hand and returns to down-card phase at the same hand index", () => {
    const s = buildKnockReadyState("5S");
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    expect(prop.state.redeal).toEqual({ fromSeat: 0, status: "pending" });

    const acc = applyIntent(prop.state, { type: "respondRedeal", seat: 1, accept: true }, () => 0.99);
    expect(acc.ok).toBe(true);
    if (!acc.ok) return;
    expect(acc.state.redeal).toBeNull();
    expect(acc.state.phase).toBe("upcardOffer");
    expect(acc.state.handIndex).toBe(0);
    expect(acc.state.dealer).toBe(1);
    expect(acc.state.nonDealer).toBe(0);
    expect(acc.state.hands[0]).toHaveLength(10);
    expect(acc.state.hands[1]).toHaveLength(10);
    expect(acc.state.discard).toHaveLength(1);
    expect(acc.state.knock).toBeNull();
  });

  it("blocks normal play until the opponent responds", () => {
    const s = buildKnockReadyState("5S");
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const bad = applyIntent(prop.state, { type: "discard", seat: 0, card: "6C", knock: false, gin: false }, () => 0.5);
    expect(bad.ok).toBe(false);
  });

  it("decline leaves a declined marker until ordinary play resumes", () => {
    const s = buildKnockReadyState("5S");
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const dec = applyIntent(prop.state, { type: "respondRedeal", seat: 1, accept: false }, () => 0.5);
    expect(dec.ok).toBe(true);
    if (!dec.ok) return;
    expect(dec.state.redeal).toEqual({ fromSeat: 0, status: "declined" });

    const again = applyIntent(dec.state, { type: "discard", seat: 0, card: "6C", knock: false, gin: false }, () => 0.5);
    expect(again.ok).toBe(true);
    if (!again.ok) return;
    expect(again.state.redeal).toBeNull();
  });
});
