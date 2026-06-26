import { describe, expect, it } from "vitest";
import {
  auditPrivacyCompliance,
  failingComplianceChecks,
  privacyContactEmail,
  renderPrivacyPolicyPage,
} from "./privacyPolicy.js";

describe("privacy policy page", () => {
  const html = renderPrivacyPolicyPage({ contactEmail: privacyContactEmail() });

  it("includes required disclosure topics", () => {
    expect(html).toContain("email address");
    expect(html).toContain("Supabase");
    expect(html).toContain("Railway");
    expect(html).toContain("do not sell");
    expect(html).toContain("do not currently use third-party analytics");
    expect(html).toContain("Delete account");
    expect(html).toContain(privacyContactEmail());
  });

  it("escapes contact email in HTML", () => {
    const escaped = renderPrivacyPolicyPage({ contactEmail: 'a"b@c.com' });
    expect(escaped).toContain("a&quot;b@c.com");
    expect(escaped).not.toContain('a"b@c.com');
  });
});

describe("privacy compliance audit", () => {
  it("has no failing checks against the current codebase", () => {
    const checks = auditPrivacyCompliance();
    const failures = failingComplianceChecks(checks);

    if (failures.length > 0) {
      const report = failures.map((f) => `[${f.id}] ${f.requirement}\n  → ${f.detail}`).join("\n\n");
      expect.fail(`Privacy compliance failures:\n\n${report}`);
    }

    expect(failures).toEqual([]);
  });

  it("reports warnings separately (informational)", () => {
    const warnings = auditPrivacyCompliance().filter((c) => c.status === "warn");
    // Warnings are allowed; surfaced in test output for visibility.
    for (const w of warnings) {
      expect(w.detail.length).toBeGreaterThan(0);
    }
  });
});
