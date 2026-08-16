import { describe, expect, it, vi } from "vitest";
import { BOT_GREETING, insertBotGreeting } from "./botGreeting.js";
import { moderateChatText } from "./chatModeration.js";

const GAME_ID = "33333333-3333-3333-3333-333333333333";
const BOT_ID = "6af0b8a9-78d4-47dd-8d78-f48f1c924c89";

function stubAdmin(result: { error: { message: string } | null }) {
  const insert = vi.fn().mockResolvedValue(result);
  const tables: string[] = [];
  const admin = {
    from(table: string) {
      tables.push(table);
      return { insert };
    },
  } as never;
  return { admin, insert, tables };
}

describe("insertBotGreeting", () => {
  it("posts the greeting as the bot, so a solo player has a message to report or block", async () => {
    const { admin, insert, tables } = stubAdmin({ error: null });

    const ok = await insertBotGreeting(GAME_ID, { admin, botUserId: BOT_ID });

    expect(ok).toBe(true);
    expect(tables).toEqual(["game_chat_messages"]);
    expect(insert).toHaveBeenCalledWith({
      game_id: GAME_ID,
      user_id: BOT_ID,
      body: BOT_GREETING,
    });
  });

  it("authors the row as the bot, never the host — otherwise fromSelf hides the menu", async () => {
    const { admin, insert } = stubAdmin({ error: null });
    const hostId = "11111111-1111-1111-1111-111111111111";

    await insertBotGreeting(GAME_ID, { admin, botUserId: BOT_ID });

    expect(insert.mock.calls[0][0].user_id).not.toBe(hostId);
    expect(insert.mock.calls[0][0].user_id).toBe(BOT_ID);
  });

  it("swallows an insert error so game creation still succeeds", async () => {
    const { admin } = stubAdmin({
      error: { message: 'violates foreign key constraint "game_chat_messages_user_id_fkey"' },
    });
    const warn = vi.fn();

    const ok = await insertBotGreeting(GAME_ID, { admin, botUserId: BOT_ID, log: { warn } });

    expect(ok).toBe(false);
    expect(warn).toHaveBeenCalledTimes(1);
  });

  it("survives a client that throws outright", async () => {
    const admin = {
      from() {
        throw new Error("connection reset");
      },
    } as never;
    const warn = vi.fn();

    await expect(
      insertBotGreeting(GAME_ID, { admin, botUserId: BOT_ID, log: { warn } }),
    ).resolves.toBe(false);
    expect(warn).toHaveBeenCalledTimes(1);
  });

  it("greeting text clears the same moderation applied to player messages", () => {
    expect(moderateChatText(BOT_GREETING).ok).toBe(true);
  });
});
