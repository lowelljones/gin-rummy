import {
  buildDeck,
  compareCutCards,
  rankOrderLow,
  shuffleDeck,
  upcardKnockValue,
  type CardId,
} from "./cards.js";
import {
  bestDeadwood,
  bestLayoff,
  isBigGin11,
  isValidMeld,
  type Meld,
} from "./melds.js";
import {
  computeBettingSettlement,
  deadwoodTotal,
  resolveKnockFinal,
  scoreEO,
  scoreGin,
  validateKnockerLayout,
} from "./scoring.js";
import type {
  ApplyOutcome,
  CurrentDealSnapshot,
  HandResult,
  Intent,
  LastAction,
  Seat,
  ServerTruth,
} from "./types.js";
import type { Partition } from "./melds.js";

function cloneState(s: ServerTruth): ServerTruth {
  return JSON.parse(JSON.stringify(s)) as ServerTruth;
}

function markSeen(state: ServerTruth, card: CardId, viewers: Seat[]) {
  const cur = state.seenBy[card] ?? [false, false];
  const next: [boolean, boolean] = [cur[0] ?? false, cur[1] ?? false];
  for (const v of viewers) next[v] = true;
  state.seenBy[card] = next;
}

function otherSeat(s: Seat): Seat {
  return (1 - s) as Seat;
}

/** Record the action just applied so both clients can log it authoritatively. */
function recordAction(state: ServerTruth, action: Omit<LastAction, "seq">): void {
  const seq = (state.lastAction?.seq ?? 0) + 1;
  state.lastAction = { seq, ...action };
}

/** First to the race target normally wins; if both are at/above target, higher total wins. */
function matchWinnerSeat(scores: [number, number], target: number): Seat | null {
  if (scores[0] < target && scores[1] < target) return null;
  if (scores[0] > scores[1]) return 0;
  if (scores[1] > scores[0]) return 1;
  return 0;
}

export function createNewMatch(_seed: string, rng: () => number): ServerTruth {
  const deck = shuffleDeck(buildDeck(), rng);
  const firstSeat = (rng() < 0.5 ? 0 : 1) as Seat;
  return {
    version: 1,
    phase: "cutForDeal",
    handIndex: 0,
    dealIndex: 0,
    currentDeal: null,
    dealer: 0,
    nonDealer: 1,
    scores: [0, 0],
    handsWon: [0, 0],
    raceTarget: 125,
    stock: [],
    discard: [],
    hands: [[], []],
    currentTurn: 0,
    cut: { spread: deck, picks: [null, null], firstSeat },
    lastCutResult: null,
    lastAction: null,
    turnPickup: null,
    upcardOffer: null,
    knockCheckCard: null,
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
  };
}

function cloneMelds(ms: Meld[]): Meld[] {
  return ms.map((m) => ({ type: m.type, cards: [...m.cards] }));
}

/**
 * Build the end-of-hand reveal payload. `winner`/`points` are filled in by
 * `awardHand`, which is the single place a hand is scored.
 */
function makeHandResult(
  kind: HandResult["kind"],
  closer: Seat,
  closerPartition: Partition,
  defenderPartition: Partition,
  layoffs: HandResult["layoffs"],
): Omit<HandResult, "winner" | "points"> {
  const sideFor = (p: Partition) => ({
    melds: cloneMelds(p.melds),
    deadwood: [...p.deadwood],
    deadwoodPoints: deadwoodTotal(p.deadwood),
  });
  const sides: [HandResult["sides"][0], HandResult["sides"][1]] =
    closer === 0
      ? [sideFor(closerPartition), sideFor(defenderPartition)]
      : [sideFor(defenderPartition), sideFor(closerPartition)];
  return { kind, closer, sides, layoffs: layoffs.map((l) => ({ ...l })) };
}

function snapshotCurrentDeal(state: ServerTruth): CurrentDealSnapshot {
  return {
    dealIndex: state.dealIndex,
    handIndex: state.handIndex,
    dealer: state.dealer,
    nonDealer: state.nonDealer,
    knockCheckCard: state.knockCheckCard,
    openingHands: [[...state.hands[0]], [...state.hands[1]]],
    scoresAtStart: [...state.scores] as [number, number],
    startedAtMoveSeq: null,
  };
}

