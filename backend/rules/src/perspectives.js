function maskHand(viewer, owner, hand, seenBy) {
    if (viewer === owner)
        return [...hand];
    return hand.map((c) => {
        const s = seenBy[c];
        if (s && s[viewer])
            return c;
        return "HIDDEN";
    });
}
function buildCutPerspective(cut, viewer) {
    const firstCutSeat = (cut.firstSeat ?? 0);
    const p0p = cut.picks[0];
    const p1p = cut.picks[1];
    const other = (1 - viewer);
    const otherPicked = cut.picks[other] !== null;
    const bothDone = p0p !== null && p1p !== null;
    let activePicker;
    if (bothDone) {
        activePicker = firstCutSeat;
    }
    else if (p0p === null && p1p === null) {
        activePicker = firstCutSeat;
    }
    else if (p0p === null) {
        activePicker = 0;
    }
    else {
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
export function buildPerspective(state, viewer) {
    const hands = [
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
        scores: [...state.scores],
        handsWon: [...state.handsWon],
        raceTarget: state.raceTarget,
        upcardOffer: state.upcardOffer,
        knock: state.knock,
        knockCheckCard: state.knockCheckCard,
        lastCut: state.lastCutResult ?? null,
        cut: state.cut ? buildCutPerspective(state.cut, viewer) : null,
        inferred: {},
    };
}
export function buildPerspectives(state) {
    return {
        "0": buildPerspective(state, 0),
        "1": buildPerspective(state, 1),
    };
}
