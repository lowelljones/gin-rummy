import { describe, expect, it } from "vitest";
import { DISPLAY_NAME_MAX_LEN, moderateDisplayName } from "./displayNameModeration.js";

describe("moderateDisplayName", () => {
  it("accepts and trims an ordinary name", () => {
    const r = moderateDisplayName("  Lucky   Lou  ");
    expect(r).toEqual({ ok: true, text: "Lucky Lou" });
  });

  it("rejects non-strings and empty values", () => {
    expect(moderateDisplayName(undefined).ok).toBe(false);
    expect(moderateDisplayName("").ok).toBe(false);
    expect(moderateDisplayName("   ").ok).toBe(false);
  });

  it("rejects names that are too short or too long", () => {
    expect(moderateDisplayName("A").ok).toBe(false);
    const long = "x".repeat(DISPLAY_NAME_MAX_LEN + 1);
    expect(moderateDisplayName(long).ok).toBe(false);
  });

  it("rejects profanity via the english preset", () => {
    expect(moderateDisplayName("fuck").ok).toBe(false);
  });
});
