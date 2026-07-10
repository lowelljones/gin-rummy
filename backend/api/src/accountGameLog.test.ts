import { describe, expect, it } from "vitest";
import { buildAccountGameLog, type AccountGameRow } from "./accountGameLog.js";
import type { ServerTruth } from "../../rules/src/types.js";

const ME = "user-me";
const FRIEND = "user-friend";
const OTHER = "user-other";
const BOT = "user-bot";

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

function row(overrides: Partial<AccountGameRow> = {}): AccountGameRow {
  return {
    id: "g1",
    status: "completed",
    created_at: "2026-07-01T00:00:00Z",
    updated_at: "2026-07-01T01:00:00Z",
    seat_for_user: { [ME]: 0, [FRIEND]: 1 },
    server_truth: truth(),
    is_bot_game: false,
    ...overrides,
  };
}

describe("buildAccountGameLog", () => {
  it("reports opponent, result, score, tier, and hands from my perspective", () => {
    const payload = buildAccountGameLog({
      userId: ME,
      botUserId: BOT,
      rows: [row()],
      displayNames: { [FRIEND]: "Charlie" },
    });

    expect(payload.games).toHaveLength(1);
    const g = payload.games[0];
    expect(g.opponent_display_name).toBe("Charlie");
    expect(g.i_won).toBe(true);
    expect(g.my_score).toBe(125);
    expect(g.opponent_score).toBe(80);
    expect(g.hands_played).toBe(5);
    expect(g.betting_bucket).toBe(3);

    expect(payload.totals).toEqual({
      completed_games: 1,
      wins: 1,
      losses: 0,
      net_buckets: 3,
      hands_played: 5,
    });
  });

  it("flips perspective when I sit in seat 1 and lose", () => {
    const payload = buildAccountGameLog({
      userId: ME,
      botUserId: BOT,
      rows: [row({ seat_for_user: { [FRIEND]: 0, [ME]: 1 } })],
      displayNames: { [FRIEND]: "Charlie" },
    });

    const g = payload.games[0];
    expect(g.i_won).toBe(false);
    expect(g.my_score).toBe(80);
    expect(g.opponent_score).toBe(125);
    expect(payload.totals.net_buckets).toBe(-3);
    expect(payload.totals.losses).toBe(1);
  });

  it("labels bot games and skips active games", () => {
    const payload = buildAccountGameLog({
      userId: ME,
      botUserId: BOT,
      rows: [
        row({ id: "bot-game", seat_for_user: { [ME]: 0, [BOT]: 1 }, is_bot_game: true }),
        row({ id: "still-playing", status: "active" }),
      ],
      displayNames: {},
    });

    expect(payload.games.map((g) => g.game_id)).toEqual(["bot-game"]);
    expect(payload.games[0].opponent_display_name).toBe("Practice bot");
    expect(payload.games[0].is_bot_game).toBe(true);
    // Practice games are listed but never counted toward the record.
    expect(payload.totals.completed_games).toBe(0);
    expect(payload.totals.wins).toBe(0);
  });

  it("marks abandoned games with who left and excludes them from totals", () => {
    const payload = buildAccountGameLog({
      userId: ME,
      botUserId: BOT,
      rows: [
        row({
          id: "walked",
          status: "abandoned",
          abandoned_by: FRIEND,
          server_truth: truth({ phase: "play", scores: [40, 10], bettingRaw: null, bettingBucket: null }),
        }),
      ],
      displayNames: { [FRIEND]: "Charlie" },
    });

    const g = payload.games[0];
    expect(g.status).toBe("abandoned");
    expect(g.i_won).toBeNull();
    expect(g.i_abandoned).toBe(false);
    expect(payload.totals.completed_games).toBe(0);
    expect(payload.totals.net_buckets).toBe(0);
  });

  it("sorts newest first and aggregates multiple games", () => {
    const payload = buildAccountGameLog({
      userId: ME,
      botUserId: BOT,
      rows: [
        row({ id: "older", updated_at: "2026-07-01T01:00:00Z" }),
        row({
          id: "newer",
          updated_at: "2026-07-02T01:00:00Z",
          seat_for_user: { [OTHER]: 0, [ME]: 1 },
          server_truth: truth({ scores: [130, 60], handsWon: [4, 1], bettingRaw: 245, bettingBucket: 2 }),
        }),
      ],
      displayNames: { [FRIEND]: "Charlie", [OTHER]: "Dana" },
    });

    expect(payload.games.map((g) => g.game_id)).toEqual(["newer", "older"]);
    expect(payload.totals).toEqual({
      completed_games: 2,
      wins: 1,
      losses: 1,
      net_buckets: 3 - 2,
      hands_played: 10,
    });
  });
});
