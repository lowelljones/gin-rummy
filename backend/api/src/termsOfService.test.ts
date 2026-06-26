import { describe, expect, it } from "vitest";
import { privacyContactEmail } from "./privacyPolicy.js";
import {
  failingTermsComplianceChecks,
  renderTermsOfServicePage,
  termsComplianceChecks,
} from "./termsOfService.js";

describe("terms of service page", () => {
  const html = renderTermsOfServicePage({ contactEmail: privacyContactEmail() });

  it("includes required legal topics", () => {
    expect(html).toContain("Terms of Service");
    expect(html).toContain("Privacy Policy");
    expect(html).toContain("/privacy");
    expect(html).toContain("Acceptable use");
    expect(html).toContain("not real-money wagers");
    expect(html).toContain("Delete account");
    expect(html).toContain(privacyContactEmail());
  });

  it("escapes contact email in HTML", () => {
    const escaped = renderTermsOfServicePage({ contactEmail: 'a"b@c.com' });
    expect(escaped).toContain("a&quot;b@c.com");
    expect(escaped).not.toContain('a"b@c.com');
  });
});

describe("terms compliance audit", () => {
  it("has no failing checks against the current codebase", () => {
    const failures = failingTermsComplianceChecks(termsComplianceChecks());

    if (failures.length > 0) {
      const report = failures.map((f) => `[${f.id}] ${f.requirement}\n  → ${f.detail}`).join("\n\n");
      expect.fail(`Terms compliance failures:\n\n${report}`);
    }

    expect(failures).toEqual([]);
  });
});
