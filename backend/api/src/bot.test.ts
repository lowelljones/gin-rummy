import { describe, expect, it } from "vitest";
import type { CardId, ServerTruth } from "../../rules/src/index.js";
import { applyIntent } from "../../rules/src/index.js";
import { computeTestBotIntent, getTestBotSeat, hasTestBotWork } from "./bot.js";

const BOT = getTestBotSeat(); /* seat 1 */

function makeBotTurnState(opts: {
  botHand: CardId[];
  humanHand: CardId[];
  stock: CardId[];
  discard: CardId[];
}): ServerTruth {
  return {
    version: 1,
    phase: "play",
    handIndex: 0,
    dealer: 0,
    nonDealer: 1,
    scores: [0, 0],
    handsWon: [0, 0],
    raceTarget: 125,
    stock: [...opts.stock],
    discard: [...opts.discard],
    hands: [[...opts.humanHand], [...opts.botHand]],
    currentTurn: BOT,
    cut: null,
    lastCutResult: null,
    upcardOffer: null,
    knockCheckCard: opts.discard[0] ?? null,
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy: {},
  };
}

const HUMAN_HAND: CardId[] = ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"];

describe("computeTestBotIntent in play phase", () => {
  it("draws from stock with 10 cards", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
      humanHand: HUMAN_HAND,
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    expect(hasTestBotWork(s)).toBe(true);
    expect(computeTestBotIntent(s)).toEqual({ type: "drawStock", seat: BOT });
  });

  it("declares big gin when all 11 cards meld", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "4S", "7H", "8H", "9H", "KC", "KD", "KH", "KS"],
      humanHand: ["6H", "2D", "3C", "4C", "5D", "8C", "8D", "9C", "TD", "JD"],
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    expect(computeTestBotIntent(s)).toEqual({ type: "declareBigGin", seat: BOT });
  });

  it("declares gin (not a plain discard) when one discard reaches zero deadwood", () => {
    /* Discarding 4C gins: A-2-3S, 7-8-9H, KC/KD/KH/KS. A plain discard would be
       rejected by the engine here, wedging the bot game forever. */
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "KS", "4C"],
      humanHand: ["6H", "2D", "3C", "5C", "5D", "8C", "8D", "9C", "TD", "JD"],
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    const intent = computeTestBotIntent(s);
    expect(intent).toEqual({ type: "discard", seat: BOT, card: "4C", knock: false, gin: true });

    /* And the engine accepts it. */
    const out = applyIntent(s, intent!, () => 0.5);
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    expect(out.state.phase).toBe("handOver");
    expect(out.state.lastHandWinner).toBe(BOT);
  });

  it("falls back to discarding the drawn (last) card with 11 cards and no gin", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "9D"],
      humanHand: HUMAN_HAND,
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    const intent = computeTestBotIntent(s);
    expect(intent).toEqual({ type: "discard", seat: BOT, card: "9D", knock: false, gin: false });
    const out = applyIntent(s, intent!, () => 0.5);
    expect(out.ok).toBe(true);
  });
});

describe("computeTestBotIntent outside its turn", () => {
  it("does nothing when it is the human's turn", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
      humanHand: HUMAN_HAND,
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    s.currentTurn = 0;
    expect(hasTestBotWork(s)).toBe(false);
    expect(computeTestBotIntent(s)).toBeNull();
  });

  it("acks its own seat once during handOver, then waits for the human", () => {
    const s = makeBotTurnState({
      botHand: [],
      humanHand: [],
      stock: [],
      discard: ["JS"],
    });
    s.phase = "handOver";
    s.lastHandWinner = 0;
    s.lastHandPoints = 10;
    s.handOverAcks = [false, false];
    expect(computeTestBotIntent(s)).toEqual({ type: "ackHandOver", seat: BOT });

    s.handOverAcks = [false, true];
    expect(hasTestBotWork(s)).toBe(false);
    expect(computeTestBotIntent(s)).toBeNull();
  });

  it("accepts a redeal proposed by the human", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
      humanHand: HUMAN_HAND,
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    s.currentTurn = 0;
    s.redeal = { fromSeat: 0, status: "pending" };
    expect(hasTestBotWork(s)).toBe(true);
    expect(computeTestBotIntent(s)).toEqual({ type: "respondRedeal", seat: BOT, accept: true });
  });
});
