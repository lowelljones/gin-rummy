import { describe, expect, it } from "vitest";
import type { CardId, ServerTruth } from "../../rules/src/index.js";
import { applyIntent } from "../../rules/src/index.js";
import { computeTestBotIntent, fallbackTestBotIntent, getTestBotSeat, hasTestBotWork } from "./bot.js";

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

  it("plain-discards even when a gin discard is available (dumb bot does not declare gin)", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "KS", "4C"],
      humanHand: ["6H", "2D", "3C", "5C", "5D", "8C", "8D", "9C", "TD", "JD"],
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    const intent = computeTestBotIntent(s);
    expect(intent).toEqual({ type: "discard", seat: BOT, card: "4C", knock: false, gin: false });

    const out = applyIntent(s, intent!, () => 0.5);
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    expect(out.state.phase).toBe("play");
    expect(out.state.currentTurn).toBe(0);
  });

  it("passes on the discard when only one stock card remains", () => {
    const s = makeBotTurnState({
      botHand: ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      humanHand: HUMAN_HAND,
      stock: ["6D"],
      discard: ["JS", "KD"],
    });
    s.currentTurn = BOT;
    expect(computeTestBotIntent(s)).toEqual({ type: "passStock", seat: BOT });
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

  it("discards when phase is upcardOffer but the offer object is missing (legacy row)", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "9D"],
      humanHand: HUMAN_HAND,
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    s.phase = "upcardOffer";
    s.upcardOffer = null;
    expect(hasTestBotWork(s)).toBe(true);
    expect(computeTestBotIntent(s)).toEqual({ type: "discard", seat: BOT, card: "9D", knock: false, gin: false });
    const out = applyIntent(s, computeTestBotIntent(s)!, () => 0.5);
    expect(out.ok).toBe(true);
  });

  it("falls back to plain discard when EO declaration would fail", () => {
    const s = makeBotTurnState({
      botHand: ["AS", "2S", "3S", "4S", "7H", "8H", "9H", "KC", "KD", "KH", "KS"],
      humanHand: HUMAN_HAND,
      stock: ["3D", "4D"],
      discard: ["JS"],
    });
    s.phase = "knockLayoff";
    const failed = computeTestBotIntent(s);
    expect(fallbackTestBotIntent(s, failed ?? { type: "declareBigGin", seat: BOT })).toBeNull();
    s.phase = "play";
    const eo = computeTestBotIntent(s);
    expect(eo).toEqual({ type: "declareBigGin", seat: BOT });
    expect(fallbackTestBotIntent(s, eo!)).toEqual({
      type: "discard",
      seat: BOT,
      card: "KS",
      knock: false,
      gin: false,
    });
  });
});

const HUMAN = 0;

function advanceBot(state: ServerTruth): ServerTruth {
  for (let i = 0; i < 40; i++) {
    if (!hasTestBotWork(state)) return state;
    const intent = computeTestBotIntent(state);
    if (!intent) {
      throw new Error(
        `bot stall: phase=${state.phase} turn=${state.currentTurn} botHand=${state.hands[BOT].length} upcard=${JSON.stringify(state.upcardOffer)}`,
      );
    }
    const out = applyIntent(state, intent, () => 0.42);
    expect(out.ok).toBe(true);
    if (!out.ok) return state;
    state = out.state;
  }
  throw new Error("bot max steps");
}