/** Same hand number and dealer; fresh shuffle and back to down-card (upcard) phase. */
function voidAndRedeal(state: ServerTruth, rng: () => number): void {
  state.dealIndex += 1;
  state.seenBy = {};
  state.knock = null;
  state.turnPickup = null;
  state.lastAction = null;
  state.voidFlash = null;
  state.knockCheckCard = null;
  state.stock = [];
  state.discard = [];
  state.hands = [[], []];
  state.lastHandWinner = null;
  state.lastHandPoints = null;
  state.lastHandResult = null;
  state.handOverAcks = null;
  beginHand(state, rng);
}

/** Deck played through: void with no score change and flash both clients before the re-deal. */
function voidHandPlayedThrough(state: ServerTruth, rng: () => number): void {
  voidAndRedeal(state, rng);
  state.voidFlash = "playedThrough";
}

/** The last face-down stock card is never drawn; drawing requires at least two cards. */
function stockDrawAllowed(state: ServerTruth): boolean {
  return state.stock.length > 1;
}

/** True when only the reserved stock card remains (end-of-deck flow). */
function isPlayedThroughEndTurn(state: ServerTruth): boolean {
  return state.stock.length === 1;
}

function applyProposeRedeal(state: ServerTruth, seat: Seat): ApplyOutcome {
  const okPhases = new Set<ServerTruth["phase"]>(["upcardOffer", "play", "knockLayoff"]);
  if (!okPhases.has(state.phase)) {
    return { ok: false, error: "Redeal can only be proposed during the down card, play, or layoff phase" };
  }
  const cur = state.redeal;
  if (cur?.status === "pending") {
    if (cur.fromSeat === seat) {
      return { ok: false, error: "Redeal already proposed — waiting on your opponent" };
    }
    return { ok: false, error: "Your opponent already proposed a redeal — respond to that first" };
  }
  state.redeal = { fromSeat: seat, status: "pending" };
  return { ok: true, state };
}

function applyRespondRedeal(state: ServerTruth, seat: Seat, accept: boolean, rng: () => number): ApplyOutcome {
  const cur = state.redeal;
  if (!cur || cur.status !== "pending") {
    return { ok: false, error: "No pending redeal proposal" };
  }
  if (cur.fromSeat === seat) {
    return { ok: false, error: "You cannot respond to your own redeal proposal" };
  }
  if (accept) {
    state.redeal = null;
    voidAndRedeal(state, rng);
    return { ok: true, state };
  }
  state.redeal = { fromSeat: cur.fromSeat, status: "declined" };
  return { ok: true, state };
}

function applyCancelRedeal(state: ServerTruth, seat: Seat): ApplyOutcome {
  const cur = state.redeal;
  if (!cur || cur.status !== "pending") {
    return { ok: false, error: "No pending redeal proposal" };
  }
  if (cur.fromSeat !== seat) {
    return { ok: false, error: "Only the player who proposed the redeal can cancel it" };
  }
  state.redeal = null;
  return { ok: true, state };
}

function dealHandFromPile(state: ServerTruth, pile: CardId[]): CardId {
  state.lastAction = null;
  state.turnPickup = null;
  state.hands = [[], []];
  for (let i = 0; i < 10; i++) {
    state.hands[state.nonDealer].push(pile.pop()!);
    state.hands[state.dealer].push(pile.pop()!);
  }
  const up = pile.pop()!;
  state.discard = [up];
  state.stock = pile.reverse();
  markSeen(state, up, [0, 1]);
  for (const s of [0, 1] as Seat[]) {
    for (const c of state.hands[s]) markSeen(state, c, [s]);
  }
  /* Knock limit for the whole hand: the first / only upcard to the table (fixed even if later taken into a hand). */
  state.knockCheckCard = up;
  state.currentDeal = snapshotCurrentDeal(state);
  return up;
}

function beginHand(state: ServerTruth, rng: () => number): void {
  const dealer = state.dealer;
  const nonDealer = otherSeat(dealer);
  state.nonDealer = nonDealer;
  state.lastCutResult = null;
  const pile = shuffleDeck(buildDeck(), rng);
  dealHandFromPile(state, pile);
  state.phase = "upcardOffer";
  state.upcardOffer = { stage: "nonDealer", nonDealerPassed: false };
  state.currentTurn = nonDealer;
  state.knock = null;
}

