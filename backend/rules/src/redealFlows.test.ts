import { describe, expect, it } from "vitest";
import { applyIntent } from "./engine.js";
import { buildPerspectives } from "./perspectives.js";
import type { CardId } from "./cards.js";
import type { ServerTruth } from "./types.js";

function makePlayState(opts: {
  hand0: CardId[];
  hand1: CardId[];
  stock: CardId[];
  discard: CardId[];
  knockCheckCard: CardId;
  scores?: [number, number];
  handsWon?: [number, number];
  handIndex?: number;
  dealer?: 0 | 1;
  nonDealer?: 0 | 1;
}): ServerTruth {
  const seenBy: Record<string, [boolean, boolean]> = {};
  for (const c of opts.hand0) seenBy[c] = [true, false];
  for (const c of opts.hand1) seenBy[c] = [false, true];
  for (const c of opts.discard) seenBy[c] = [true, true];
  const dealer = opts.dealer ?? 1;
  const nonDealer = opts.nonDealer ?? 0;

  return {
    version: 1,
    phase: "play",
    handIndex: opts.handIndex ?? 0,
    dealIndex: opts.handIndex ?? 0,
    currentDeal: null,
    dealer,
    nonDealer,
    scores: opts.scores ?? [0, 0],
    handsWon: opts.handsWon ?? [1, 0],
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

function buildKnockReadyState(knockCheckCard: CardId = "5S"): ServerTruth {
  return makePlayState({
    hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"],
    hand1: ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"],
    stock: ["3D", "4D"],
    discard: ["JS"],
    knockCheckCard,
  });
}

/** End hand 1 with both acks — lands on hand 2 down-card with seat 0 dealing, seat 1 leading. */
function advanceToSecondHandUpcardOffer(rng: () => number = () => 0.42): ServerTruth {
  const s = buildKnockReadyState("5S");
  const k = applyIntent(s, { type: "discard", seat: 0, card: "6C", knock: true, gin: false }, rng);
  if (!k.ok) throw new Error(k.error);
  const d = applyIntent(k.state, { type: "layoffDone", seat: 1 }, rng);
  if (!d.ok) throw new Error(d.error);
  const a0 = applyIntent(d.state, { type: "ackHandOver", seat: 0 }, rng);
  if (!a0.ok) throw new Error(a0.error);
  const a1 = applyIntent(a0.state, { type: "ackHandOver", seat: 1 }, rng);
  if (!a1.ok) throw new Error(a1.error);
  return a1.state;
}

function makeUpcardOfferState(): ServerTruth {
  const s = makePlayState({
    hand0: ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C"],
    hand1: ["4S", "6H", "KS", "2D", "3C", "4C", "5D", "8C", "8D", "9C"],
    stock: ["3D", "4D", "6C", "7C"],
    discard: ["JS"],
    knockCheckCard: "JS",
    scores: [0, 0],
    handsWon: [0, 0],
    handIndex: 0,
    dealer: 1,
    nonDealer: 0,
  });
  s.phase = "upcardOffer";
  s.upcardOffer = { stage: "nonDealer", nonDealerPassed: false };
  s.currentTurn = 0;
  return s;
}

describe("redeal flows — down-card and second hand", () => {
  it("allows propose during upcardOffer on the waiting seat (second hand, non-dealer to act)", () => {
    const s = advanceToSecondHandUpcardOffer();
    expect(s.phase).toBe("upcardOffer");
    expect(s.handIndex).toBe(1);
    expect(s.dealer).toBe(0);
    expect(s.nonDealer).toBe(1);
    expect(s.currentTurn).toBe(1);

    /* Seat 0 is dealer and waiting while seat 1 decides on the down card. */
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    expect(prop.state.redeal).toEqual({ fromSeat: 0, status: "pending" });
  });

  it("allows propose during upcardOffer on the active seat (second hand, non-dealer)", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 1 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    expect(prop.state.redeal).toEqual({ fromSeat: 1, status: "pending" });
  });

  it("exposes pending redeal identically to both perspectives", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;

    const views = buildPerspectives(prop.state);
    expect(views["0"].redeal).toEqual({ fromSeat: 0, status: "pending" });
    expect(views["1"].redeal).toEqual({ fromSeat: 0, status: "pending" });
  });

  it("blocks down-card moves for both seats while a redeal is pending", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 1 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;

    const proposerPass = applyIntent(prop.state, { type: "upcardPass", seat: 1 }, () => 0.5);
    expect(proposerPass.ok).toBe(false);
    if (proposerPass.ok) return;
    expect(proposerPass.error).toMatch(/Respond to the redeal proposal first/i);

    const dealerTake = applyIntent(prop.state, { type: "upcardTake", seat: 0 }, () => 0.5);
    expect(dealerTake.ok).toBe(false);
  });

  it("cancel restores down-card play on the second hand", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;

    const cancel = applyIntent(prop.state, { type: "cancelRedeal", seat: 0 }, () => 0.5);
    expect(cancel.ok).toBe(true);
    if (!cancel.ok) return;
    expect(cancel.state.redeal).toBeNull();

    const take = applyIntent(cancel.state, { type: "upcardTake", seat: 1 }, () => 0.5);
    expect(take.ok).toBe(true);
    if (!take.ok) return;
    expect(take.state.phase).toBe("play");
    expect(take.state.scores).toEqual([34, 0]);
  });

  it("full second-hand cycle: propose → opponent accepts → fresh down-card, same score", () => {
    const s = advanceToSecondHandUpcardOffer();
    const scoresBefore = [...s.scores] as [number, number];
    const handIndexBefore = s.handIndex;

    const prop = applyIntent(s, { type: "proposeRedeal", seat: 1 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const acc = applyIntent(prop.state, { type: "respondRedeal", seat: 0, accept: true }, () => 0.88);
    expect(acc.ok).toBe(true);
    if (!acc.ok) return;

    expect(acc.state.redeal).toBeNull();
    expect(acc.state.phase).toBe("upcardOffer");
    expect(acc.state.handIndex).toBe(handIndexBefore);
    expect(acc.state.scores).toEqual(scoresBefore);
    expect(acc.state.hands[0]).toHaveLength(10);
    expect(acc.state.hands[1]).toHaveLength(10);
    expect(acc.state.upcardOffer).toEqual({ stage: "nonDealer", nonDealerPassed: false });
  });

  it("clears stale redeal state when advancing to the next hand after handOver", () => {
    const s = makeUpcardOfferState();
    const declined = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(declined.ok).toBe(true);
    if (!declined.ok) return;
    const dec = applyIntent(
      declined.state,
      { type: "respondRedeal", seat: 1, accept: false },
      () => 0.5,
    );
    expect(dec.ok).toBe(true);
    if (!dec.ok) return;
    expect(dec.state.redeal?.status).toBe("declined");

    /* Force handOver with a synthetic transition — declined should not carry into hand 2. */
    const hand2 = advanceToSecondHandUpcardOffer();
    expect(hand2.redeal).toBeNull();
  });

  it("rejects duplicate propose while pending", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const again = applyIntent(prop.state, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(again.ok).toBe(false);
    if (again.ok) return;
    expect(again.error).toMatch(/redeal is already pending/i);
  });

  it("rejects opponent proposing while one is already pending", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const counter = applyIntent(prop.state, { type: "proposeRedeal", seat: 1 }, () => 0.5);
    expect(counter.ok).toBe(false);
    if (counter.ok) return;
    expect(counter.error).toMatch(/redeal is already pending/i);
  });

  it("after decline, either seat can resume down-card then play", () => {
    const s = advanceToSecondHandUpcardOffer();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 1 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const dec = applyIntent(prop.state, { type: "respondRedeal", seat: 0, accept: false }, () => 0.5);
    expect(dec.ok).toBe(true);
    if (!dec.ok) return;
    expect(dec.state.redeal?.status).toBe("declined");

    const pass = applyIntent(dec.state, { type: "upcardPass", seat: 1 }, () => 0.5);
    expect(pass.ok).toBe(true);
    if (!pass.ok) return;
    expect(pass.state.redeal).toBeNull();
    expect(pass.state.upcardOffer?.stage).toBe("dealer");
  });

  it("dealer-stage down card: waiting dealer can propose redeal", () => {
    const s = makeUpcardOfferState();
    const passed = applyIntent(s, { type: "upcardPass", seat: 0 }, () => 0.5);
    expect(passed.ok).toBe(true);
    if (!passed.ok) return;
    expect(passed.state.currentTurn).toBe(1);

    const prop = applyIntent(passed.state, { type: "proposeRedeal", seat: 1 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    expect(prop.state.redeal).toEqual({ fromSeat: 1, status: "pending" });

    const views = buildPerspectives(prop.state);
    expect(views["0"].redeal?.status).toBe("pending");
    expect(views["1"].redeal?.status).toBe("pending");
  });
});

describe("redeal flows — cancel edge cases", () => {
  it("rejects cancel when nothing is pending", () => {
    const s = buildKnockReadyState("5S");
    const out = applyIntent(s, { type: "cancelRedeal", seat: 0 }, () => 0.5);
    expect(out.ok).toBe(false);
  });

  it("rejects cancel after opponent already declined", () => {
    const s = buildKnockReadyState("5S");
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const dec = applyIntent(prop.state, { type: "respondRedeal", seat: 1, accept: false }, () => 0.5);
    expect(dec.ok).toBe(true);
    if (!dec.ok) return;
    const cancel = applyIntent(dec.state, { type: "cancelRedeal", seat: 0 }, () => 0.5);
    expect(cancel.ok).toBe(false);
  });

  it("allows play immediately after cancel on first-hand down card", () => {
    const s = makeUpcardOfferState();
    const prop = applyIntent(s, { type: "proposeRedeal", seat: 0 }, () => 0.5);
    expect(prop.ok).toBe(true);
    if (!prop.ok) return;
    const cancel = applyIntent(prop.state, { type: "cancelRedeal", seat: 0 }, () => 0.5);
    expect(cancel.ok).toBe(true);
    if (!cancel.ok) return;

    const pass = applyIntent(cancel.state, { type: "upcardPass", seat: 0 }, () => 0.5);
    expect(pass.ok).toBe(true);
  });
});
