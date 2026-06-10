import { describe, expect, it } from "vitest";
import {
  buildDeck,
  compareCutCards,
  deadwoodValue,
  rankOrderLow,
  shuffleDeck,
  upcardKnockValue,
} from "./cards.js";

describe("deadwoodValue", () => {
  it("aces count 1, faces and tens count 10, pips count face value", () => {
    expect(deadwoodValue("AS")).toBe(1);
    expect(deadwoodValue("2H")).toBe(2);
    expect(deadwoodValue("9D")).toBe(9);
    expect(deadwoodValue("TC")).toBe(10);
    expect(deadwoodValue("JS")).toBe(10);
    expect(deadwoodValue("QH")).toBe(10);
    expect(deadwoodValue("KD")).toBe(10);
  });
});

describe("rankOrderLow", () => {
  it("orders ace low through king high", () => {
    expect(rankOrderLow("AS")).toBe(1);
    expect(rankOrderLow("TS")).toBe(10);
    expect(rankOrderLow("KS")).toBe(13);
  });
});

describe("upcardKnockValue", () => {
  it("is null for no card and for any ace (no knock that hand)", () => {
    expect(upcardKnockValue(null)).toBeNull();
    expect(upcardKnockValue("AS")).toBeNull();
    expect(upcardKnockValue("AH")).toBeNull();
  });

  it("matches deadwood value otherwise", () => {
    expect(upcardKnockValue("2C")).toBe(2);
    expect(upcardKnockValue("9D")).toBe(9);
    expect(upcardKnockValue("QS")).toBe(10);
  });
});

describe("compareCutCards", () => {
  it("rank is primary with ace high", () => {
    expect(compareCutCards("AC", "KS")).toBeGreaterThan(0);
    expect(compareCutCards("2S", "3C")).toBeLessThan(0);
  });

  it("suit breaks ties: spades > hearts > diamonds > clubs", () => {
    expect(compareCutCards("9S", "9H")).toBeGreaterThan(0);
    expect(compareCutCards("9D", "9H")).toBeLessThan(0);
    expect(compareCutCards("9C", "9D")).toBeLessThan(0);
  });
});

describe("buildDeck / shuffleDeck", () => {
  it("builds 52 unique cards", () => {
    const deck = buildDeck();
    expect(deck).toHaveLength(52);
    expect(new Set(deck).size).toBe(52);
  });

  it("shuffle is a permutation and does not mutate the input", () => {
    const deck = buildDeck();
    const before = [...deck];
    let i = 0;
    const seq = [0.1, 0.9, 0.5, 0.3, 0.7];
    const shuffled = shuffleDeck(deck, () => seq[i++ % seq.length]!);
    expect(deck).toEqual(before);
    expect(shuffled).toHaveLength(52);
    expect([...shuffled].sort()).toEqual([...deck].sort());
  });
});