function finishCutAndDealFirstHand(state: ServerTruth): void {
  const p0 = state.cut!.picks[0]!;
  const p1 = state.cut!.picks[1]!;
  const cmp = compareCutCards(p0, p1);
  const higherSeat = (cmp >= 0 ? 0 : 1) as Seat;
  state.nonDealer = higherSeat;
  state.dealer = otherSeat(higherSeat);
  state.lastCutResult = { p0, p1, nonDealer: higherSeat };

  const used = new Set<CardId>([p0, p1]);
  const remaining = state.cut!.spread.filter((c) => !used.has(c));
  state.cut = null;

  if (remaining.length !== 50) {
    throw new Error(`Cut spread size invalid: ${remaining.length}`);
  }

  const pile = [...remaining];
  dealHandFromPile(state, pile);
  state.phase = "upcardOffer";
  state.upcardOffer = { stage: "nonDealer", nonDealerPassed: false };
  state.currentTurn = state.nonDealer;
  state.knock = null;
}

function awardHand(
  state: ServerTruth,
  winner: Seat,
  points: number,
  result?: Omit<HandResult, "winner" | "points">,
) {
  state.scores[winner] += points;
  state.handsWon[winner] += 1;
  state.lastHandWinner = winner;
  state.lastHandPoints = points;
  state.lastHandResult = result ? { ...result, winner, points } : null;
  state.handOverAcks = [false, false];
  state.phase = "handOver";

  const w = matchWinnerSeat(state.scores, state.raceTarget);
  if (w !== null) {
    const loser = otherSeat(w);
    const { raw, bucket } = computeBettingSettlement({
      winner: w,
      loser,
      finalScores: state.scores,
      handsWon: state.handsWon,
    });
    state.bettingRaw = raw;
    state.bettingBucket = bucket;
    state.phase = "matchOver";
  }
}

function maybeStartNextHand(state: ServerTruth, rng: () => number) {
  if (state.phase !== "handOver") return;
  const winner = state.lastHandWinner;
  if (winner === null) return;
  if (matchWinnerSeat(state.scores, state.raceTarget) !== null) return;

  state.handIndex += 1;
  state.dealIndex += 1;
  state.dealer = winner;
  state.upcardOffer = null;
  state.knockCheckCard = null;
  state.knock = null;
  state.lastHandWinner = null;
  state.lastHandPoints = null;
  state.lastHandResult = null;
  state.handOverAcks = null;
  state.redeal = null;
  beginHand(state, rng);
}

/** `upcardOffer` phase must carry an offer object; if missing (legacy/partial row), treat as play. */
function repairPhase(state: ServerTruth): void {
  if (state.phase === "upcardOffer" && !state.upcardOffer) {
    state.phase = "play";
  }
}

export function applyIntent(state: ServerTruth, intent: Intent, rng: () => number): ApplyOutcome {
  const s = cloneState(state);
  repairPhase(s);

  if (s.phase === "matchOver") {
    return { ok: false, error: "Match is over" };
  }

  /* One-shot void flash is consumed once either player makes the next move. */
  if (s.voidFlash && intent.type !== "ackHandOver") {
    s.voidFlash = null;
  }

  /* Declined proposals clear as soon as either player makes an ordinary move. */
  if (s.redeal?.status === "declined") {
    if (intent.type !== "proposeRedeal" && intent.type !== "respondRedeal") {
      s.redeal = null;
    }
  }

  if (s.redeal?.status === "pending") {
    if (intent.type === "respondRedeal") {
      return applyRespondRedeal(s, intent.seat, intent.accept, rng);
    }
    if (intent.type === "cancelRedeal") {
      return applyCancelRedeal(s, intent.seat);
    }
    if (intent.type === "proposeRedeal") {
      return { ok: false, error: "A redeal is already pending — wait for your opponent’s response" };
    }
    return { ok: false, error: "Respond to the redeal proposal first (accept or decline)" };
  }

  if (intent.type === "proposeRedeal") {
    return applyProposeRedeal(s, intent.seat);
  }
  if (intent.type === "respondRedeal") {
    return { ok: false, error: "No pending redeal proposal" };
  }
  if (intent.type === "cancelRedeal") {
    return { ok: false, error: "No pending redeal proposal" };
  }

  if (s.phase === "handOver") {
    if (intent.type !== "ackHandOver") {
      return { ok: false, error: "Waiting for hand acknowledgment" };
    }
    const seat = intent.seat;
    if (seat === 0 || seat === 1) {
      /* Ready-up: the next hand only deals once both players have continued. */
      const acks: [boolean, boolean] = s.handOverAcks ?? [false, false];
      acks[seat] = true;
      s.handOverAcks = acks;
      if (acks[0] && acks[1]) {
        maybeStartNextHand(s, rng);
      }
      return { ok: true, state: s };
    }
    /* Legacy seatless ack (older clients): advance immediately. */
    maybeStartNextHand(s, rng);
    return { ok: true, state: s };
  }

  switch (intent.type) {
    case "ackHandOver":
      return { ok: false, error: "No hand to acknowledge" };
    case "cutPick":
      return applyCutPick(s, intent.seat, intent.index);
    case "upcardTake":
      return applyUpcardTake(s, intent.seat);
    case "upcardPass":
      return applyUpcardPass(s, intent.seat);
    case "drawStock":
      return applyDrawStock(s, intent.seat);
    case "takeDiscard":
      return applyTakeDiscard(s, intent.seat);
    case "passStock":
      return applyPassStock(s, intent.seat, rng);
    case "discard":
      return applyDiscard(s, intent, rng);
    case "declareBigGin":
      return applyDeclareBigGin(s, intent.seat);
    case "layoffAttach":
      return applyLayoffAttach(s, intent);
    case "layoffResolve":
      return applyLayoffResolve(s, intent);
    case "layoffDone":
      return applyLayoffDone(s, intent.seat);
    default:
      return { ok: false, error: "Unknown intent" };
  }
}

