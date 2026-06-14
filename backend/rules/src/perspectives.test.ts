import { describe, expect, it } from "vitest";
import { buildPerspective, buildPerspectives } from "./perspectives.js";
import type { ServerTruth } from "./types.js";

function makeState(): ServerTruth {
  return {
    version: 1,
    phase: "play",
    handIndex: 0,
    dealer: 1,
    nonDealer: 0,
    scores: [10, 20],
    handsWon: [1, 1],
    raceTarget: 125,
    stock: ["3D", "4D", "6C"],
    discard: ["JS"],
    hands: [
      ["AS", "2S", "3S"],
      ["KC", "KD", "KH"],
    ],
    currentTurn: 0,
    cut: null,
    lastCutResult: null,
    upcardOffer: null,
    knockCheckCard: "JS",
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy: {
      AS: [true, false],
      "2S": [true, false],
      "3S": [true, true] /* seat 1 saw 3S (e.g. it was taken from the discard) */,
      KC: [false, true],
      KD: [false, true],
      KH: [false, true],
      JS: [true, true],
    },
  };
}

describe("buildPerspective hand masking", () => {
  it("shows the viewer their own hand in full", () => {
    const p = buildPerspective(makeState(), 0);
    expect(p.hands[0]).toEqual(["AS", "2S", "3S"]);
  });

  it("hides opponent cards the viewer has not seen, reveals the ones they have", () => {
    const p0 = buildPerspective(makeState(), 0);
    expect(p0.hands[1]).toEqual(["HIDDEN", "HIDDEN", "HIDDEN"]);

    const p1 = buildPerspective(makeState(), 1);
    expect(p1.hands[0]).toEqual(["HIDDEN", "HIDDEN", "3S"]);
  });

  it("never exposes stock contents, only the count", () => {
    const p = buildPerspective(makeState(), 0);
    expect(p.stockCount).toBe(3);
    expect((p as unknown as Record<string, unknown>).stock).toBeUndefined();
  });
});

describe("buildPerspective lastAction masking", () => {
  it("hides a stock-draw face from the non-acting viewer only", () => {
    const s = makeState();
    s.lastAction = { seq: 3, seat: 0, type: "drawStock", card: "6C", pickup: null };
    expect(buildPerspective(s, 0).lastAction?.card).toBe("6C");
    expect(buildPerspective(s, 1).lastAction?.card).toBeNull();
  });

  it("keeps discard faces visible to both viewers", () => {
    const s = makeState();
    s.lastAction = {
      seq: 4,
      seat: 0,
      type: "discard",
      card: "2S",
      pickup: { type: "takeDiscard", card: "JS" },
    };
    expect(buildPerspective(s, 1).lastAction?.card).toBe("2S");
    expect(buildPerspective(s, 1).lastAction?.pickup).toEqual({ type: "takeDiscard", card: "JS" });
  });
});

describe("buildPerspectives", () => {
  it("returns both seats keyed by string seat ids", () => {
    const both = buildPerspectives(makeState());
    expect(both["0"].seat).toBe(0);
    expect(both["1"].seat).toBe(1);
  });

  it("exposes redeal proposals identically to both seats", () => {
    const s = makeState();
    s.redeal = { fromSeat: 1, status: "pending" };
    const views = buildPerspectives(s);
    expect(views["0"].redeal).toEqual({ fromSeat: 1, status: "pending" });
    expect(views["1"].redeal).toEqual({ fromSeat: 1, status: "pending" });
  });
});
