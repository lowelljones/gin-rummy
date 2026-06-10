import { describe, expect, it } from "vitest";
import {
  bestAfterDiscard11,
  bestDeadwood,
  bestLayoff,
  isBigGin11,
  isValidMeld,
  type Meld,
} from "./melds.js";

describe("isValidMeld", () => {
  it("accepts sets of 3 or 4 of the same rank in distinct suits", () => {
    expect(isValidMeld({ type: "set", cards: ["7S", "7H", "7D"] })).toBe(true);
    expect(isValidMeld({ type: "set", cards: ["7S", "7H", "7D", "7C"] })).toBe(true);
  });

  it("rejects short, mixed-rank, or duplicate-suit sets", () => {
    expect(isValidMeld({ type: "set", cards: ["7S", "7H"] })).toBe(false);
    expect(isValidMeld({ type: "set", cards: ["7S", "8H", "7D"] })).toBe(false);
    expect(isValidMeld({ type: "set", cards: ["7S", "7S", "7D"] })).toBe(false);
  });

  it("accepts same-suit consecutive runs of 3+ (ace low)", () => {
    expect(isValidMeld({ type: "run", cards: ["AS", "2S", "3S"] })).toBe(true);
    expect(isValidMeld({ type: "run", cards: ["9H", "TH", "JH", "QH", "KH"] })).toBe(true);
  });

  it("rejects gaps, suit mixes, and around-the-corner runs", () => {
    expect(isValidMeld({ type: "run", cards: ["3S", "4S", "6S"] })).toBe(false);
    expect(isValidMeld({ type: "run", cards: ["3S", "4H", "5S"] })).toBe(false);
    /* K-A-2 is not a legal run: ace is low only. */
    expect(isValidMeld({ type: "run", cards: ["QS", "KS", "AS"] })).toBe(false);
  });
});

describe("bestDeadwood", () => {
  it("finds zero deadwood for a gin hand", () => {
    const { sum, partition } = bestDeadwood([
      "AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "KS",
    ]);
    expect(sum).toBe(0);
    expect(partition.deadwood).toEqual([]);
    expect(partition.melds).toHaveLength(3);
  });

  it("prefers the partition with the lowest unmelded total", () => {
    /* 5S can join the 5s set OR the 5-6-7 run; only the run keeps 6S/7S melded. */
    const { sum } = bestDeadwood([
      "5S", "6S", "7S", "5C", "5D", "5H", "2D", "9C", "QH", "KH",
    ]);
    /* Best: 5S-6S-7S run is impossible together with the 5s set (5S shared);
       keep run + 5C/5D/5H needs 5S — so set of three 5s (5C,5D,5H) + run uses 5S.
       Deadwood: 2D + 9C + QH + KH = 2 + 9 + 10 + 10 = 31. */
    expect(sum).toBe(31);
  });

  it("throws on duplicate cards", () => {
    expect(() => bestDeadwood(["5S", "5S", "6S"])).toThrow(/duplicate/i);
  });
});

describe("bestAfterDiscard11", () => {
  it("identifies the discard that reaches gin", () => {
    const hand11 = [
      "AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "KS", "4C",
    ] as const;
    const res = bestAfterDiscard11([...hand11]);
    expect(res.bestSum).toBe(0);
    expect(res.discard).toBe("4C");
  });

  it("throws unless given exactly 11 cards", () => {
    expect(() => bestAfterDiscard11(["AS", "2S"])).toThrow(/11/);
  });
});

describe("isBigGin11", () => {
  it("true when all 11 cards meld", () => {
    expect(
      isBigGin11(["AS", "2S", "3S", "4S", "7H", "8H", "9H", "KC", "KD", "KH", "KS"]),
    ).toBe(true);
  });

  it("false when any card is stranded", () => {
    expect(
      isBigGin11(["AS", "2S", "3S", "4S", "7H", "8H", "9H", "KC", "KD", "KH", "2C"]),
    ).toBe(false);
  });
});

describe("bestLayoff", () => {
  const knockerMelds: Meld[] = [
    { type: "set", cards: ["5C", "5D", "5H"] },
    { type: "run", cards: ["9H", "TH", "JH"] },
  ];

  it("does not greedily lay off when keeping an own meld is better", () => {
    /* Laying 5S onto the 5s set would strand 6S+7S (13); keeping the run leaves 0. */
    const res = bestLayoff(knockerMelds, ["5S", "6S", "7S"]);
    expect(res.unmelded).toBe(0);
    expect(res.opponentMelds).toHaveLength(1);
    expect(res.melds[0]!.cards).toEqual(["5C", "5D", "5H"]);
  });

  it("lays off run extensions card by card in order", () => {
    /* QH then KH both extend the 9-T-J run; 2C stays deadwood. */
    const res = bestLayoff(knockerMelds, ["QH", "KH", "2C"]);
    expect(res.unmelded).toBe(2);
    expect(res.opponentDeadwood).toEqual(["2C"]);
    expect(res.melds[1]!.cards).toEqual(["9H", "TH", "JH", "QH", "KH"]);
  });
});
