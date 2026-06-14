import { describe, expect, it } from "vitest";
import {
  attachHandScoresToMatches,
  buildHandScoresFromEpisodes,
  buildSessionRecapFromGames,
  matchWinnerFromScores,
} from "./sessionRecap.js";
import type { ServerTruth } from "../../rules/src/types.js";

function truth(overrides: Partial<ServerTruth> = {}): ServerTruth {
  return {
    version: 1,
    phase: "matchOver",
    handIndex: 4,
    dealIndex: 4,
    currentDeal: null,
    dealer: 0,
    nonDealer: 1,
    scores: [125, 80],
    handsWon: [3, 2],
    raceTarget: 125,
    stock: [],
    discard: [],
    hands: [[], []],
    currentTurn: 0,
    cut: { spread: [], picks: [null, null], firstSeat: 0 },
    lastCutResult: null,
    upcardOffer: null,
    knockCheckCard: null,
    knock: null,
    lastHandWinner: null,
    lastHandPoints: null,
    seenBy: {},
    bettingRaw: 264,
    bettingBucket: 3,
    ...overrides,
  } as ServerTruth;
}

describe("matchWinnerFromScores", () => {
  it("returns the seat that reached the race target", () => {
    expect(matchWinnerFromScores([125, 80], 125)).toBe(0);
    expect(matchWinnerFromScores([90, 130], 125)).toBe(1);
    expect(matchWinnerFromScores([90, 90], 125)).toBeNull();
  });
});

describe("buildSessionRecapFromGames", () => {
  it("orders matches chronologically and accumulates session totals", () => {
    const { matches, totals } = buildSessionRecapFromGames(
      [
        {
          id: "game-2",
          status: "completed",
          server_truth: truth({ scores: [130, 40], handsWon: [4, 1], bettingRaw: 300, bettingBucket: 3 }),
          created_at: "2026-06-14T12:00:00.000Z",
          updated_at: "2026-06-14T12:30:00.000Z",
        },
        {
          id: "game-1",
          status: "completed",
          server_truth: truth(),
          created_at: "2026-06-14T10:00:00.000Z",
          updated_at: "2026-06-14T10:45:00.000Z",
        },
      ],
      "game-3",
    );

    expect(matches.map((m) => m.game_id)).toEqual(["game-1", "game-2"]);
    expect(matches[0].match_number).toBe(1);
    expect(matches[0].winner_seat).toBe(0);
    expect(matches[0].betting_bucket).toBe(3);
    expect(matches[1].match_number).toBe(2);
    expect(totals.completed_matches).toBe(2);
    expect(totals.match_wins).toEqual([2, 0]);
    expect(totals.total_betting_raw).toBe(264 + 300);
    expect(totals.total_buckets).toBe(6);
  });

  it("marks the active in-progress match without betting settlement", () => {
    const { matches, totals } = buildSessionRecapFromGames(
      [
        {
          id: "game-1",
          status: "completed",
          server_truth: truth(),
          created_at: "2026-06-14T10:00:00.000Z",
          updated_at: "2026-06-14T10:45:00.000Z",
        },
        {
          id: "game-2",
          status: "active",
          server_truth: truth({
            phase: "play",
            scores: [45, 30],
            handsWon: [1, 0],
            bettingRaw: null,
            bettingBucket: null,
          }),
          created_at: "2026-06-14T12:00:00.000Z",
          updated_at: "2026-06-14T12:05:00.000Z",
        },
      ],
      "game-2",
    );

    expect(matches[1].is_current).toBe(true);
    expect(matches[1].winner_seat).toBeNull();
    expect(matches[1].betting_bucket).toBeNull();
    expect(totals.completed_matches).toBe(1);
    expect(totals.match_wins).toEqual([1, 0]);
  });
});

describe("buildHandScoresFromEpisodes", () => {
  it("keeps one row per hand_index with points and ignores void redeals", () => {
    const rows = buildHandScoresFromEpisodes([
      {
        game_id: "g1",
        hand_index: 1,
        deal_index: 1,
        winner_seat: null,
        points_awarded: 0,
        scores_after: [0, 0],
      },
      {
        game_id: "g1",
        hand_index: 1,
        deal_index: 2,
        winner_seat: 0,
        points_awarded: 29,
        scores_after: [29, 0],
      },
      {
        game_id: "g1",
        hand_index: 2,
        deal_index: 3,
        winner_seat: 1,
        points_awarded: 15,
        scores_after: [29, 15],
      },
    ]);
    expect(rows).toEqual([
      { hand_index: 1, winner_seat: 0, points_awarded: 29, scores_after: [29, 0] },
      { hand_index: 2, winner_seat: 1, points_awarded: 15, scores_after: [29, 15] },
    ]);
  });

  it("attaches hand scores to session matches by game_id", () => {
    const matches = attachHandScoresToMatches(
      [
        {
          match_number: 1,
          game_id: "game-1",
          status: "completed",
          phase: "matchOver",
          created_at: "",
          updated_at: "",
          race_target: 125,
          scores: [125, 80],
          hands_won: [3, 2],
          winner_seat: 0,
          betting_raw: 264,
          betting_bucket: 3,
          is_current: false,
        },
      ],
      [
        {
          game_id: "game-1",
          hand_index: 1,
          deal_index: 1,
          winner_seat: 0,
          points_awarded: 29,
          scores_after: [29, 0],
        },
      ],
    );
    expect(matches[0].hand_scores).toHaveLength(1);
    expect(matches[0].hand_scores[0].points_awarded).toBe(29);
  });
});