function applyCutPick(state: ServerTruth, seat: Seat, index: number): ApplyOutcome {
  if (state.phase !== "cutForDeal" || !state.cut) {
    return { ok: false, error: "Not in cut phase" };
  }
  const spread = state.cut.spread;
  if (!Number.isInteger(index) || index < 0 || index >= spread.length) {
    return { ok: false, error: "Invalid spread index" };
  }

  if (state.cut.picks[seat] !== null) {
    return { ok: false, error: "Seat already picked" };
  }
  const firstSeat = (state.cut.firstSeat ?? 0) as Seat;
  const secondSeat = otherSeat(firstSeat);
  const expected: Seat | null =
    state.cut.picks[firstSeat] === null
      ? firstSeat
      : state.cut.picks[secondSeat] === null
        ? secondSeat
        : null;
  if (expected === null) {
    return { ok: false, error: "Cut already complete" };
  }
  if (seat !== expected) {
    return { ok: false, error: "Wrong turn to cut" };
  }

  const card = spread[index]!;
  spread.splice(index, 1);
  state.cut.picks[seat] = card;
  /* Reveal this cut pick to both players immediately (sequential draw UX). */
  markSeen(state, card, [0, 1]);
  if (state.cut.picks[0] !== null && state.cut.picks[1] !== null) {
    finishCutAndDealFirstHand(state);
  }

  return { ok: true, state };
}

function applyUpcardTake(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase !== "upcardOffer" || !state.upcardOffer) {
    return { ok: false, error: "Not in upcard offer" };
  }
  const { stage, nonDealerPassed } = state.upcardOffer;
  const nd = state.nonDealer;
  const d = state.dealer;

  if (stage === "nonDealer") {
    if (seat !== nd) return { ok: false, error: "Non-dealer acts first" };
    const up = state.discard[state.discard.length - 1]!;
    state.hands[seat].push(up);
    state.discard.pop();
    markSeen(state, up, [0, 1]);
    state.turnPickup = { seat, type: "takeDownCard", card: up };
    recordAction(state, { seat, type: "takeDownCard", card: up, pickup: null });
    state.upcardOffer = null;
    state.phase = "play";
    state.currentTurn = seat;
    return { ok: true, state };
  }

  if (stage === "dealer") {
    if (seat !== d) return { ok: false, error: "Dealer acts" };
    if (!nonDealerPassed) return { ok: false, error: "Non-dealer has not passed" };
    const up = state.discard[state.discard.length - 1]!;
    state.hands[seat].push(up);
    state.discard.pop();
    markSeen(state, up, [0, 1]);
    state.turnPickup = { seat, type: "takeDownCard", card: up };
    recordAction(state, { seat, type: "takeDownCard", card: up, pickup: null });
    state.upcardOffer = null;
    state.phase = "play";
    state.currentTurn = seat;
    return { ok: true, state };
  }

  return { ok: false, error: "Invalid upcard stage" };
}

