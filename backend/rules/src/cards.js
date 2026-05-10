export const SUITS = ["S", "H", "D", "C"];
export const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K"];
const RANK_INDEX = {
    A: 1,
    "2": 2,
    "3": 3,
    "4": 4,
    "5": 5,
    "6": 6,
    "7": 7,
    "8": 8,
    "9": 9,
    T: 10,
    J: 11,
    Q: 12,
    K: 13,
};
/** Ace-low run order (A=1 … K=13). */
export function rankOrderLow(card) {
    return RANK_INDEX[parseRank(card)];
}
/** Deadwood / knock comparison value: A=1, 2–9 face, T/J/Q/K=10. */
export function deadwoodValue(card) {
    const r = parseRank(card);
    if (r === "T" || r === "J" || r === "Q" || r === "K")
        return 10;
    if (r === "A")
        return 1;
    return RANK_INDEX[r];
}
/** Cut comparison: suit strength S>H>D>C, ace-high rank. */
export function suitStrength(suit) {
    const order = { S: 4, H: 3, D: 2, C: 1 };
    return order[suit];
}
export function cutRankStrength(card) {
    const r = parseRank(card);
    if (r === "A")
        return 14;
    return RANK_INDEX[r];
}
export function compareCutCards(a, b) {
    // Rank is primary; suit is tie-breaker.
    const ra = cutRankStrength(a);
    const rb = cutRankStrength(b);
    if (ra !== rb)
        return ra - rb;
    const sa = suitStrength(parseSuit(a));
    const sb = suitStrength(parseSuit(b));
    return sa - sb;
}
export function parseRank(card) {
    return card[0];
}
export function parseSuit(card) {
    return card[1];
}
export function buildDeck() {
    const deck = [];
    for (const s of SUITS) {
        for (const r of RANKS) {
            deck.push(`${r}${s}`);
        }
    }
    return deck;
}
export function shuffleDeck(deck, rng) {
    const copy = [...deck];
    for (let i = copy.length - 1; i > 0; i--) {
        const j = Math.floor(rng() * (i + 1));
        [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
}
export function upcardKnockValue(card) {
    if (!card)
        return null;
    if (parseRank(card) === "A")
        return null;
    return deadwoodValue(card);
}
