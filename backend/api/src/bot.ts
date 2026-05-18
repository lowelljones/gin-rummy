import { isBigGin11, type Intent, type ServerTruth, type Seat } from "../../rules/src/index.js";

const TEST_BOT_SEAT: Seat = 1;

export function getTestBotSeat(): Seat {
  return TEST_BOT_SEAT;
}

/**
 * Dumb test bot: pass on upcard offers, first spread card on cut, then always draw
 * from stock and discard the last card in hand. On knock layoff, ends layoff immediately.
 *
 * The bot intentionally does NOT ack `handOver`: `ackHandOver` is unscoped (no seat),
 * so if the bot acked, it would advance straight into the next hand's down-card phase
 * before the human ever saw the End-of-hand screen. Instead, the human must always
 * tap Continue, which guarantees they see the handOver UI and then the down-card phase
 * for hand 2 and beyond.
 */
function cutActivePicker(cut: NonNullable<ServerTruth["cut"]>): Seat {
  const first = (cut.firstSeat ?? 0) as Seat;
  const [p0, p1] = cut.picks;
  if (p0 === null && p1 === null) return first;
  if (p0 === null) return 0;
  if (p1 === null) return 1;
  return first;
}

export function computeTestBotIntent(state: ServerTruth): Intent | null {
  if (state.phase === "matchOver") return null;
  if (state.phase === "handOver") {
    /* Wait for the human to ackHandOver; otherwise the bot would auto-advance
     * past the End-of-hand screen and the hand-2+ down-card phase. */
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

  if (state.phase === "play") {
    const hand = state.hands[TEST_BOT_SEAT];
    if (hand.length === 10) {
      return { type: "drawStock", seat: TEST_BOT_SEAT };
    }
    if (hand.length === 11) {
      if (isBigGin11(hand)) {
        return { type: "declareBigGin", seat: TEST_BOT_SEAT };
      }
      const drawn = hand[hand.length - 1]!;
      return { type: "discard", seat: TEST_BOT_SEAT, card: drawn, knock: false, gin: false };
    }
  }

  if (state.phase === "knockLayoff" && state.knock) {
    if (state.knock.layoffTurn !== TEST_BOT_SEAT) return null;
    return { type: "layoffDone", seat: TEST_BOT_SEAT };
  }

  return null;
}

export function hasTestBotWork(state: ServerTruth): boolean {
  if (state.phase === "matchOver") return false;
  /* Never auto-ack handOver — the human must press Continue so they see the
   * end-of-hand UI and the upcardOffer ("down card") UI on the next deal. */
  if (state.phase === "handOver") return false;
  if (state.redeal?.status === "pending" && state.redeal.fromSeat !== TEST_BOT_SEAT) return true;
  if (state.phase === "cutForDeal" && state.cut) {
    if (state.cut.picks[TEST_BOT_SEAT] !== null) return false;
    return cutActivePicker(state.cut) === TEST_BOT_SEAT;
  }
  if (state.currentTurn === TEST_BOT_SEAT) return true;
  return false;
}

