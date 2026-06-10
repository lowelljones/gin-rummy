import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { assertChatRateAllowed, CHAT_COOLDOWN_MS, moderateChatText } from "./chatModeration.js";

describe("moderateChatText", () => {
  it("accepts and trims an ordinary message", () => {
    const r = moderateChatText("  nice   knock!  ");
    expect(r).toEqual({ ok: true, text: "nice knock!" });
  });

  it("rejects non-strings and empty/whitespace-only messages", () => {
    expect(moderateChatText(undefined).ok).toBe(false);
    expect(moderateChatText(42).ok).toBe(false);
    expect(moderateChatText("").ok).toBe(false);
    expect(moderateChatText("   \n\t ").ok).toBe(false);
  });

  it("rejects messages over the length limit", () => {
    const r = moderateChatText("a ".repeat(300)); /* 599 chars after collapse */
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error).toMatch(/too long/);
  });

  it("rejects a single absurd unbroken token", () => {
    expect(moderateChatText("x".repeat(120)).ok).toBe(false);
  });

  it("rejects profanity via the english preset", () => {
    expect(moderateChatText("you are such a fuck").ok).toBe(false);
  });
});

describe("assertChatRateAllowed", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("allows the first post and blocks an immediate repeat for the same user+game", () => {
    vi.setSystemTime(1_000_000);
    const user = `u-${Math.random()}`;
    expect(assertChatRateAllowed(user, "g1").ok).toBe(true);
    expect(assertChatRateAllowed(user, "g1").ok).toBe(false);
  });

  it("allows again after the cooldown elapses", () => {
    vi.setSystemTime(2_000_000);
    const user = `u-${Math.random()}`;
    expect(assertChatRateAllowed(user, "g1").ok).toBe(true);
    vi.setSystemTime(2_000_000 + CHAT_COOLDOWN_MS + 1);
    expect(assertChatRateAllowed(user, "g1").ok).toBe(true);
  });

  it("tracks games independently for the same user", () => {
    vi.setSystemTime(3_000_000);
    const user = `u-${Math.random()}`;
    expect(assertChatRateAllowed(user, "g1").ok).toBe(true);
    expect(assertChatRateAllowed(user, "g2").ok).toBe(true);
  });
});
