import { describe, expect, it } from "vitest";
import { applyIntent } from "../../rules/src/engine.js";
import { buildPerspectives } from "../../rules/src/perspectives.js";
import type { ServerTruth } from "../../rules/src/types.js";
import { computeTestBotIntent } from "./bot.js";
import { detectHandEpisodeClose } from "./handEpisode.js";

function buildKnockReadyState(): ServerTruth {
  const seenBy: Record<string, [boolean, boolean]> = {};
  const hand0 = ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"];
  const hand1 = ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"];
  for (const c of hand0) seenBy[c] = [true, false];
  for (const c of hand1) seenBy[c] = [false, true];
  seenBy.JS = [true, true];

  return {
    version: 1,
    phase: "play",
    handIndex: 0,
    dealIndex: 0,
    currentDeal: null,
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
    knockCheckCard: "5S",
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    lastHandResult: null,
    handOverAcks: null,
    lastAction: null,
    turnPickup: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy,
    redeal: null,
    voidFlash: null,
  };
}

describe("redeal API-adjacent flows", () => {
  it("records a mutualRedeal hand episode when accepted", () => {
    const prev = buildKnockReadyState();
    prev.currentDeal = {
      dealIndex: prev.dealIndex,
      handIndex: prev.handIndex,
      dealer: prev.dealer,
      nonDealer: prev.nonDealer,
      knockCheckCard: prev.knockCheckCard,
      openingHands: [[...prev.hands[0]], [...prev.hands[1]]],
      scoresAtStart: [...prev.scores] as [number, number],
      startedAtMoveSeq: 10,
    };
    const prop = applyIntent(prev, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;

    const next = applyIntent(prop.state, { type: "respondRedeal", seat: 1, accept: true }, () => 0.77);
    expect(next.ok).toBe(true);
    if (!next.ok) return;

    const row = detectHandEpisodeClose(
      "game-1",
      prop.state,
      next.state,
      { type: "respondRedeal", seat: 1, accept: true },
      99,
    );
    expect(row).not.toBeNull();
    expect(row!.outcome).toBe("mutualRedeal");
    expect(row!.points_awarded).toBe(0);
  });

  it("does not record an episode on cancelRedeal", () => {
    const prev = buildKnockReadyState();
    const prop = applyIntent(prev, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;

    const next = applyIntent(prop.state, { type: "cancelRedeal", seat: 0 }, () => 0.5);
    expect(next.ok).toBe(true);
    if (!next.ok) return;

    const row = detectHandEpisodeClose(
      "game-1",
      prop.state,
      next.state,
      { type: "cancelRedeal", seat: 0 },
      50,
    );
    expect(row).toBeNull();
  });

  it("bot auto-accepts a human redeal proposal", () => {
    const s = buildKnockReadyState();
    s.redeal = { fromSeat: 0, status: "pending" };
    expect(computeTestBotIntent(s)).toEqual({ type: "respondRedeal", seat: 1, accept: true });
  });

  it("bot does not respond to its own pending redeal", () => {
    const s = buildKnockReadyState();
    s.redeal = { fromSeat: 1, status: "pending" };
    expect(computeTestBotIntent(s)).toBeNull();
  });

  it("perspectives stay in sync through propose → cancel", () => {
    const prev = buildKnockReadyState();
    const prop = applyIntent(prev, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;

    const mid = buildPerspectives(prop.state);
    expect(mid["0"].redeal).toEqual(mid["1"].redeal);

    const next = applyIntent(prop.state, { type: "cancelRedeal", seat: 0 }, () => 0.5);
    expect(next.ok).toBe(true);
    if (!next.ok) return;

    const after = buildPerspectives(next.state);
    expect(after["0"].redeal).toBeNull();
    expect(after["1"].redeal).toBeNull();
  });
});