function applyUpcardPass(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase !== "upcardOffer" || !state.upcardOffer) {
    return { ok: false, error: "Not in upcard offer" };
  }
  const nd = state.nonDealer;
  const d = state.dealer;

  if (state.upcardOffer.stage === "nonDealer") {
    if (seat !== nd) return { ok: false, error: "Wrong seat" };
    state.upcardOffer = { stage: "dealer", nonDealerPassed: true };
    state.currentTurn = d;
    recordAction(state, { seat, type: "passUpcard", card: null, pickup: null });
    return { ok: true, state };
  }

  if (state.upcardOffer.stage === "dealer") {
    if (seat !== d) return { ok: false, error: "Wrong seat" };
    if (!state.upcardOffer.nonDealerPassed) return { ok: false, error: "Invalid pass order" };
    state.upcardOffer = null;
    state.phase = "play";
    /* Both passed: the non-dealer leads and may draw from the stock or even
     * take the twice-refused upcard (house rule — rare, but allowed). */
    state.currentTurn = nd;
    recordAction(state, { seat, type: "passUpcard", card: null, pickup: null });
    return { ok: true, state };
  }

  return { ok: false, error: "Invalid pass" };
}

function applyDrawStock(state: ServerTruth, seat: Seat): ApplyOutcome {
  /* During the down-card offer only upcardTake/upcardPass are legal — drawing
   * here would let the non-dealer preempt the dealer's option on the upcard. */
  if (state.phase !== "play") return { ok: false, error: "Cannot draw now" };
  if (state.currentTurn !== seat) return { ok: false, error: "Not your turn" };
  if (state.hands[seat].length !== 10) return { ok: false, error: "Expected 10 cards before draw" };
  if (!stockDrawAllowed(state)) {
    return { ok: false, error: "The last card in the deck cannot be drawn" };
  }
  const c = state.stock.pop()!;
  state.hands[seat].push(c);
  markSeen(state, c, [seat]);
  state.turnPickup = { seat, type: "drawStock", card: c };
  recordAction(state, { seat, type: "drawStock", card: c, pickup: null });
  return { ok: true, state };
}

function applyTakeDiscard(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase !== "play") {
    return { ok: false, error: "Not in play" };
  }
  if (state.currentTurn !== seat) {
    return { ok: false, error: "Not your turn" };
  }
  if (state.hands[seat].length !== 10) {
    return { ok: false, error: "Expected 10 cards before take" };
  }
  if (state.discard.length === 0) {
    return { ok: false, error: "No discard" };
  }
  const c = state.discard.pop()!;
  state.hands[seat].push(c);
  markSeen(state, c, [0, 1]);
  state.turnPickup = { seat, type: "takeDiscard", card: c };
  recordAction(state, { seat, type: "takeDiscard", card: c, pickup: null });
  return { ok: true, state };
}

function applyPassStock(state: ServerTruth, seat: Seat, rng: () => number): ApplyOutcome {
  if (state.phase !== "play") return { ok: false, error: "Not in play" };
  if (state.currentTurn !== seat) return { ok: false, error: "Not your turn" };
  if (state.hands[seat].length !== 10) return { ok: false, error: "Expected 10 cards before passing" };
  if (!isPlayedThroughEndTurn(state)) {
    return { ok: false, error: "Can only pass when one card remains in the deck" };
  }
  recordAction(state, { seat, type: "passStock", card: null, pickup: null });
  voidHandPlayedThrough(state, rng);
  return { ok: true, state };
}

