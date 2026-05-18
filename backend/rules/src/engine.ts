import {
  buildDeck,
  compareCutCards,
  shuffleDeck,
  upcardKnockValue,
  type CardId,
} from "./cards.js";
import {
  applyLayoffsGreedy,
  bestAfterDiscard11,
  bestDeadwood,
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
import type { ApplyOutcome, Intent, Seat, ServerTruth } from "./types.js";

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
    upcardOffer: null,
    knockCheckCard: null,
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    bettingRaw: null,
    bettingBucket: null,
    seenBy: {},
  };
}

function dealHandFromPile(state: ServerTruth, pile: CardId[]): CardId {
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

function awardHand(state: ServerTruth, winner: Seat, points: number) {
  state.scores[winner] += points;
  state.handsWon[winner] += 1;
  state.lastHandWinner = winner;
  state.lastHandPoints = points;
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
  state.dealer = winner;
  state.upcardOffer = null;
  state.knockCheckCard = null;
  state.knock = null;
  state.lastHandWinner = null;
  state.lastHandPoints = null;
  beginHand(state, rng);
}

export function applyIntent(state: ServerTruth, intent: Intent, rng: () => number): ApplyOutcome {
  const s = cloneState(state);

  if (s.phase === "matchOver") {
    return { ok: false, error: "Match is over" };
  }

  if (s.phase === "handOver") {
    if (intent.type !== "ackHandOver") {
      return { ok: false, error: "Waiting for hand acknowledgment" };
    }
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
    case "discard":
      return applyDiscard(s, intent);
    case "declareBigGin":
      return applyDeclareBigGin(s, intent.seat);
    case "layoffAttach":
      return applyLayoffAttach(s, intent);
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
    return { ok: true, state };
  }

  if (state.upcardOffer.stage === "dealer") {
    if (seat !== d) return { ok: false, error: "Wrong seat" };
    if (!state.upcardOffer.nonDealerPassed) return { ok: false, error: "Invalid pass order" };
    state.upcardOffer = null;
    state.phase = "play";
    state.currentTurn = nd;
    return { ok: true, state };
  }

  return { ok: false, error: "Invalid pass" };
}

function applyDrawStock(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase === "play") {
    if (state.currentTurn !== seat) return { ok: false, error: "Not your turn" };
    if (state.hands[seat].length !== 10) return { ok: false, error: "Expected 10 cards before draw" };
    if (state.stock.length === 0) return { ok: false, error: "Stock empty" };
    const c = state.stock.pop()!;
    state.hands[seat].push(c);
    markSeen(state, c, [seat]);
    return { ok: true, state };
  }

  if (state.phase === "upcardOffer") {
    const nd = state.nonDealer;
    if (seat !== nd) return { ok: false, error: "Only non-dealer draws after two passes" };
    if (!state.upcardOffer || state.upcardOffer.stage !== "dealer" || !state.upcardOffer.nonDealerPassed) {
      return { ok: false, error: "Passes not complete" };
    }
    if (state.hands[seat].length !== 10) return { ok: false, error: "Invalid hand size" };
    if (state.stock.length === 0) return { ok: false, error: "Stock empty" };
    const c = state.stock.pop()!;
    state.hands[seat].push(c);
    markSeen(state, c, [seat]);
    state.upcardOffer = null;
    state.phase = "play";
    state.currentTurn = nd;
    return { ok: true, state };
  }

  return { ok: false, error: "Cannot draw now" };
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
  return { ok: true, state };
}

function applyDiscard(state: ServerTruth, intent: Intent): ApplyOutcome {
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
     * Equality knock: after discarding, the knocker's best deadwood total must equal the
     * first upcard's deadwood value (same as knock points: A=1, 2–9 face, T/J/Q/K=10).
     * Ace as first upcard ⇒ no knock this hand (`upcardKnockValue` is null).
     */
    if (knockVal === null) return { ok: false, error: "Cannot knock when knock card is an Ace" };
    if (layout) {
      if (!validateKnockerLayout(hand10, layout.melds, layout.deadwood)) {
        return { ok: false, error: "Invalid knocker layout" };
      }
      const supplied = deadwoodTotal(layout.deadwood);
      if (supplied === 0) return { ok: false, error: "Must declare gin with deadwood 0" };
      if (supplied !== knockVal) {
        return {
          ok: false,
          error: `Knock requires deadwood exactly ${knockVal} (first upcard); supplied layout has ${supplied}.`,
        };
      }
      resolvedKnockMelds = layout.melds;
      resolvedKnockDeadwood = layout.deadwood;
    } else {
      const best = bestDeadwood(hand10);
      if (best.sum === 0) return { ok: false, error: "Must declare gin with deadwood 0" };
      if (best.sum !== knockVal) {
        return {
          ok: false,
          error: `Knock requires deadwood exactly ${knockVal} (first upcard); best layout from this discard is ${best.sum}.`,
        };
      }
      resolvedKnockMelds = best.partition.melds;
      resolvedKnockDeadwood = best.partition.deadwood;
    }
  } else {
    const best = bestAfterDiscard11(hand);
    if (best.bestSum === 0) {
      return { ok: false, error: "Must declare gin with deadwood 0" };
    }
  }

  state.hands[seat] = hand10;
  state.discard.push(card);
  markSeen(state, card, [0, 1]);

  if (gin) {
    const opp = otherSeat(seat);
    const pts = scoreGin(state.hands[opp]);
    awardHand(state, seat, pts);
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
  const pts = scoreEO(state.hands[opp]);
  state.hands[seat] = [];
  awardHand(state, seat, pts);
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

function applyLayoffDone(state: ServerTruth, seat: Seat): ApplyOutcome {
  if (state.phase !== "knockLayoff" || !state.knock) return { ok: false, error: "No knock layoff" };
  if (state.knock.layoffTurn !== seat) return { ok: false, error: "Not layoff turn" };
  const knocker = state.knock.knocker;
  if (seat === knocker) return { ok: false, error: "Knocker cannot finish layoff" };

  /**
   * Greedy auto-layoff: attach every opponent deadwood card that legally extends
   * one of the knocker's melds before scoring. The client UI today only exposes a
   * "Done" button, so without this the opponent always loses their entire hand as
   * deadwood — even cards that obviously fit on the knocker's runs/sets.
   */
  const beforeDeadwood = [...state.knock.opponentDeadwood];
  const { melds: newMelds, opponentDeadwood: newDeadwood } = applyLayoffsGreedy(
    state.knock.knockerMeldsAfterLayoff,
    beforeDeadwood,
  );
  const attached = beforeDeadwood.filter((c) => !newDeadwood.includes(c));
  state.knock.knockerMeldsAfterLayoff = newMelds;
  state.knock.opponentDeadwood = newDeadwood;
  for (const c of attached) {
    const hi = state.hands[seat].indexOf(c);
    if (hi >= 0) state.hands[seat].splice(hi, 1);
    markSeen(state, c, [0, 1]);
  }

  const { winner, points } = resolveKnockFinal({
    knocker,
    knockerDeadwood: state.knock.knockerDeadwood,
    opponentDeadwood: state.knock.opponentDeadwood,
  });

  state.hands[knocker] = [];
  state.hands[otherSeat(knocker)] = [];
  awardHand(state, winner, points);
  state.knock = null;
  return { ok: true, state };
}
