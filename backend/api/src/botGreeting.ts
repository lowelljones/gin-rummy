import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * One canned line from the practice bot, posted when a solo game is created.
 *
 * It exists so a player alone at the table has an opponent message to long-press:
 * Report and Block only render on messages the viewer did not send (GameChatBubble
 * in GameChatSheet.swift), and the bot never chats on its own. Without this the
 * moderation tools App Review looks for under guideline 1.2 are unreachable in a
 * solo session — which is how a reviewer with one device concludes they don't exist.
 */
export const BOT_GREETING = "Good luck — deal 'em.";

export type BotGreetingDeps = {
  admin: SupabaseClient;
  botUserId: string;
  log?: { warn: (obj: object, msg: string) => void };
};

/**
 * Writes the greeting straight to the table rather than going through
 * POST /games/:id/chat: the text is server-authored, so the rate limiter and
 * profanity filter that guard player input have nothing to do here.
 *
 * Best-effort by design. A missing greeting is a small loss; a failed insert
 * that sinks game creation would leave a reviewer staring at a dead "Play bot"
 * button, so every failure is logged and swallowed.
 */
export async function insertBotGreeting(gameId: string, deps: BotGreetingDeps): Promise<boolean> {
  try {
    const { error } = await deps.admin.from("game_chat_messages").insert({
      game_id: gameId,
      user_id: deps.botUserId,
      body: BOT_GREETING,
    });
    if (error) {
      deps.log?.warn({ err: error.message, gameId }, "bot greeting insert failed");
      return false;
    }
    return true;
  } catch (e) {
    const msg = e instanceof Error ? e.message : "unknown error";
    deps.log?.warn({ err: msg, gameId }, "bot greeting insert failed");
    return false;
  }
}
