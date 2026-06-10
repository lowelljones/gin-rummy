import { describe, expect, it } from "vitest";
import {
  bettingBucket,
  computeBettingSettlement,
  resolveKnockFinal,
  scoreEO,
  scoreGin,
} from "./scoring.js";

describe("hand scoring", () => {
  it("gin is 25 + opponent unmelded (face cards 10, ace 1)", () => {
    expect(scoreGin([])).toBe(25);
    expect(scoreGin(["AH", "KD", "QC", "5S"])).toBe(25 + 1 + 10 + 10 + 5);
  });

  it("EO is 50 + opponent unmelded", () => {
    expect(scoreEO([])).toBe(50);
    expect(scoreEO(["TD", "2C"])).toBe(50 + 10 + 2);
  });

  it("knocker lower → knocker wins the difference (no bonus)", () => {
    const r = resolveKnockFinal({
      knocker: 0,
      knockerDeadwood: ["5C"],
      opponentDeadwood: ["KD", "9H"],
    });
    expect(r).toEqual({ winner: 0, points: 19 - 5 });
  });

  it("opponent lower → opponent wins the difference + 25 Cut", () => {
    const r = resolveKnockFinal({
      knocker: 0,
      knockerDeadwood: ["5C"],
      opponentDeadwood: ["2D"],
    });
    expect(r).toEqual({ winner: 1, points: 5 - 2 + 25 });
  });

  it("equal totals → defender wins the 25-point Cut", () => {
    const r = resolveKnockFinal({
      knocker: 1,
      knockerDeadwood: ["5C"],
      opponentDeadwood: ["5D"],
    });
    expect(r).toEqual({ winner: 0, points: 25 });
  });
});

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

  it("continues a bucket every 100 points", () => {
    expect(bettingBucket(349)).toBe(3);
    expect(bettingBucket(350)).toBe(4);
    expect(bettingBucket(450)).toBe(5);
  });
});

describe("computeBettingSettlement", () => {
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

  it("adds 100 shutout bonus when the loser has 0 points", () => {
    const { raw, bucket } = computeBettingSettlement({
      winner: 0,
      loser: 1,
      finalScores: [130, 0],
      handsWon: [5, 0],
    });
    /* 130 - 0 + 100 win + 100 shutout + 25 × 5 = 455 → bucket 5. */
    expect(raw).toBe(455);
    expect(bucket).toBe(5);
  });

  it("net hands term goes negative when the winner lost more hands", () => {
    const { raw, bucket } = computeBettingSettlement({
      winner: 0,
      loser: 1,
      finalScores: [126, 95],
      handsWon: [2, 4],
    });
    /* 126 - 95 + 100 + 25 × (2 - 4) = 81 → bucket 1. */
    expect(raw).toBe(81);
    expect(bucket).toBe(1);
  });

  it("works for seat 1 as the winner", () => {
    const { raw } = computeBettingSettlement({
      winner: 1,
      loser: 0,
      finalScores: [40, 140],
      handsWon: [2, 3],
    });
    expect(raw).toBe(140 - 40 + 100 + 25);
  });
});
