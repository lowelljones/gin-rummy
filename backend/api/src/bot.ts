import { isBigGin11, type Intent, type ServerTruth, type Seat } from "../../rules/src/index.js";

const TEST_BOT_SEAT: Seat = 1;

export function getTestBotSeat(): Seat {
  return TEST_BOT_SEAT;
}

/**
 * Dumb test bot: pass on upcard offers, first spread card on cut, then always draw
 * from stock and discard the last card in hand. Auto ack hands. On knock layoff, ends layoff immediately.
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
    return { type: "ackHandOver" };
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
  if (state.phase === "handOver") return true;
  if (state.phase === "cutForDeal" && state.cut) {
    if (state.cut.picks[TEST_BOT_SEAT] !== null) return false;
    return cutActivePicker(state.cut) === TEST_BOT_SEAT;
  }
  if (state.currentTurn === TEST_BOT_SEAT) return true;
  return false;
}

