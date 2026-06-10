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

/** Fresh-deal state in the down-card (upcardOffer) phase: seat 0 is non-dealer. */
function makeUpcardOfferState(): ServerTruth {
  const s = makePlayState({
    hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
    hand1: ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"],
    stock: ["3D", "4D", "6C", "7C"],
    discard: ["JS"],
    knockCheckCard: "JS",
  });
  s.phase = "upcardOffer";
  s.upcardOffer = { stage: "nonDealer", nonDealerPassed: false };
  s.currentTurn = 0;
  return s;
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

describe("upcard offer: turn order and the double-pass rule", () => {
  it("non-dealer cannot draw from stock while the dealer is still deciding", () => {
    const s = makeUpcardOfferState();
    const passed = applyIntent(s, { type: "upcardPass", seat: 0 }, () => 0.5);
    expect(passed.ok).toBe(true);
    if (!passed.ok) return;
    expect(passed.state.phase).toBe("upcardOffer");
    expect(passed.state.upcardOffer).toEqual({ stage: "dealer", nonDealerPassed: true });
    expect(passed.state.currentTurn).toBe(1);

    /* Out-of-turn stock draw by the non-dealer must be rejected — the dealer
       still holds the option on the down card. */
    const sneak = applyIntent(passed.state, { type: "drawStock", seat: 0 }, () => 0.5);
    expect(sneak.ok).toBe(false);
    if (sneak.ok) return;
    expect(sneak.error).toMatch(/Cannot draw now/);

    /* The dealer can still take the down card afterwards. */
    const take = applyIntent(passed.state, { type: "upcardTake", seat: 1 }, () => 0.5);
    expect(take.ok).toBe(true);
    if (!take.ok) return;
    expect(take.state.phase).toBe("play");
    expect(take.state.currentTurn).toBe(1);
    expect(take.state.hands[1]).toContain("JS");
  });

  it("after both pass, the non-dealer must draw from the deck (not the refused upcard)", () => {
    const s = makeUpcardOfferState();
    const p0 = applyIntent(s, { type: "upcardPass", seat: 0 }, () => 0.5);
    expect(p0.ok).toBe(true);
    if (!p0.ok) return;
    const p1 = applyIntent(p0.state, { type: "upcardPass", seat: 1 }, () => 0.5);
    expect(p1.ok).toBe(true);
    if (!p1.ok) return;
    expect(p1.state.phase).toBe("play");
    expect(p1.state.currentTurn).toBe(0);
    expect(p1.state.mustDrawFromStock).toBe(0);

    /* Taking the twice-refused upcard is illegal. */
    const take = applyIntent(p1.state, { type: "takeDiscard", seat: 0 }, () => 0.5);
    expect(take.ok).toBe(false);
    if (take.ok) return;
    expect(take.error).toMatch(/must draw from the deck/);

    /* Drawing from the stock clears the restriction and play continues. */
    const draw = applyIntent(p1.state, { type: "drawStock", seat: 0 }, () => 0.5);
    expect(draw.ok).toBe(true);
    if (!draw.ok) return;
    expect(draw.state.mustDrawFromStock).toBeNull();
    expect(draw.state.hands[0]).toHaveLength(11);

    const disc = applyIntent(
      draw.state,
      { type: "discard", seat: 0, card: "5C", knock: false, gin: false },
      () => 0.5,
    );
    expect(disc.ok).toBe(true);
    if (!disc.ok) return;

    /* The dealer may take from the discard pile normally on their turn. */
    const dealerTake = applyIntent(disc.state, { type: "takeDiscard", seat: 1 }, () => 0.5);
    expect(dealerTake.ok).toBe(true);
  });

  it("exposes mustDrawFromStock only to the constrained viewer", async () => {
    const s = makeUpcardOfferState();
    const p0 = applyIntent(s, { type: "upcardPass", seat: 0 }, () => 0.5);
    expect(p0.ok).toBe(true);
    if (!p0.ok) return;
    const p1 = applyIntent(p0.state, { type: "upcardPass", seat: 1 }, () => 0.5);
    expect(p1.ok).toBe(true);
    if (!p1.ok) return;

    const { buildPerspective } = await import("./perspectives.js");
    expect(buildPerspective(p1.state, 0).mustDrawFromStock).toBe(true);
    expect(buildPerspective(p1.state, 1).mustDrawFromStock).toBe(false);
  });
});

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

describe("layoffResolve: defender chooses melds and layoffs (no server optimization)", () => {
  it("applies own melds + layoffs and builds the hand result reveal", () => {
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

    const r = applyIntent(
      k.state,
      {
        type: "layoffResolve",
        seat: 1,
        ownMelds: [
          { type: "run", cards: ["TD", "JD", "QD"] },
          { type: "run", cards: ["2D", "3D", "4D"] },
        ],
        layoffs: [
          { card: "4S", meldIndex: 0 },
          { card: "6H", meldIndex: 1 },
          { card: "KS", meldIndex: 2 },
        ],
      },
      () => 0.5,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    /* Only 2C (2) is unmelded; 2 < knocker's 5 → undercut: (5 - 2) + 25 = 28. */
    expect(r.state.phase).toBe("handOver");
    expect(r.state.lastHandWinner).toBe(1);
    expect(r.state.lastHandPoints).toBe(28);

    const hr = r.state.lastHandResult!;
    expect(hr.kind).toBe("undercut");
    expect(hr.closer).toBe(0);
    expect(hr.winner).toBe(1);
    expect(hr.points).toBe(28);
    expect(hr.layoffs).toEqual([
      { card: "4S", meldIndex: 0 },
      { card: "6H", meldIndex: 1 },
      { card: "KS", meldIndex: 2 },
    ]);
    expect(hr.sides[0].deadwood).toEqual(["5C"]);
    expect(hr.sides[0].deadwoodPoints).toBe(5);
    /* Laid-off cards live inside the knocker's melds. */
    expect(hr.sides[0].melds.flatMap((m) => m.cards)).toContain("4S");
    expect(hr.sides[1].melds).toHaveLength(2);
    expect(hr.sides[1].deadwood).toEqual(["2C"]);
    expect(hr.sides[1].deadwoodPoints).toBe(2);
  });

  it("a suboptimal arrangement stands (skipped layoff counts against the defender)", () => {
    const s = buildKnockReadyState("5S");
    const k = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(k.ok).toBe(true);
    if (!k.ok) return;

    /* Lays off 4S and KS but keeps 6H in hand — optimal play would shed it too. */
    const r = applyIntent(
      k.state,
      {
        type: "layoffResolve",
        seat: 1,
        ownMelds: [],
        layoffs: [
          { card: "4S", meldIndex: 0 },
          { card: "KS", meldIndex: 2 },
        ],
      },
      () => 0.5,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    /* Remaining 6H 2D 3C 4C 5D 8C 8D 9C = 45 → knocker wins 45 - 5 = 40. */
    expect(r.state.lastHandWinner).toBe(0);
    expect(r.state.lastHandPoints).toBe(40);
    expect(r.state.lastHandResult!.kind).toBe("knock");
  });

  it("rejects a layoff card that does not extend the target meld", () => {
    const s = buildKnockReadyState("5S");
    const k = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(k.ok).toBe(true);
    if (!k.ok) return;
    const r = applyIntent(
      k.state,
      { type: "layoffResolve", seat: 1, ownMelds: [], layoffs: [{ card: "8C", meldIndex: 0 }] },
      () => 0.5,
    );
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error).toMatch(/cannot attach/);
  });

  it("rejects invalid or overlapping own melds and cards not in hand", () => {
    const s = buildKnockReadyState("5S");
    const k = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(k.ok).toBe(true);
    if (!k.ok) return;

    const badMeld = applyIntent(
      k.state,
      {
        type: "layoffResolve",
        seat: 1,
        ownMelds: [{ type: "run", cards: ["2D", "3C", "4C"] }],
        layoffs: [],
      },
      () => 0.5,
    );
    expect(badMeld.ok).toBe(false);

    const notInHand = applyIntent(
      k.state,
      { type: "layoffResolve", seat: 1, ownMelds: [], layoffs: [{ card: "AS", meldIndex: 0 }] },
      () => 0.5,
    );
    expect(notInHand.ok).toBe(false);
  });
});

describe("gin builds a full hand result reveal", () => {
  it("includes the ginner's melds and the opponent's optimal partition", () => {
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
    const hr = out.state.lastHandResult!;
    expect(hr.kind).toBe("gin");
    expect(hr.closer).toBe(0);
    expect(hr.winner).toBe(0);
    expect(hr.points).toBe(39);
    expect(hr.sides[0].deadwood).toEqual([]);
    expect(hr.sides[0].deadwoodPoints).toBe(0);
    expect(hr.sides[0].melds.flatMap((m) => m.cards)).toHaveLength(10);
    expect(hr.sides[1].melds).toHaveLength(2);
    expect(hr.sides[1].deadwoodPoints).toBe(14);
    expect([...hr.sides[1].deadwood].sort()).toEqual(["2D", "3D", "4C", "5C"]);
  });
});

describe("seat-scoped ackHandOver requires both players (ready-up)", () => {
  it("waits for both seats before dealing the next hand", () => {
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
    expect(d.state.handOverAcks).toEqual([false, false]);
    expect(d.state.lastHandResult).not.toBeNull();

    const a0 = applyIntent(d.state, { type: "ackHandOver", seat: 0 }, () => 0.5);
    expect(a0.ok).toBe(true);
    if (!a0.ok) return;
    expect(a0.state.phase).toBe("handOver");
    expect(a0.state.handOverAcks).toEqual([true, false]);

    /* Same seat acking again is idempotent. */
    const again = applyIntent(a0.state, { type: "ackHandOver", seat: 0 }, () => 0.5);
    expect(again.ok).toBe(true);
    if (!again.ok) return;
    expect(again.state.phase).toBe("handOver");

    const a1 = applyIntent(again.state, { type: "ackHandOver", seat: 1 }, () => 0.42);
    expect(a1.ok).toBe(true);
    if (!a1.ok) return;
    expect(a1.state.phase).toBe("upcardOffer");
    expect(a1.state.handIndex).toBe(1);
    expect(a1.state.lastHandResult).toBeNull();
    expect(a1.state.handOverAcks).toBeNull();
  });

  it("layoffDone also produces a hand result with computed layoffs", () => {
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
    const hr = d.state.lastHandResult!;
    expect(hr.kind).toBe("knock");
    expect(hr.layoffs.map((l) => l.card).sort()).toEqual(["4S", "6H", "KS"]);
    expect(hr.sides[1].deadwoodPoints).toBe(39);
  });
});

describe("layoffAttach followed by layoffDone", () => {
  it("includes manually attached cards in the hand-result layoffs", () => {
    const s = buildKnockReadyState("5S");
    const k = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(k.ok).toBe(true);
    if (!k.ok) return;

    /* Attach 4S by hand onto the A-2-3 of spades run, then let Done optimize the rest. */
    const runIdx = k.state.knock!.knockerMeldsAfterLayoff.findIndex((m) => m.cards.includes("AS"));
    expect(runIdx).toBeGreaterThanOrEqual(0);
    const att = applyIntent(
      k.state,
      { type: "layoffAttach", seat: 1, card: "4S", meldIndex: runIdx },
      () => 0.5,
    );
    expect(att.ok).toBe(true);
    if (!att.ok) return;
    expect(att.state.knock!.opponentDeadwood).not.toContain("4S");

    const d = applyIntent(att.state, { type: "layoffDone", seat: 1 }, () => 0.5);
    expect(d.ok).toBe(true);
    if (!d.ok) return;

    const hr = d.state.lastHandResult!;
    /* All three laid-off cards appear in the reveal — including the manual 4S. */
    expect(hr.layoffs.map((l) => l.card).sort()).toEqual(["4S", "6H", "KS"]);
    expect(hr.layoffs.find((l) => l.card === "4S")!.meldIndex).toBe(runIdx);
    expect(d.state.lastHandWinner).toBe(0);
    expect(d.state.lastHandPoints).toBe(34);
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

describe("lastAction logging", () => {
  it("records a deck draw + discard with the same pickup story for both perspectives", async () => {
    const s = makePlayState({
      hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
      hand1: ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"],
      stock: ["3D", "4D"],
      discard: ["JS"],
      knockCheckCard: "5S",
    });

    const drew = applyIntent(s, { type: "drawStock", seat: 0 }, () => 0.5);
    expect(drew.ok).toBe(true);
    if (!drew.ok) return;
    expect(drew.state.lastAction).toEqual({
      seq: 1,
      seat: 0,
      type: "drawStock",
      card: "4D",
      pickup: null,
    });

    const { buildPerspective } = await import("./perspectives.js");
    /* The drawer sees the card face; the opponent only learns a deck draw happened. */
    expect(buildPerspective(drew.state, 0).lastAction?.card).toBe("4D");
    expect(buildPerspective(drew.state, 1).lastAction?.card).toBeNull();
    expect(buildPerspective(drew.state, 1).lastAction?.type).toBe("drawStock");

    const disc = applyIntent(
      drew.state,
      { type: "discard", seat: 0, card: "5C", knock: false, gin: false },
      () => 0.5,
    );
    expect(disc.ok).toBe(true);
    if (!disc.ok) return;
    expect(disc.state.lastAction).toEqual({
      seq: 2,
      seat: 0,
      type: "discard",
      card: "5C",
      pickup: { type: "drawStock", card: "4D" },
    });
    /* Both viewers agree: 5C discarded after a deck draw; the drawn face stays hidden from seat 1. */
    const p0 = buildPerspective(disc.state, 0).lastAction;
    const p1 = buildPerspective(disc.state, 1).lastAction;
    expect(p0?.pickup).toEqual({ type: "drawStock", card: "4D" });
    expect(p1?.pickup).toEqual({ type: "drawStock", card: null });
    expect(p0?.card).toBe("5C");
    expect(p1?.card).toBe("5C");
  });

  it("records a discard-pile pickup with the exact card for both viewers", async () => {
    const s = makePlayState({
      hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
      hand1: ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"],
      stock: ["3D", "4D"],
      discard: ["JS"],
      knockCheckCard: "5S",
    });

    const took = applyIntent(s, { type: "takeDiscard", seat: 0 }, () => 0.5);
    expect(took.ok).toBe(true);
    if (!took.ok) return;

    const disc = applyIntent(
      took.state,
      { type: "discard", seat: 0, card: "5C", knock: false, gin: false },
      () => 0.5,
    );
    expect(disc.ok).toBe(true);
    if (!disc.ok) return;

    const { buildPerspective } = await import("./perspectives.js");
    const p0 = buildPerspective(disc.state, 0).lastAction;
    const p1 = buildPerspective(disc.state, 1).lastAction;
    expect(p0).toEqual(p1);
    expect(p1?.pickup).toEqual({ type: "takeDiscard", card: "JS" });
  });

  it("clears lastAction when the next hand deals", () => {
    const s = buildKnockReadyState("5S");
    const ginOut = applyIntent(
      s,
      { type: "discard", seat: 0, card: "6C", knock: true, gin: false },
      () => 0.5,
    );
    expect(ginOut.ok).toBe(true);
    if (!ginOut.ok) return;
    expect(ginOut.state.lastAction?.type).toBe("discard");

    const done = applyIntent(ginOut.state, { type: "layoffDone", seat: 1 }, () => 0.5);
    expect(done.ok).toBe(true);
    if (!done.ok) return;

    const a0 = applyIntent(done.state, { type: "ackHandOver", seat: 0 }, () => 0.5);
    expect(a0.ok).toBe(true);
    if (!a0.ok) return;
    const a1 = applyIntent(a0.state, { type: "ackHandOver", seat: 1 }, () => 0.5);
    expect(a1.ok).toBe(true);
    if (!a1.ok) return;
    expect(a1.state.phase).toBe("upcardOffer");
    expect(a1.state.lastAction ?? null).toBeNull();
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
