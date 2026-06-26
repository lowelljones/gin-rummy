import { describe, expect, it } from "vitest";
import { normalizeReportReason } from "./chatSafety.js";

describe("normalizeReportReason", () => {
  it("accepts known reason codes", () => {
    expect(normalizeReportReason("harassment")).toBe("harassment");
    expect(normalizeReportReason(" SPAM ")).toBe("spam");
  });

  it("returns null for empty or invalid input", () => {
    expect(normalizeReportReason("")).toBeNull();
    expect(normalizeReportReason(null)).toBeNull();
    expect(normalizeReportReason(42)).toBeNull();
  });

  it("truncates free-text reasons", () => {
    const long = "x".repeat(250);
    expect(normalizeReportReason(long)?.length).toBe(200);
  });
});
