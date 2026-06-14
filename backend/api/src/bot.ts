import { isBigGin11, type CardId, type Intent, type ServerTruth, type Seat } from "../../rules/src/index.js";

const TEST_BOT_SEAT: Seat = 1;

export function getTestBotSeat(): Seat {
  return TEST_BOT_SEAT;
}

/**
 * Dumb test bot: pass on upcard offers, first spread card on cut, then always draw
 * from stock and discard the last card in hand. On knock layoff, ends layoff immediately.
 *
 * Hand-over acks are per-seat (ready-up): the bot acks its own seat right away, but
 * the next hand only deals after the human also taps Continue — so the human always
 * sees the end-of-hand reveal at their own pace.
 */
function cutActivePicker(cut: NonNullable<ServerTruth["cut"]>): Seat {
  const first = (cut.firstSeat ?? 0) as Seat;
  const [p0, p1] = cut.picks;
  if (p0 === null && p1 === null) return first;
  if (p0 === null) return 0;
  if (p1 === null) return 1;
  return first;
}

/** Match engine repair: down-card phase without an offer object is treated as play. */
function botPlayPhase(state: ServerTruth): boolean {
  return state.phase === "play" || (state.phase === "upcardOffer" && !state.upcardOffer);
}

function plainDiscardIntent(hand: CardId[]): Intent {
  const card = hand[hand.length - 1]!;
  return { type: "discard", seat: TEST_BOT_SEAT, card, knock: false, gin: false };
}

export function computeTestBotIntent(state: ServerTruth): Intent | null {
  if (state.phase === "matchOver") return null;
  if (state.phase === "handOver") {
    /* Ready up the bot's seat; the hand only advances once the human also acks. */
    const acks = state.handOverAcks;
    if (acks && !acks[TEST_BOT_SEAT]) {
      return { type: "ackHandOver", seat: TEST_BOT_SEAT };
    }
    return null;
  }
  if (state.redeal?.status === "pending" && state.redeal.fromSeat !== TEST_BOT_SEAT) {
    return { type: "respondRedeal", seat: TEST_BOT_SEAT, accept: true };
  }
  if (state.phase === "cutForDeal" && state.cut) {
    if (state.cut.picks[TEST_BOT_SEAT] !== null) return null;
    if (cutActivePicker(state.cut) !== TEST_BOT_SEAT) return null;
    if (state.cut.spread.length === 0) return null;
    return { type: "cutPick", seat: TEST_BOT_SEAT, index: 0 };
  }
  if (state.currentTurn !== TEST_BOT_SEAT) return null;

  if (state.phase === "upcardOffer" && state.upcardOffer) {
    return { type: "upcardPass", seat: TEST_BOT_SEAT };
  }

  if (botPlayPhase(state)) {
    const hand = state.hands[TEST_BOT_SEAT];
    if (hand.length === 10) {
      if (state.stock.length <= 1) {
        return { type: "passStock", seat: TEST_BOT_SEAT };
      }
      return { type: "drawStock", seat: TEST_BOT_SEAT };
    }
    if (hand.length === 11) {
      if (isBigGin11(hand)) {
        return { type: "declareBigGin", seat: TEST_BOT_SEAT };
      }
      return plainDiscardIntent(hand);
    }
  }

  if (state.phase === "knockLayoff" && state.knock) {
    if (state.knock.layoffTurn !== TEST_BOT_SEAT) return null;
    return { type: "layoffDone", seat: TEST_BOT_SEAT };
  }

  return null;
}

export function hasTestBotWork(state: ServerTruth): boolean {
  return computeTestBotIntent(state) !== null;
}

/** If EO declaration fails, fall back to a plain discard so the bot never stalls at 11. */
export function fallbackTestBotIntent(state: ServerTruth, failed: Intent): Intent | null {
  if (failed.type !== "declareBigGin") return null;
  if (!botPlayPhase(state) || state.currentTurn !== TEST_BOT_SEAT) return null;
  const hand = state.hands[TEST_BOT_SEAT];
  if (hand.length !== 11) return null;
  return plainDiscardIntent(hand);
}
