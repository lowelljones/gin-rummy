import { describe, expect, it } from "vitest";
import { bettingBucket, computeBettingSettlement } from "./scoring.js";

describe("bettingBucket", () => {
  it("maps 250 to 3", () => {
    expect(bettingBucket(250)).toBe(3);
  });

  it("maps 0-149 to 1", () => {
    expect(bettingBucket(0)).toBe(1);
    expect(bettingBucket(149)).toBe(1);
  });

  it("maps 150-249 to 2", () => {
    expect(bettingBucket(150)).toBe(2);
    expect(bettingBucket(249)).toBe(2);
  });
});

describe("computeBettingSettlement example", () => {
  it("matches user example raw 250 bucket 3", () => {
    const winner = 0 as const;
    const loser = 1 as const;
    const finalScores: [number, number] = [125, 25];
    const handsWon: [number, number] = [3, 1];
    const { raw, bucket } = computeBettingSettlement({
      winner,
      loser,
      finalScores,
      handsWon,
    });
    expect(raw).toBe(250);
    expect(bucket).toBe(3);
  });
});
