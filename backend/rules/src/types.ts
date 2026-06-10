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

/** One seat's final layout when a hand ends (used by the end-of-hand reveal). */
export interface HandResultSide {
  melds: Meld[];
  /** Cards that counted against this seat (unmelded, after any layoffs). */
  deadwood: CardId[];
  deadwoodPoints: number;
}

/**
 * Full reveal of how the hand ended: both layouts, the laid-off cards, and the
 * score delta. Exposed to both players during `handOver` / `matchOver` and
 * cleared when the next hand is dealt.
 */
export interface HandResult {
  kind: "gin" | "bigGin" | "knock" | "undercut";
  winner: Seat;
  points: number;
  /** Seat that ended the hand (the ginner or knocker). */
  closer: Seat;
  /** Indexed by seat. Laid-off cards appear inside the closer's melds. */
  sides: [HandResultSide, HandResultSide];
  /** Defender cards attached onto the closer's melds (knock hands only). */
  layoffs: { card: CardId; meldIndex: number }[];
}

/** How a seat picked up the card that brought them to 11 (attached to their discard). */
export type PickupKind = "drawStock" | "takeDiscard" | "takeDownCard";

/**
 * Server-authoritative record of the most recent draw/take/pass/discard. Both
 * clients build their activity log from this instead of diffing polled
 * snapshots, so the two players always see the same (correct) pickup story.
 * Stock-draw card faces are masked per viewer in perspectives.
 */
export interface LastAction {
  /** Monotonic per-game counter so clients can detect new actions across polls. */
  seq: number;
  seat: Seat;
  type: "passUpcard" | "takeDownCard" | "drawStock" | "takeDiscard" | "discard";
  /** Card drawn / taken / discarded by this action (null for passes). */
  card: CardId | null;
  /** Discards only: how the discarding seat picked up earlier this turn. */
  pickup: { type: PickupKind; card: CardId | null } | null;
}

export interface KnockState {
  knocker: Seat;
  knockCard: CardId;
  knockerMelds: Meld[];
  knockerDeadwood: CardId[];
  opponentOriginalHand: CardId[];
  /**
   * Opponent cards not yet laid off — mutated through layoff intents. After layoffDone
   * this holds only the opponent's truly unmelded cards (own melds excluded).
   */
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

  /** Full reveal of the last hand (omitted in legacy persisted rows — treated as null). */
  lastHandResult?: HandResult | null;

  /**
   * Per-seat hand-over acknowledgments: the next hand deals once both are true.
   * Omitted in legacy rows. A legacy unscoped `ackHandOver` advances immediately.
   */
  handOverAcks?: [boolean, boolean] | null;

  /** Betting settlement at match end. */
  bettingRaw: number | null;
  bettingBucket: number | null;

  /** Visibility: cardId -> which seats have seen this specific card face. */
  seenBy: Record<string, [boolean, boolean]>;

  /** Most recent draw/take/pass/discard, for client activity logs. Omitted in legacy rows. */
  lastAction?: LastAction | null;

  /** The acting seat's pickup this turn — consumed by their discard. Omitted in legacy rows. */
  turnPickup?: { seat: Seat; type: PickupKind; card: CardId } | null;

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
  /**
   * Defender's full response to a knock in one shot: their own meld partition plus
   * an ordered list of layoffs onto the knocker's melds. Whatever is left over
   * counts against them — the server does NOT optimize on their behalf.
   */
  | {
      type: "layoffResolve";
      seat: Seat;
      ownMelds: Meld[];
      layoffs: { card: CardId; meldIndex: number }[];
    }
  /** Seat-scoped acks ready-up (both required); legacy seatless ack advances immediately. */
  | { type: "ackHandOver"; seat?: Seat }
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