describe("bot completes turn after played-through then mutual redeal", () => {
  it("draws and discards when human leads after both pass the down card", () => {
    let s: ServerTruth = {
      version: 1,
      phase: "play",
      handIndex: 2,
      dealIndex: 3,
      dealer: 1,
      nonDealer: 0,
      scores: [30, 40],
      handsWon: [1, 1],
      raceTarget: 125,
      stock: ["6D"],
      discard: ["KS", "KD"],
      hands: [
        ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S"],
        ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      ],
      currentTurn: 1,
      cut: null,
      lastCutResult: null,
      upcardOffer: null,
      knockCheckCard: "KS",
      knock: null,
      lastHandWinner: null,
      lastHandPoints: null,
      lastHandResult: null,
      handOverAcks: null,
      bettingRaw: null,
      bettingBucket: null,
      seenBy: {},
      redeal: null,
      voidFlash: null,
      currentDeal: null,
      lastAction: null,
      turnPickup: null,
    };

    const played = applyIntent(s, { type: "passStock", seat: 1 }, () => 0.99);
    expect(played.ok).toBe(true);
    if (!played.ok) return;
    s = played.state;
    expect(s.phase).toBe("upcardOffer");
    expect(s.voidFlash).toBe("playedThrough");

    const prop = applyIntent(s, { type: "proposeRedeal", seat: HUMAN }, () => 0.42);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    s = advanceBot(prop.state);

    expect(s.phase).toBe("upcardOffer");
    expect(s.redeal).toBeNull();
    expect(s.hands[HUMAN]).toHaveLength(10);
    expect(s.hands[BOT]).toHaveLength(10);

    if (s.currentTurn === HUMAN) {
      const pass = applyIntent(s, { type: "upcardPass", seat: HUMAN }, () => 0.42);
      expect(pass.ok).toBe(true);
      if (!pass.ok) return;
      s = pass.state;
    }
    s = advanceBot(s);
    expect(s.phase).toBe("play");

    if (s.currentTurn !== HUMAN) {
      s = advanceBot(s);
    }
    expect(s.currentTurn).toBe(HUMAN);

    const draw = applyIntent(s, { type: "drawStock", seat: HUMAN }, () => 0.42);
    expect(draw.ok).toBe(true);
    if (!draw.ok) return;
    s = draw.state;
    expect(s.hands[HUMAN]).toHaveLength(11);

    const card = s.hands[HUMAN][s.hands[HUMAN].length - 1]!;
    const disc = applyIntent(s, { type: "discard", seat: HUMAN, card, knock: false, gin: false }, () => 0.42);
    expect(disc.ok).toBe(true);
    if (!disc.ok) return;
    s = disc.state;
    expect(s.currentTurn).toBe(BOT);
    expect(s.hands[BOT]).toHaveLength(10);

    s = advanceBot(s);
    expect(s.hands[BOT]).toHaveLength(10);
    expect(s.currentTurn).toBe(HUMAN);
  });

  it("draws and discards after human took the twice-refused upcard then discarded", () => {
    let s: ServerTruth = {
      version: 1,
      phase: "play",
      handIndex: 2,
      dealIndex: 3,
      dealer: 1,
      nonDealer: 0,
      scores: [30, 40],
      handsWon: [1, 1],
      raceTarget: 125,
      stock: ["6D"],
      discard: ["KS", "KD"],
      hands: [
        ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S"],
        ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      ],
      currentTurn: 1,
      cut: null,
      lastCutResult: null,
      upcardOffer: null,
      knockCheckCard: "KS",
      knock: null,
      lastHandWinner: null,
      lastHandPoints: null,
      lastHandResult: null,
      handOverAcks: null,
      bettingRaw: null,
      bettingBucket: null,
      seenBy: {},
      redeal: null,
      voidFlash: null,
      currentDeal: null,
      lastAction: null,
      turnPickup: null,
    };

    const played = applyIntent(s, { type: "passStock", seat: 1 }, () => 0.99);
    expect(played.ok).toBe(true);
    if (!played.ok) return;
    s = played.state;

    const prop = applyIntent(s, { type: "proposeRedeal", seat: HUMAN }, () => 0.42);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    s = advanceBot(prop.state);

    if (s.currentTurn === HUMAN) {
      const pass = applyIntent(s, { type: "upcardPass", seat: HUMAN }, () => 0.42);
      expect(pass.ok).toBe(true);
      if (!pass.ok) return;
      s = pass.state;
    }
    s = advanceBot(s);
    expect(s.phase).toBe("play");
    expect(s.currentTurn).toBe(HUMAN);

    const take = applyIntent(s, { type: "takeDiscard", seat: HUMAN }, () => 0.42);
    expect(take.ok).toBe(true);
    if (!take.ok) return;
    s = take.state;
    expect(s.hands[HUMAN]).toHaveLength(11);

    const card = s.hands[HUMAN][s.hands[HUMAN].length - 1]!;
    const disc = applyIntent(s, { type: "discard", seat: HUMAN, card, knock: false, gin: false }, () => 0.42);
    expect(disc.ok).toBe(true);
    if (!disc.ok) return;
    s = disc.state;
    expect(s.currentTurn).toBe(BOT);
    expect(s.hands[BOT]).toHaveLength(10);

    s = advanceBot(s);
    expect(s.hands[BOT]).toHaveLength(10);
    expect(s.currentTurn).toBe(HUMAN);
  });

  it("never stalls across many shuffles", () => {
    for (let seed = 0; seed < 80; seed++) {
      const rng = () => {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed / 0x7fffffff;
      };
      let s: ServerTruth = {
        version: 1,
        phase: "play",
        handIndex: 2,
        dealIndex: 3,
        dealer: 1,
        nonDealer: 0,
        scores: [30, 40],
        handsWon: [1, 1],
        raceTarget: 125,
        stock: ["6D"],
        discard: ["KS", "KD"],
        hands: [
          ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S"],
          ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
        ],
        currentTurn: 1,
        cut: null,
        lastCutResult: null,
        upcardOffer: null,
        knockCheckCard: "KS",
        knock: null,
        lastHandWinner: null,
        lastHandPoints: null,
        lastHandResult: null,
        handOverAcks: null,
        bettingRaw: null,
        bettingBucket: null,
        seenBy: {},
        redeal: null,
        voidFlash: null,
        currentDeal: null,
        lastAction: null,
        turnPickup: null,
      };

      const played = applyIntent(s, { type: "passStock", seat: 1 }, rng);
      if (!played.ok) throw new Error(played.error);
      s = played.state;

      const prop = applyIntent(s, { type: "proposeRedeal", seat: HUMAN }, rng);
      if (!prop.ok) throw new Error(prop.error);
      s = advanceBot(prop.state);

      if (s.currentTurn === HUMAN) {
        const pass = applyIntent(s, { type: "upcardPass", seat: HUMAN }, rng);
        if (!pass.ok) throw new Error(pass.error);
        s = pass.state;
      }
      s = advanceBot(s);

      if (s.currentTurn !== HUMAN) s = advanceBot(s);
      if (s.currentTurn !== HUMAN) throw new Error(`seed stall before human lead: turn=${s.currentTurn}`);

      const draw = applyIntent(s, { type: "drawStock", seat: HUMAN }, rng);
      if (!draw.ok) throw new Error(draw.error);
      s = draw.state;

      const card = s.hands[HUMAN][s.hands[HUMAN].length - 1]!;
      const disc = applyIntent(s, { type: "discard", seat: HUMAN, card, knock: false, gin: false }, rng);
      if (!disc.ok) throw new Error(disc.error);
      s = disc.state;

      s = advanceBot(s);
      if (s.hands[BOT].length === 11 && s.currentTurn === BOT) {
        throw new Error(`seed ${seed}: bot stuck with 11 after advanceBot`);
      }
    }
  });

  it("draws and discards after redeal proposed mid-play following played-through", () => {
    let s: ServerTruth = {
      version: 1,
      phase: "play",
      handIndex: 2,
      dealIndex: 3,
      dealer: 1,
      nonDealer: 0,
      scores: [30, 40],
      handsWon: [1, 1],
      raceTarget: 125,
      stock: ["6D"],
      discard: ["KS", "KD"],
      hands: [
        ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S"],
        ["9S", "TS", "JS", "QC", "QD", "QH", "2D", "3D", "4C", "5C"],
      ],
      currentTurn: 1,
      cut: null,
      lastCutResult: null,
      upcardOffer: null,
      knockCheckCard: "KS",
      knock: null,
      lastHandWinner: null,
      lastHandPoints: null,
      lastHandResult: null,
      handOverAcks: null,
      bettingRaw: null,
      bettingBucket: null,
      seenBy: {},
      redeal: null,
      voidFlash: null,
      currentDeal: null,
      lastAction: null,
      turnPickup: null,
    };

    const played = applyIntent(s, { type: "passStock", seat: 1 }, () => 0.99);
    expect(played.ok).toBe(true);
    if (!played.ok) return;
    s = played.state;

    // Play one turn on the post-played-through deal before proposing redeal.
    if (s.currentTurn === HUMAN) {
      const pass = applyIntent(s, { type: "upcardPass", seat: HUMAN }, () => 0.42);
      expect(pass.ok).toBe(true);
      if (!pass.ok) return;
      s = pass.state;
    }
    s = advanceBot(s);
    if (s.currentTurn !== HUMAN) s = advanceBot(s);
    const draw0 = applyIntent(s, { type: "drawStock", seat: HUMAN }, () => 0.42);
    expect(draw0.ok).toBe(true);
    if (!draw0.ok) return;
    s = draw0.state;
    const c0 = s.hands[HUMAN][s.hands[HUMAN].length - 1]!;
    const disc0 = applyIntent(s, { type: "discard", seat: HUMAN, card: c0, knock: false, gin: false }, () => 0.42);
    expect(disc0.ok).toBe(true);
    if (!disc0.ok) return;
    s = disc0.state;
    s = advanceBot(s);

    const prop = applyIntent(s, { type: "proposeRedeal", seat: HUMAN }, () => 0.42);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    s = advanceBot(prop.state);

    if (s.currentTurn === HUMAN) {
      const pass = applyIntent(s, { type: "upcardPass", seat: HUMAN }, () => 0.42);
      expect(pass.ok).toBe(true);
      if (!pass.ok) return;
      s = pass.state;
    }
    s = advanceBot(s);
    if (s.currentTurn !== HUMAN) s = advanceBot(s);

    const draw = applyIntent(s, { type: "drawStock", seat: HUMAN }, () => 0.42);
    expect(draw.ok).toBe(true);
    if (!draw.ok) return;
    s = draw.state;
    const card = s.hands[HUMAN][s.hands[HUMAN].length - 1]!;
    const disc = applyIntent(s, { type: "discard", seat: HUMAN, card, knock: false, gin: false }, () => 0.42);
    expect(disc.ok).toBe(true);
    if (!disc.ok) return;
    s = disc.state;

    s = advanceBot(s);
    expect(s.hands[BOT]).toHaveLength(10);
    expect(s.currentTurn).toBe(HUMAN);
  });
});
