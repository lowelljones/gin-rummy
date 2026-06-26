import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = join(MODULE_DIR, "../../..");

/** Production defaults — override with APPLE_TEAM_ID / APPLE_BUNDLE_ID on Railway. */
export const DEFAULT_APPLE_TEAM_ID = "BDDQS574XW";
export const DEFAULT_APPLE_BUNDLE_ID = "com.lowelljones.GinRummyApp";

/** HTTPS paths the iOS app handles via Universal Links (see AppModel.parseInviteCode). */
export const UNIVERSAL_LINK_PATHS = ["/join/*"] as const;

export interface AppleAppSiteAssociation {
  applinks: {
    apps: [];
    details: Array<{
      appID: string;
      paths: string[];
    }>;
  };
}

export interface UniversalLinksComplianceCheck {
  id: string;
  requirement: string;
  status: "pass" | "fail" | "warn";
  detail: string;
}

function readRepoFile(relPath: string): string {
  const abs = join(REPO_ROOT, relPath);
  if (!existsSync(abs)) return "";
  return readFileSync(abs, "utf8");
}

/** Parse `https://host` or bare hostname from Info.plist invite/API base URL keys. */
export function inviteLinkHostFromInfoPlist(plistXml: string): string | null {
  for (const key of ["GIN_INVITE_WEB_BASE_URL", "GIN_API_BASE_URL"]) {
    const m = plistXml.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`));
    if (!m) continue;
    const raw = m[1].trim();
    if (!raw) continue;
    try {
      const host = new URL(raw.includes("://") ? raw : `https://${raw}`).hostname;
      if (host) return host;
    } catch {
      /* try next key */
    }
  }
  return null;
}

export function appleAppId(opts?: { teamId?: string; bundleId?: string }): string {
  const teamId = (opts?.teamId ?? process.env.APPLE_TEAM_ID ?? DEFAULT_APPLE_TEAM_ID).trim();
  const bundleId = (opts?.bundleId ?? process.env.APPLE_BUNDLE_ID ?? DEFAULT_APPLE_BUNDLE_ID).trim();
  return `${teamId}.${bundleId}`;
}

export function buildAppleAppSiteAssociation(opts?: {
  teamId?: string;
  bundleId?: string;
  paths?: readonly string[];
}): AppleAppSiteAssociation {
  return {
    applinks: {
      apps: [],
      details: [
        {
          appID: appleAppId(opts),
          paths: [...(opts?.paths ?? UNIVERSAL_LINK_PATHS)],
        },
      ],
    },
  };
}

export function associatedDomainEntry(host: string): string {
  const normalized = host.trim().replace(/^applinks:/, "");
  return `applinks:${normalized}`;
}

/** Cross-repo checks: AASA JSON, API route, entitlements, and Info.plist domain alignment. */
export function auditUniversalLinksCompliance(): UniversalLinksComplianceCheck[] {
  const checks: UniversalLinksComplianceCheck[] = [];
  const serverTs = readRepoFile("backend/api/src/server.ts");
  const entitlements = readRepoFile("ios/GinRummyApp/GinRummyApp/GinRummyApp.entitlements");
  const infoPlist = readRepoFile("ios/GinRummyApp/GinRummyApp/Info.plist");
  const rootView = readRepoFile("ios/GinRummyApp/GinRummyApp/RootView.swift");
  const appModel = readRepoFile("ios/GinRummyApp/GinRummyApp/AppModel.swift");

  const aasa = buildAppleAppSiteAssociation();
  checks.push({
    id: "aasa-shape",
    requirement: "AASA JSON lists the production app ID and /join/* paths",
    status:
      aasa.applinks.details[0]?.appID === `${DEFAULT_APPLE_TEAM_ID}.${DEFAULT_APPLE_BUNDLE_ID}` &&
      aasa.applinks.details[0]?.paths.includes("/join/*")
        ? "pass"
        : "fail",
    detail: `appID=${aasa.applinks.details[0]?.appID}, paths=${aasa.applinks.details[0]?.paths.join(", ")}`,
  });

  checks.push({
    id: "api-serves-aasa",
    requirement: "API serves apple-app-site-association at /.well-known/",
    status: serverTs.includes('"/.well-known/apple-app-site-association"') ? "pass" : "fail",
    detail: "GET /.well-known/apple-app-site-association returns JSON for iOS Universal Links.",
  });

  checks.push({
    id: "entitlements-associated-domains",
    requirement: "GinRummyApp.entitlements declares Associated Domains (applinks:)",
    status:
      entitlements.includes("com.apple.developer.associated-domains") &&
      entitlements.includes("applinks:")
        ? "pass"
        : "fail",
    detail: "Xcode Associated Domains capability must match the HTTPS invite host.",
  });

  const inviteHost = inviteLinkHostFromInfoPlist(infoPlist);
  const entitlementHost = entitlements.match(/applinks:([^<]+)/)?.[1]?.trim() ?? "";
  checks.push({
    id: "domain-alignment",
    requirement: "Associated Domains host matches GIN_INVITE_WEB_BASE_URL / API host",
    status:
      inviteHost && entitlementHost && inviteHost === entitlementHost ? "pass" : inviteHost ? "fail" : "warn",
    detail: inviteHost
      ? `Info.plist host=${inviteHost}, entitlements host=${entitlementHost || "(missing)"}`
      : "Could not parse invite host from Info.plist.",
  });

  checks.push({
    id: "ios-handles-universal-links",
    requirement: "RootView forwards browsing-web activity into invite/password handlers",
    status:
      rootView.includes("NSUserActivityTypeBrowsingWeb") &&
      rootView.includes("handleInviteURL") &&
      appModel.includes('url.path.contains("/join/")')
        ? "pass"
        : "fail",
    detail: "onContinueUserActivity + parseInviteCode for https://…/join/CODE.",
  });

  return checks;
}

export function failingUniversalLinksChecks(
  checks: UniversalLinksComplianceCheck[] = auditUniversalLinksCompliance(),
): UniversalLinksComplianceCheck[] {
  return checks.filter((c) => c.status === "fail");
}
