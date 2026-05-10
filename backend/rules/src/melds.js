import { deadwoodValue, parseRank, parseSuit, rankOrderLow, } from "./cards.js";
function sortCards(cards) {
    return [...cards].sort();
}
function isValidSet(cards) {
    if (cards.length < 3 || cards.length > 4)
        return false;
    const ranks = new Set(cards.map(parseRank));
    if (ranks.size !== 1)
        return false;
    const suits = cards.map(parseSuit);
    if (new Set(suits).size !== cards.length)
        return false;
    return true;
}
function isValidRun(cards) {
    if (cards.length < 3)
        return false;
    const suit = parseSuit(cards[0]);
    if (!cards.every((c) => parseSuit(c) === suit))
        return false;
    const orders = [...new Set(cards.map(rankOrderLow))].sort((a, b) => a - b);
    if (orders.length !== cards.length)
        return false;
    for (let i = 1; i < orders.length; i++) {
        if (orders[i] !== orders[i - 1] + 1)
            return false;
    }
    return true;
}
export function isValidMeld(meld) {
    const cs = meld.cards;
    if (meld.type === "set")
        return isValidSet(cs);
    return isValidRun(cs);
}
function deadwoodSum(deadwood) {
    return deadwood.reduce((s, c) => s + deadwoodValue(c), 0);
}
function subsetsOfSize(arr, k) {
    const res = [];
    function rec(start, chosen) {
        if (chosen.length === k) {
            res.push([...chosen]);
            return;
        }
        for (let i = start; i < arr.length; i++) {
            chosen.push(arr[i]);
            rec(i + 1, chosen);
            chosen.pop();
        }
    }
    rec(0, []);
    return res;
}
/** Enumerate meld partitions; return minimum deadwood sum and one optimal partition. */
export function bestDeadwood(hand) {
    if (new Set(hand).size !== hand.length) {
        throw new Error("Hand contains duplicate cards");
    }
    const cards = sortCards(hand);
    let best = {
        sum: Infinity,
        partition: { melds: [], deadwood: [...hand] },
    };
    function dfs(remaining, meldsSoFar) {
        if (remaining.length === 0) {
            if (0 < best.sum) {
                best = { sum: 0, partition: { melds: meldsSoFar, deadwood: [] } };
            }
            return;
        }
        if (remaining.length < 3) {
            const s = deadwoodSum(remaining);
            if (s < best.sum) {
                best = { sum: s, partition: { melds: meldsSoFar, deadwood: [...remaining] } };
            }
            return;
        }
        for (let len = Math.min(4, remaining.length); len >= 3; len--) {
            for (const combo of subsetsOfSize(remaining, len)) {
                const setM = { type: "set", cards: sortCards(combo) };
                const runM = { type: "run", cards: sortCards(combo) };
                for (const meld of [setM, runM]) {
                    if (!isValidMeld(meld))
                        continue;
                    const used = new Set(meld.cards);
                    const rest = remaining.filter((c) => !used.has(c));
                    dfs(rest, [...meldsSoFar, meld]);
                }
            }
        }
        const s = deadwoodSum(remaining);
        if (s < best.sum) {
            best = { sum: s, partition: { melds: meldsSoFar, deadwood: [...remaining] } };
        }
    }
    dfs(cards, []);
    if (!Number.isFinite(best.sum)) {
        best = { sum: deadwoodSum(cards), partition: { melds: [], deadwood: [...cards] } };
    }
    return best;
}
/** Best deadwood after drawing to 11 and discarding exactly one card. */
export function bestAfterDiscard11(hand11) {
    if (hand11.length !== 11)
        throw new Error("Expected 11 cards");
    let bestSum = Infinity;
    let bestDiscard = hand11[0];
    let bestPart = { melds: [], deadwood: [] };
    for (const d of hand11) {
        const ten = hand11.filter((c) => c !== d);
        if (ten.length !== 10)
            continue;
        const { sum, partition } = bestDeadwood(ten);
        if (sum < bestSum) {
            bestSum = sum;
            bestDiscard = d;
            bestPart = partition;
        }
    }
    return { bestSum, discard: bestDiscard, partition10: bestPart };
}
/** True if all 11 cards can be partitioned into valid melds (EO / big gin). */
export function isBigGin11(hand11) {
    if (hand11.length !== 11)
        return false;
    function canPartition(remaining) {
        if (remaining.length === 0)
            return true;
        if (remaining.length < 3)
            return false;
        for (let len = Math.min(remaining.length, 4); len >= 3; len--) {
            for (const combo of subsetsOfSize(remaining, len)) {
                const setM = { type: "set", cards: sortCards(combo) };
                const runM = { type: "run", cards: sortCards(combo) };
                for (const meld of [setM, runM]) {
                    if (!isValidMeld(meld))
                        continue;
                    const used = new Set(meld.cards);
                    const rest = remaining.filter((c) => !used.has(c));
                    if (canPartition(rest))
                        return true;
                }
            }
        }
        return false;
    }
    return canPartition([...hand11]);
}
/** Attach opponent cards to knocker melds (greedy), return updated melds + remaining opponent deadwood. */
export function applyLayoffsGreedy(knockerMelds, opponentHand) {
    const melds = knockerMelds.map((m) => ({ ...m, cards: [...m.cards] }));
    const remaining = [...opponentHand];
    const tryAttach = (card) => {
        const r = parseRank(card);
        const s = parseSuit(card);
        for (const meld of melds) {
            if (meld.type === "set") {
                const rank = parseRank(meld.cards[0]);
                if (rank !== r)
                    continue;
                const suits = new Set(meld.cards.map(parseSuit));
                if (suits.has(s) || meld.cards.length >= 4)
                    continue;
                meld.cards.push(card);
                if (isValidSet(meld.cards))
                    return true;
                meld.cards.pop();
            }
            else {
                const suit = parseSuit(meld.cards[0]);
                if (suit !== s)
                    continue;
                const orders = meld.cards.map(rankOrderLow);
                const o = rankOrderLow(card);
                const min = Math.min(...orders);
                const max = Math.max(...orders);
                if (o === min - 1 || o === max + 1) {
                    meld.cards.push(card);
                    meld.cards.sort((a, b) => rankOrderLow(a) - rankOrderLow(b));
                    if (isValidRun(meld.cards))
                        return true;
                    meld.cards.splice(meld.cards.findIndex((c) => c === card), 1);
                }
            }
        }
        return false;
    };
    let progress = true;
    while (progress) {
        progress = false;
        for (let i = 0; i < remaining.length; i++) {
            const c = remaining[i];
            if (tryAttach(c)) {
                remaining.splice(i, 1);
                progress = true;
                break;
            }
        }
    }
    return { melds, opponentDeadwood: remaining };
}
