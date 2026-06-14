import { describe, expect, it } from "vitest";
import { applyIntent } from "../../rules/src/engine.js";
import type { ServerTruth } from "../../rules/src/types.js";
import {
  detectHandEpisodeClose,
  moveAnalyticsFields,
  stampDealStartMoveSeq,
} from "./handEpisode.js";

function makePlayState(opts: {
  hand0: string[];
  hand1: string[];
  stock: string[];
  discard: string[];
  knockCheckCard: string;
  scores?: [number, number];
}): ServerTruth {
  const seenBy: Record<string, [boolean, boolean]> = {};
  for (const c of opts.hand0) seenBy[c] = [true, false];
  for (const c of opts.hand1) seenBy[c] = [false, true];
  for (const c of opts.discard) seenBy[c] = [true, true];

  return {
    version: 1,
    phase: "play",
    handIndex: 2,
    dealIndex: 3,
    currentDeal: {
      dealIndex: 3,
      handIndex: 2,
      dealer: 1,
      nonDealer: 0,
      knockCheckCard: opts.knockCheckCard as ServerTruth["knockCheckCard"],
      openingHands: [[...opts.hand0], [...opts.hand1]],
      scoresAtStart: opts.scores ?? [40, 35],
      startedAtMoveSeq: 10,
    },
    dealer: 1,
    nonDealer: 0,
    scores: opts.scores ?? [40, 35],
    handsWon: [1, 1],
    raceTarget: 125,
    stock: [...opts.stock],
    discard: [...opts.discard],
    hands: [[...opts.hand0], [...opts.hand1]],
    currentTurn: 0,
    cut: null,
    upcardOffer: null,
    knockCheckCard: opts.knockCheckCard as ServerTruth["knockCheckCard"],
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy,
    voidFlash: null,
  };
}

describe("detectHandEpisodeClose", () => {
  it("records playedThrough with deal_index and hand_index", () => {
    const prev = makePlayState({
      hand0: ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S"],
      hand1: ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      stock: ["6D"],
      discard: ["KS", "KD"],
      knockCheckCard: "KS",
    });
    prev.currentTurn = 1;
    const out = applyIntent(prev, { type: "passStock", seat: 1 }, () => 0.99);
    expect(out.ok).toBe(true);
    if (!out.ok) return;

    const row = detectHandEpisodeClose("game-1", prev, out.state, { type: "passStock", seat: 1 }, 42);
    expect(row).not.toBeNull();
    expect(row!.outcome).toBe("playedThrough");
    expect(row!.deal_index).toBe(3);
    expect(row!.hand_index).toBe(2);
    expect(row!.started_at_move_seq).toBe(10);
    expect(row!.ended_at_move_seq).toBe(42);
  });

  it("records gin with result payload and score delta", () => {
    const prev = makePlayState({
      hand0: ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S", "KD"],
      hand1: ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      stock: ["6D", "7D"],
      discard: ["KS"],
      knockCheckCard: "KS",
    });
    const out = applyIntent(
      prev,
      { type: "discard", seat: 0, card: "KD", knock: false, gin: true },
      () => 0.5,
    );
    expect(out.ok).toBe(true);
    if (!out.ok) return;

    const row = detectHandEpisodeClose(
      "game-1",
      prev,
      out.state,
      { type: "discard", seat: 0, card: "KD", knock: false, gin: true },
      7,
    );
    expect(row?.outcome).toBe("gin");
    expect(row?.winner_seat).toBe(0);
    expect(row?.points_awarded).toBeGreaterThan(0);
    expect(row?.result).not.toBeNull();
  });
});

describe("moveAnalyticsFields", () => {
  it("captures pre-move deal and scoreboard context", () => {
    const prev = makePlayState({
      hand0: ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S"],
      hand1: ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      stock: ["6D", "7D"],
      discard: ["KS"],
      knockCheckCard: "KS",
    });
    prev.dealIndex = 5;
    prev.handIndex = 2;
    prev.phase = "play";
    const fields = moveAnalyticsFields(prev, { type: "drawStock", seat: 0 });
    expect(fields).toEqual({
      actor_seat: 0,
      deal_index: 5,
      hand_index: 2,
      phase: "play",
      stock_count: 2,
    });
  });
});

describe("stampDealStartMoveSeq", () => {
  it("sets startedAtMoveSeq on the first move of a deal", () => {
    const truth: ServerTruth = {
      ...makePlayState({
        hand0: ["2S"],
        hand1: ["3S"],
        stock: ["4S"],
        discard: ["KS"],
        knockCheckCard: "KS",
      }),
      currentDeal: {
        dealIndex: 1,
        handIndex: 0,
        dealer: 0,
        nonDealer: 1,
        knockCheckCard: "KS",
        openingHands: [[], []],
        scoresAtStart: [0, 0],
        startedAtMoveSeq: null,
      },
    };
    const stamped = stampDealStartMoveSeq(truth, 99);
    expect(stamped.currentDeal?.startedAtMoveSeq).toBe(99);
    expect(stampDealStartMoveSeq(stamped, 100).currentDeal?.startedAtMoveSeq).toBe(99);
  });
});
