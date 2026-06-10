import { RegExpMatcher, englishDataset, englishRecommendedTransformers } from "obscenity";

const matcher = new RegExpMatcher({
  ...englishDataset.build(),
  ...englishRecommendedTransformers,
});

const MAX_LEN = 500;
const MAX_TOKEN_LEN = 80;

/** In-memory per (user, game); a multi-instance deploy would need shared storage. */
const lastPostByUserGame = new Map<string, number>();
export const CHAT_COOLDOWN_MS = 1800;

export type ModerationResult = { ok: true; text: string } | { ok: false; code: "moderation_rejected"; error: string };

function collapseWhitespace(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

function normalizeForChat(raw: string): string {
  return collapseWhitespace(raw.normalize("NFC"));
}

function hasAbsurdToken(s: string): boolean {
  for (const part of s.split(/\s+/)) {
    if (part.length > MAX_TOKEN_LEN) return true;
  }
  return false;
}

/**
 * Validates and normalizes chat text. Rejects profanity (English preset), length abuse, and empty messages.
 */
export function moderateChatText(raw: unknown): ModerationResult {
  if (typeof raw !== "string") {
    return { ok: false, code: "moderation_rejected", error: "Message not allowed" };
  }
  const trimmed = normalizeForChat(raw);
  if (!trimmed) {
    return { ok: false, code: "moderation_rejected", error: "Message not allowed" };
  }
  if (trimmed.length > MAX_LEN) {
    return { ok: false, code: "moderation_rejected", error: "Message is too long" };
  }
  if (hasAbsurdToken(trimmed)) {
    return { ok: false, code: "moderation_rejected", error: "Message not allowed" };
  }
  if (matcher.hasMatch(trimmed)) {
    return { ok: false, code: "moderation_rejected", error: "Message not allowed" };
  }
  return { ok: true, text: trimmed };
}

/* Entries older than the cooldown are useless; sweep occasionally so the map
 * doesn't grow forever on a long-lived process. */
const PRUNE_THRESHOLD = 5000;

function pruneStaleEntries(now: number) {
  if (lastPostByUserGame.size < PRUNE_THRESHOLD) return;
  for (const [key, ts] of lastPostByUserGame) {
    if (now - ts >= CHAT_COOLDOWN_MS) lastPostByUserGame.delete(key);
  }
}

export function assertChatRateAllowed(userId: string, gameId: string): { ok: true } | { ok: false; error: string } {
  const key = `${userId}:${gameId}`;
  const now = Date.now();
  const last = lastPostByUserGame.get(key) ?? 0;
  if (now - last < CHAT_COOLDOWN_MS) {
    return { ok: false, error: "Slow down — try again in a moment" };
  }
  pruneStaleEntries(now);
  lastPostByUserGame.set(key, now);
  return { ok: true };
}