function applyDiscard(state: ServerTruth, intent: Intent, rng: () => number): ApplyOutcome {
  if (intent.type !== "discard") return { ok: false, error: "Internal" };
  const { seat, card, knock, gin } = intent;
  const layout = intent.layout;

  if (state.phase !== "play") return { ok: false, error: "Not in play" };
  if (state.currentTurn !== seat) return { ok: false, error: "Not your turn" };
  const hand = state.hands[seat];
  if (hand.length !== 11) return { ok: false, error: "Must have 11 cards to discard" };
  if (!hand.includes(card)) return { ok: false, error: "Card not in hand" };

  const hand10 = hand.filter((c) => c !== card);
  if (hand10.length !== 10) return { ok: false, error: "Hand size error" };

  const knockVal = state.knockCheckCard == null ? null : upcardKnockValue(state.knockCheckCard);

  /**
   * Resolved layout used when the knock is legal. The client may either submit an
   * explicit (validated) layout or omit it — when omitted, the server picks the
   * unique optimal partition. This avoids shipping a meld solver to the iOS client.
   */
  let resolvedKnockMelds: Meld[] | null = null;
  let resolvedKnockDeadwood: CardId[] | null = null;

  if (gin) {
    const { sum } = bestDeadwood(hand10);
    if (sum !== 0) return { ok: false, error: "Gin not legal" };
  } else if (knock) {
    /**
     * Threshold knock: after discarding, the knocker's best unmelded total must be
     * greater than 0 and at most the down card's knock value (2–9 face, T/J/Q/K=10).
     * Ace as down card ⇒ no knock this hand for either player (`upcardKnockValue` is null).
     */
    if (knockVal === null) {
      return {
        ok: false,
        error:
          "Knocking is not allowed when the first upcard is an Ace (no knock for this hand, even with 1 deadwood).",
      };
    }
    if (layout) {
      if (!validateKnockerLayout(hand10, layout.melds, layout.deadwood)) {
        return { ok: false, error: "Invalid knocker layout" };
      }
      const supplied = deadwoodTotal(layout.deadwood);
      if (supplied === 0) return { ok: false, error: "Must declare gin with deadwood 0" };
      if (supplied > knockVal) {
        return {
          ok: false,
          error: `Knock requires unmelded points at most ${knockVal} (down card); supplied layout has ${supplied}.`,
        };
      }
      resolvedKnockMelds = layout.melds;
      resolvedKnockDeadwood = layout.deadwood;
    } else {
      const best = bestDeadwood(hand10);
      if (best.sum === 0) return { ok: false, error: "Must declare gin with deadwood 0" };
      if (best.sum > knockVal) {
        return {
          ok: false,
          error: `Knock requires unmelded points at most ${knockVal} (down card); best layout from this discard is ${best.sum}.`,
        };
      }
      resolvedKnockMelds = best.partition.melds;
      resolvedKnockDeadwood = best.partition.deadwood;
    }
  }
  /* Plain discard: always allowed, even when the remaining 10 meld perfectly.
   * Gin and EO are explicit declarations — a player may pass up gin to keep
   * drawing toward 11-card big gin. */

  state.hands[seat] = hand10;
  state.discard.push(card);
  markSeen(state, card, [0, 1]);

  const pickup =
    state.turnPickup && state.turnPickup.seat === seat
      ? { type: state.turnPickup.type, card: state.turnPickup.card }
      : null;
  state.turnPickup = null;
  recordAction(state, { seat, type: "discard", card, pickup });

  if (gin) {
    const opp = otherSeat(seat);
    /* Only the opponent's unmelded cards count toward gin points — their own melds don't.
     * Any optimal partition works for the ginner's display: all 10 cards are melded. */
    const ginnerPartition = bestDeadwood(hand10).partition;
    const oppPartition = bestDeadwood(state.hands[opp]).partition;
    const pts = scoreGin(oppPartition.deadwood);
    for (const c of state.hands[opp]) markSeen(state, c, [0, 1]);
    for (const c of hand10) markSeen(state, c, [0, 1]);
    awardHand(state, seat, pts, makeHandResult("gin", seat, ginnerPartition, oppPartition, []));
    return { ok: true, state };
  }

  if (knock && resolvedKnockMelds && resolvedKnockDeadwood) {
    state.phase = "knockLayoff";
    const opp = otherSeat(seat);
    state.knock = {
      knocker: seat,
      knockCard: card,
      knockerMelds: resolvedKnockMelds.map((m) => ({ ...m, cards: [...m.cards] })),
      knockerDeadwood: [...resolvedKnockDeadwood],
      opponentOriginalHand: [...state.hands[opp]],
      opponentDeadwood: [...state.hands[opp]],
      knockerMeldsAfterLayoff: resolvedKnockMelds.map((m) => ({ ...m, cards: [...m.cards] })),
      layoffTurn: opp,
    };
    state.currentTurn = opp;
    for (const m of state.knock.knockerMelds) {
      for (const c of m.cards) markSeen(state, c, [0, 1]);
    }
    for (const c of state.knock.knockerDeadwood) markSeen(state, c, [0, 1]);
    return { ok: true, state };
  }

  /* End-of-deck: after taking the discard with one stock card left, a plain discard ends the hand with no points. */
  if (isPlayedThroughEndTurn(state) && pickup?.type === "takeDiscard") {
    voidHandPlayedThrough(state, rng);
    return { ok: true, state };
  }

  state.currentTurn = otherSeat(seat);
  return { ok: true, state };
}

