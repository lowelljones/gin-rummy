import { RegExpMatcher, englishDataset, englishRecommendedTransformers } from "obscenity";

const matcher = new RegExpMatcher({
  ...englishDataset.build(),
  ...englishRecommendedTransformers,
});

export const DISPLAY_NAME_MAX_LEN = 32;
export const DISPLAY_NAME_MIN_LEN = 2;

export type DisplayNameModerationResult =
  | { ok: true; text: string }
  | { ok: false; error: string };

function collapseWhitespace(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

function normalizeDisplayName(raw: string): string {
  return collapseWhitespace(raw.normalize("NFC"));
}

/** Validates and normalizes a player-chosen display name shown in lobbies and invites. */
export function moderateDisplayName(raw: unknown): DisplayNameModerationResult {
  if (typeof raw !== "string") {
    return { ok: false, error: "Enter a display name" };
  }
  const trimmed = normalizeDisplayName(raw);
  if (!trimmed) {
    return { ok: false, error: "Enter a display name" };
  }
  if (trimmed.length < DISPLAY_NAME_MIN_LEN) {
    return { ok: false, error: `Use at least ${DISPLAY_NAME_MIN_LEN} characters` };
  }
  if (trimmed.length > DISPLAY_NAME_MAX_LEN) {
    return { ok: false, error: `Use at most ${DISPLAY_NAME_MAX_LEN} characters` };
  }
  if (matcher.hasMatch(trimmed)) {
    return { ok: false, error: "That display name isn't allowed" };
  }
  return { ok: true, text: trimmed };
}
