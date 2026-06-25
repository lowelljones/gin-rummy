import { describe, expect, it, vi } from "vitest";
import { createNewMatch } from "../../rules/src/index.js";
import { buildGameStatePayloadForUser, syncPlayerGameSnapshots } from "./playerGameSnapshots.js";

describe("playerGameSnapshots", () => {
  const hostId = "11111111-1111-1111-1111-111111111111";
  const guestId = "22222222-2222-2222-2222-222222222222";
  const botId = "00000000-0000-0000-0000-000000000001";
  const gameId = "33333333-3333-3333-3333-333333333333";

  it("buildGameStatePayloadForUser hides the opponent hand", async () => {
    const truth = createNewMatch("test", () => 0.5);
    const game = {
      id: gameId,
      server_truth: truth,
      seat_for_user: { [hostId]: 0, [guestId]: 1 },
      move_seq: 0,
      status: "active",
      lobby_id: null,
      is_bot_game: false,
    };

    const deps = {
      admin: {} as never,
      botUserId: botId,
      opponentDisplayNameForGame: async () => "Guest",
      findLobbyInviteCode: async () => null,
      buildRematchStatus: async () => null,
    };

    const hostView = await buildGameStatePayloadForUser(game, hostId, deps);
    const guestView = await buildGameStatePayloadForUser(game, guestId, deps);

    expect(hostView).not.toBeNull();
    expect(guestView).not.toBeNull();
    expect(hostView!.perspective.seat).toBe(0);
    expect(guestView!.perspective.seat).toBe(1);
    /* Each seat sees their own cards, opponent hand is HIDDEN placeholders. */
    expect(hostView!.perspective.hands[0].every((c) => c !== "HIDDEN")).toBe(true);
    expect(hostView!.perspective.hands[1].every((c) => c === "HIDDEN")).toBe(true);
    expect(guestView!.perspective.hands[1].every((c) => c !== "HIDDEN")).toBe(true);
    expect(guestView!.perspective.hands[0].every((c) => c === "HIDDEN")).toBe(true);
  });

  it("syncPlayerGameSnapshots upserts one row per human player", async () => {
    const truth = createNewMatch("test", () => 0.5);
    const upsert = vi.fn().mockResolvedValue({ error: null });
    const deps = {
      admin: {
        from(table: string) {
          if (table === "games") {
            return {
              select: () => ({
                eq: () => ({
                  maybeSingle: async () => ({
                    data: {
                      id: gameId,
                      server_truth: truth,
                      seat_for_user: { [hostId]: 0, [guestId]: 1, [botId]: 1 },
                      move_seq: 3,
                      status: "active",
                      lobby_id: null,
                      is_bot_game: false,
                    },
                    error: null,
                  }),
                }),
              }),
            };
          }
          if (table === "player_game_snapshots") {
            return { upsert };
          }
          throw new Error(`unexpected table ${table}`);
        },
      },
      botUserId: botId,
      opponentDisplayNameForGame: async () => "Opponent",
      findLobbyInviteCode: async () => null,
      buildRematchStatus: async () => null,
    };

    await syncPlayerGameSnapshots(gameId, deps as never);

    expect(upsert).toHaveBeenCalledTimes(2);
    const userIds = upsert.mock.calls.map((c) => c[0].user_id).sort();
    expect(userIds).toEqual([guestId, hostId].sort());
    expect(upsert.mock.calls[0][0]).toMatchObject({
      game_id: gameId,
      move_seq: 3,
      status: "active",
    });
  });
});
