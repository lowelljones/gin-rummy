import { describe, expect, it } from "vitest";
import {
  appleAppId,
  associatedDomainEntry,
  auditUniversalLinksCompliance,
  buildAppleAppSiteAssociation,
  DEFAULT_APPLE_BUNDLE_ID,
  DEFAULT_APPLE_TEAM_ID,
  failingUniversalLinksChecks,
  inviteLinkHostFromInfoPlist,
} from "./appleAppSiteAssociation.js";

describe("apple-app-site-association", () => {
  it("builds the production app ID and invite paths", () => {
    const doc = buildAppleAppSiteAssociation();
    expect(doc.applinks.apps).toEqual([]);
    expect(doc.applinks.details).toHaveLength(1);
    expect(doc.applinks.details[0]?.appID).toBe(`${DEFAULT_APPLE_TEAM_ID}.${DEFAULT_APPLE_BUNDLE_ID}`);
    expect(doc.applinks.details[0]?.paths).toEqual(["/join/*"]);
  });

  it("honours env overrides for team and bundle", () => {
    expect(
      appleAppId({ teamId: "TEAM123", bundleId: "com.example.app" }),
    ).toBe("TEAM123.com.example.app");
  });

  it("formats associated domain entries", () => {
    expect(associatedDomainEntry("gin-rummy-production.up.railway.app")).toBe(
      "applinks:gin-rummy-production.up.railway.app",
    );
  });

  it("parses invite host from Info.plist URLs", () => {
    const plist = `
      <key>GIN_INVITE_WEB_BASE_URL</key>
      <string>https://gin-rummy-production.up.railway.app</string>
    `;
    expect(inviteLinkHostFromInfoPlist(plist)).toBe("gin-rummy-production.up.railway.app");
  });
});

describe("universal links compliance audit", () => {
  it("has no failing checks against the current codebase", () => {
    const failures = failingUniversalLinksChecks(auditUniversalLinksCompliance());
    if (failures.length > 0) {
      const report = failures.map((f) => `[${f.id}] ${f.requirement}\n  → ${f.detail}`).join("\n\n");
      expect.fail(`Universal Links compliance failures:\n\n${report}`);
    }
    expect(failures).toEqual([]);
  });
});