function applyDeclareBigGin(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase !== "play") return { ok: false, error: "Not in play" };
  if (state.currentTurn !== seat) return { ok: false, error: "Not your turn" };
  const hand = state.hands[seat];
  if (hand.length !== 11) return { ok: false, error: "Need 11 cards for EO" };
  if (!isBigGin11(hand)) return { ok: false, error: "Not EO" };
  const opp = otherSeat(seat);
  /* Only the opponent's unmelded cards count toward EO points — their own melds don't. */
  const ginnerPartition = bestDeadwood(hand).partition; /* all 11 meld (EO verified above) */
  const oppPartition = bestDeadwood(state.hands[opp]).partition;
  const pts = scoreEO(oppPartition.deadwood);
  for (const c of state.hands[opp]) markSeen(state, c, [0, 1]);
  for (const c of hand) markSeen(state, c, [0, 1]);
  state.hands[seat] = [];
  awardHand(state, seat, pts, makeHandResult("bigGin", seat, ginnerPartition, oppPartition, []));
  return { ok: true, state };
}

function applyLayoffAttach(state: ServerTruth, intent: Intent): ApplyOutcome {
  if (intent.type !== "layoffAttach") return { ok: false, error: "Internal" };
  if (state.phase !== "knockLayoff" || !state.knock) return { ok: false, error: "No knock layoff" };
  const { seat, card, meldIndex } = intent;
  if (state.knock.layoffTurn !== seat) return { ok: false, error: "Not layoff turn" };
  const knocker = state.knock.knocker;
  if (seat === knocker) return { ok: false, error: "Knocker cannot lay off" };

  const idx = state.knock.opponentDeadwood.indexOf(card);
  if (idx < 0) return { ok: false, error: "Card not in opponent deadwood" };
  const melds = state.knock.knockerMeldsAfterLayoff;
  const meld = melds[meldIndex];
  if (!meld) return { ok: false, error: "Invalid meld index" };

  const trial = { ...meld, cards: [...meld.cards, card] };
  if (!isValidMeld(trial)) return { ok: false, error: "Illegal layoff" };

  meld.cards.push(card);
  state.knock.opponentDeadwood.splice(idx, 1);
  const hi = state.hands[seat].indexOf(card);
  if (hi >= 0) state.hands[seat].splice(hi, 1);
  markSeen(state, card, [0, 1]);
  return { ok: true, state };
}

/** Append `card` to a meld, keeping run cards in rank order for display. */
function extendMeld(base: Meld, card: CardId): Meld {
  const cards =
    base.type === "run"
      ? [...base.cards, card].sort((a, b) => rankOrderLow(a) - rankOrderLow(b))
      : [...base.cards, card];
  return { type: base.type, cards };
}

/**
 * Defender's single-shot answer to a knock: their chosen meld partition plus an
 * ordered layoff sequence. The choices are validated for legality only — a
 * suboptimal arrangement stands (that's the skill), unlike `layoffDone` which
 * optimizes on the defender's behalf (kept for the test bot / legacy clients).
 */
