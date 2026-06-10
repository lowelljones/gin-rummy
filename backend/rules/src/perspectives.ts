import type { CardId } from "./cards.js";
import type { HandResult, Seat, ServerTruth } from "./types.js";

export type MaskedCard = CardId | "HIDDEN";

export interface PlayerPerspective {
  seat: Seat;
  hands: [MaskedCard[] | CardId[], MaskedCard[] | CardId[]];
  stockCount: number;
  discard: CardId[];
  phase: ServerTruth["phase"];
  dealer: Seat;
  nonDealer: Seat;
  currentTurn: Seat;
  scores: [number, number];
  handsWon: [number, number];
  raceTarget: number;
  upcardOffer: ServerTruth["upcardOffer"];
  knock: ServerTruth["knock"];
  /** First upcard for this hand (knock limit); does not change when the discard pile turns over. */
  knockCheckCard: CardId | null;
  /** First hand only — both cut cards, until the next hand is dealt. */
  lastCut: { p0: CardId; p1: CardId; nonDealer: Seat } | null;
  /** High-card cut: face-down spread; each pick is visible to both players after it is made. */
  cut: CutPerspective | null;
  /** Mid-hand mutual redeal proposal (optional on legacy rows). */
  redeal: null | { fromSeat: Seat; status: "pending" | "declined" };
  /** Full reveal of the last hand (both layouts) during handOver / matchOver. */
  handResult: HandResult | null;
  /** Per-seat Continue acks during handOver (next hand deals when both are true). */
  handOverAcks: [boolean, boolean] | null;
  /** Cards opponent is known to hold (from draws you did not see — usually empty). */
  inferred: Record<string, unknown>;
}

export interface CutPerspective {
  faceDownRemaining: number;
  activePicker: Seat;
  youMustPick: boolean;
  /** Your card once you have cut from the spread (visible to both players after your pick). */
  yourCut: CardId | null;
  /** The other seat has already cut; you see their card after their pick. */
  opponentHasPicked: boolean;
  /** Opponent's revealed cut card once they have picked; null until then. */
  theirCut: CardId | null;
  /** Who was chosen to cut first (legacy states omit this and default to 0). */
  firstCutSeat: Seat;
}

function maskHand(viewer: Seat, owner: Seat, hand: CardId[], seenBy: ServerTruth["seenBy"]): MaskedCard[] {
  if (viewer === owner) return [...hand];
  return hand.map((c) => {
    const s = seenBy[c];
    if (s && s[viewer]) return c;
    return "HIDDEN";
  });
}

function buildCutPerspective(cut: NonNullable<ServerTruth["cut"]>, viewer: Seat): CutPerspective {
  const firstCutSeat = (cut.firstSeat ?? 0) as Seat;
  const p0p = cut.picks[0];
  const p1p = cut.picks[1];
  const other = (1 - viewer) as Seat;
  const otherPicked = cut.picks[other] !== null;
  const bothDone = p0p !== null && p1p !== null;
  let activePicker: Seat;
  if (bothDone) {
    activePicker = firstCutSeat;
  } else if (p0p === null && p1p === null) {
    activePicker = firstCutSeat;
  } else if (p0p === null) {
    activePicker = 0;
  } else {
    activePicker = 1;
  }
  const youMustPick = !bothDone && viewer === activePicker;
  const theirPick = cut.picks[other];
  return {
    faceDownRemaining: cut.spread.length,
    activePicker,
    youMustPick,
    yourCut: cut.picks[viewer],
    opponentHasPicked: otherPicked,
    theirCut: otherPicked && theirPick !== null ? theirPick : null,
    firstCutSeat,
  };
}

export function buildPerspective(state: ServerTruth, viewer: Seat): PlayerPerspective {
  const hands: [MaskedCard[] | CardId[], MaskedCard[] | CardId[]] = [
    maskHand(viewer, 0, state.hands[0], state.seenBy),
    maskHand(viewer, 1, state.hands[1], state.seenBy),
  ];
  return {
    seat: viewer,
    hands,
    stockCount: state.stock.length,
    discard: [...state.discard],
    phase: state.phase,
    dealer: state.dealer,
    nonDealer: state.nonDealer,
    currentTurn: state.currentTurn,
    scores: [...state.scores] as [number, number],
    handsWon: [...state.handsWon] as [number, number],
    raceTarget: state.raceTarget,
    upcardOffer: state.upcardOffer,
    knock: state.knock,
    knockCheckCard: state.knockCheckCard,
    lastCut: state.lastCutResult ?? null,
    cut: state.cut ? buildCutPerspective(state.cut, viewer) : null,
    redeal: state.redeal ?? null,
    handResult: state.lastHandResult ?? null,
    handOverAcks: state.handOverAcks ?? null,
    inferred: {},
  };
}

export function buildPerspectives(state: ServerTruth): { "0": PlayerPerspective; "1": PlayerPerspective } {
  return {
    "0": buildPerspective(state, 0),
    "1": buildPerspective(state, 1),
  };
}
