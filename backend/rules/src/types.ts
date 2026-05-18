import type { CardId } from "./cards.js";
import type { Meld } from "./melds.js";

export type Seat = 0 | 1;

export type Phase =
  | "cutForDeal"
  | "upcardOffer"
  | "play"
  | "knockLayoff"
  | "handOver"
  | "matchOver";

export interface UpcardOfferState {
  stage: "nonDealer" | "dealer";
  nonDealerPassed: boolean;
}

export interface KnockState {
  knocker: Seat;
  knockCard: CardId;
  knockerMelds: Meld[];
  knockerDeadwood: CardId[];
  opponentOriginalHand: CardId[];
  /** After layoffs — mutated through layoff intents. */
  opponentDeadwood: CardId[];
  knockerMeldsAfterLayoff: Meld[];
  layoffTurn: Seat;
}

/** Authoritative server state (serializable). */
export interface ServerTruth {
  version: 1;
  phase: Phase;
  handIndex: number;
  /** Winner of previous hand deals; for hand 0 set after cut. */
  dealer: Seat;
  /** Non-dealer; first to act on upcard / leads play. */
  nonDealer: Seat;
  /** Race scores (first to >= target wins match). */
  scores: [number, number];
  handsWon: [number, number];
  raceTarget: number;

  stock: CardId[];
  discard: CardId[];
  hands: [CardId[], CardId[]];
  currentTurn: Seat;

  /** First hand only — high-card cut. `firstSeat` picks first (randomized at match start). */
  cut: null | {
    spread: CardId[];
    picks: [CardId | null, CardId | null];
    /** Who cuts first; omitted in legacy persisted games (defaults to 0). */
    firstSeat?: Seat;
  };

  /** Shown to clients right after the cut; cleared when the next hand begins. (Optional on legacy stored rows.) */
  lastCutResult?: { p0: CardId; p1: CardId; nonDealer: Seat } | null;

  upcardOffer: UpcardOfferState | null;

  /**
   * First upcard placed to the table when the hand was dealt (same as `discard[0]` at that moment).
   * Fixed for the entire hand — not the current discard pile top. Determines equality knock;
   * if this card is any ace, neither player may knock for the hand.
   */
  knockCheckCard: CardId | null;

  knock: KnockState | null;

  /** Winner seat if phase is handOver (before advancing). */
  lastHandWinner: Seat | null;
  lastHandPoints: number | null;

  /** Betting settlement at match end. */
  bettingRaw: number | null;
  bettingBucket: number | null;

  /** Visibility: cardId -> which seats have seen this specific card face. */
  seenBy: Record<string, [boolean, boolean]>;

  /**
   * Optional mid-hand redeal request (same hand index / scores if redealt).
   * Omitted in legacy persisted rows — treated as null.
   */
  redeal?: null | { fromSeat: Seat; status: "pending" | "declined" };
}

export interface KnockerLayout {
  melds: Meld[];
  deadwood: CardId[];
}

export type Intent =
  /** `index` is 0..spread.length-1 into the face-down spread. */
  | { type: "cutPick"; seat: Seat; index: number }
  | { type: "upcardTake"; seat: Seat }
  | { type: "upcardPass"; seat: Seat }
  | { type: "drawStock"; seat: Seat }
  /** Play phase: take top of discard instead of stock (10 cards, your turn). */
  | { type: "takeDiscard"; seat: Seat }
  | { type: "discard"; seat: Seat; card: CardId; knock: boolean; gin: boolean; layout?: KnockerLayout }
  | { type: "declareBigGin"; seat: Seat }
  | { type: "layoffDone"; seat: Seat }
  | { type: "layoffAttach"; seat: Seat; card: CardId; meldIndex: number }
  | { type: "ackHandOver" }
  | { type: "proposeRedeal"; seat: Seat }
  | { type: "respondRedeal"; seat: Seat; accept: boolean };

export interface ApplyResult {
  ok: true;
  state: ServerTruth;
}

export interface ApplyError {
  ok: false;
  error: string;
}

export type ApplyOutcome = ApplyResult | ApplyError;