function applyLayoffResolve(state: ServerTruth, intent: Intent): ApplyOutcome {
  if (intent.type !== "layoffResolve") return { ok: false, error: "Internal" };
  if (state.phase !== "knockLayoff" || !state.knock) return { ok: false, error: "No knock layoff" };
  const { seat, ownMelds, layoffs } = intent;
  if (state.knock.layoffTurn !== seat) return { ok: false, error: "Not layoff turn" };
  const knocker = state.knock.knocker;
  if (seat === knocker) return { ok: false, error: "Knocker cannot resolve layoffs" };

  const available = [...state.knock.opponentDeadwood];
  const used = new Set<CardId>();

  const resolvedOwnMelds: Meld[] = [];
  for (const raw of ownMelds) {
    const meld: Meld =
      raw.type === "run"
        ? { type: "run", cards: [...raw.cards].sort((a, b) => rankOrderLow(a) - rankOrderLow(b)) }
        : { type: "set", cards: [...raw.cards] };
    if (!isValidMeld(meld)) {
      return { ok: false, error: `Invalid meld: ${meld.cards.join(" ")}` };
    }
    for (const c of meld.cards) {
      if (used.has(c)) return { ok: false, error: `Card ${c} used in more than one meld` };
      if (!available.includes(c)) return { ok: false, error: `Card ${c} not in your hand` };
      used.add(c);
    }
    resolvedOwnMelds.push(meld);
  }

  const meldsAfter = state.knock.knockerMeldsAfterLayoff.map((m) => ({ ...m, cards: [...m.cards] }));
  const appliedLayoffs: { card: CardId; meldIndex: number }[] = [];
  for (const lo of layoffs) {
    const { card, meldIndex } = lo;
    if (used.has(card)) return { ok: false, error: `Card ${card} already melded or laid off` };
    if (!available.includes(card)) return { ok: false, error: `Card ${card} not in your hand` };
    const base = meldsAfter[meldIndex];
    if (!base) return { ok: false, error: "Invalid meld index" };
    const trial = extendMeld(base, card);
    if (!isValidMeld(trial)) {
      return { ok: false, error: `Card ${card} cannot attach to that meld` };
    }
    meldsAfter[meldIndex] = trial;
    used.add(card);
    appliedLayoffs.push({ card, meldIndex });
  }

  const remaining = available.filter((c) => !used.has(c));
  state.knock.knockerMeldsAfterLayoff = meldsAfter;
  state.knock.opponentDeadwood = remaining;
  for (const c of available) markSeen(state, c, [0, 1]);

  const { winner, points } = resolveKnockFinal({
    knocker,
    knockerDeadwood: state.knock.knockerDeadwood,
    opponentDeadwood: remaining,
  });

  const result = makeHandResult(
    winner === knocker ? "knock" : "undercut",
    knocker,
    { melds: meldsAfter, deadwood: state.knock.knockerDeadwood },
    { melds: resolvedOwnMelds, deadwood: remaining },
    appliedLayoffs,
  );

  state.hands[knocker] = [];
  state.hands[otherSeat(knocker)] = [];
  awardHand(state, winner, points, result);
  state.knock = null;
  return { ok: true, state };
}

function applyLayoffDone(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase !== "knockLayoff" || !state.knock) return { ok: false, error: "No knock layoff" };
  if (state.knock.layoffTurn !== seat) return { ok: false, error: "Not layoff turn" };
  const knocker = state.knock.knocker;
  if (seat === knocker) return { ok: false, error: "Knocker cannot finish layoff" };

  /**
   * Resolve the opponent's hand optimally before scoring: combine layoffs onto the
   * knocker's melds with the opponent's own melds so that only truly unmelded cards
   * count against them. The client UI today only exposes a "Done" button, so the
   * server computes the best outcome on the opponent's behalf.
   */
  const beforeDeadwood = [...state.knock.opponentDeadwood];
  const result = bestLayoff(state.knock.knockerMeldsAfterLayoff, beforeDeadwood);
  state.knock.knockerMeldsAfterLayoff = result.melds;
  state.knock.opponentDeadwood = [...result.opponentDeadwood];
  const removed = beforeDeadwood.filter((c) => !result.opponentDeadwood.includes(c));
  for (const c of removed) {
    const hi = state.hands[seat].indexOf(c);
    if (hi >= 0) state.hands[seat].splice(hi, 1);
    markSeen(state, c, [0, 1]);
  }
  for (const c of beforeDeadwood) markSeen(state, c, [0, 1]);

  /* Which laid-off cards landed on which knocker meld (indices are stable through
   * bestLayoff). Diff against the knocker's ORIGINAL melds so cards the defender
   * already attached via layoffAttach are included in the reveal too. */
  const layoffs: { card: CardId; meldIndex: number }[] = [];
  result.melds.forEach((m, i) => {
    const baseCards = new Set(state.knock!.knockerMelds[i]?.cards ?? []);
    for (const c of m.cards) {
      if (!baseCards.has(c)) layoffs.push({ card: c, meldIndex: i });
    }
  });

  const { winner, points } = resolveKnockFinal({
    knocker,
    knockerDeadwood: state.knock.knockerDeadwood,
    opponentDeadwood: state.knock.opponentDeadwood,
  });

  const handResult = makeHandResult(
    winner === knocker ? "knock" : "undercut",
    knocker,
    { melds: result.melds, deadwood: state.knock.knockerDeadwood },
    { melds: result.opponentMelds, deadwood: result.opponentDeadwood },
    layoffs,
  );

  state.hands[knocker] = [];
  state.hands[otherSeat(knocker)] = [];
  awardHand(state, winner, points, handResult);
  state.knock = null;
  return { ok: true, state };
}
