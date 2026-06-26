import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
/** Gin Rummy repo root (`backend/api/src` → three levels up). */
export const REPO_ROOT = join(MODULE_DIR, "../../..");

export const PRIVACY_POLICY_LAST_UPDATED = "June 26, 2026";

export interface PrivacyPolicyOptions {
  contactEmail: string;
}

export interface PrivacyComplianceCheck {
  id: string;
  requirement: string;
  status: "pass" | "fail" | "warn";
  detail: string;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function readRepoFile(relPath: string): string {
  const abs = join(REPO_ROOT, relPath);
  if (!existsSync(abs)) return "";
  return readFileSync(abs, "utf8");
}

/** Public privacy/support inbox (override with PRIVACY_CONTACT_EMAIL if needed). */
const PRIVACY_CONTACT_DEFAULT = "lowellwjones@gmail.com";

export function privacyContactEmail(): string {
  const fromEnv = process.env.PRIVACY_CONTACT_EMAIL?.trim();
  return fromEnv || PRIVACY_CONTACT_DEFAULT;
}

export function isPrivacyContactConfigured(): boolean {
  return privacyContactEmail().includes("@");
}

export function renderPrivacyPolicyPage(opts: PrivacyPolicyOptions): string {
  const email = escapeHtml(opts.contactEmail);
  const mailto = `mailto:${email}`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Privacy Policy — Gin Rummy</title>
<meta name="description" content="Privacy policy for the Gin Rummy iOS app." />
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; min-height: 100vh;
    background: radial-gradient(ellipse at top, #14352a 0%, #0b211a 65%, #081711 100%);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #f3ecd9; line-height: 1.55;
  }
  .wrap { max-width: 680px; margin: 0 auto; padding: 40px 24px 64px; }
  h1 { font-size: 28px; margin: 0 0 6px; }
  .updated { color: #8fa388; font-size: 14px; margin-bottom: 28px; }
  h2 { font-size: 18px; margin: 28px 0 10px; color: #e8c66a; }
  p, li { font-size: 15px; color: #d8dccf; }
  ul { padding-left: 1.25rem; margin: 0 0 14px; }
  a { color: #e8c66a; }
  .card {
    background: rgba(10, 30, 23, 0.82); border: 1px solid rgba(212, 175, 55, 0.35);
    border-radius: 16px; padding: 28px 24px; box-shadow: 0 18px 60px rgba(0,0,0,0.35);
  }
</style>
</head>
<body>
  <main class="wrap">
    <div class="card">
      <h1>Privacy Policy</h1>
      <p class="updated">Last updated: ${escapeHtml(PRIVACY_POLICY_LAST_UPDATED)}</p>
      <p>
        This policy describes how the Gin Rummy iOS app ("the app") and its online services
        collect, use, and delete information. The app is built for playing Gin Rummy with friends.
      </p>

      <h2>Information we collect</h2>
      <ul>
        <li><strong>Account information.</strong> If you create an account, we collect your email address and password. Passwords are handled by our authentication provider; we do not store your password in plain text.</li>
        <li><strong>Profile information.</strong> We store a display name for your account (initially derived from your email address) so friends can see who invited them to a lobby.</li>
        <li><strong>Gameplay and lobby data.</strong> To run multiplayer games we store lobby membership, invite codes, game state, move history, scores, betting totals within a match, session recaps, and related metadata needed to keep games in sync and let you resume play.</li>
        <li><strong>In-game chat.</strong> If you send chat messages during a game, we store the message text, your user ID, and the associated game.</li>
        <li><strong>Device session data.</strong> The app stores your sign-in session (access token, refresh token, and email) in the iOS Keychain on your device so you stay signed in.</li>
        <li><strong>Local score sheet (optional).</strong> If you use the in-app manual scorecard for an in-person game, names and scores are saved only on your device using iOS local storage. That data is not uploaded to our servers.</li>
      </ul>

      <h2>How we use information</h2>
      <p>We use the information above solely to provide and improve the game: authentication, matchmaking, real-time updates, chat, scorekeeping, and customer support. We do not sell your personal data.</p>

      <h2>Service providers</h2>
      <ul>
        <li><strong>Supabase</strong> — authentication, PostgreSQL database, and real-time subscriptions for in-game updates. Supabase processes account and gameplay data on our behalf.</li>
        <li><strong>Railway</strong> (or similar backend hosting) — hosts our game API that validates moves, manages lobbies, and serves invite links. Server logs may include technical metadata such as request timestamps and internal user IDs for troubleshooting.</li>
      </ul>

      <h2>Analytics and advertising</h2>
      <p>
        We do not currently use third-party analytics, advertising, or crash-reporting SDKs
        (for example Firebase Analytics, Google Analytics, or Sentry). Game move history and
        hand summaries are stored in our database to operate the game and show session recaps;
        that is first-party gameplay data, not third-party tracking.
      </p>

      <h2>Data retention and deletion</h2>
      <p>
        Game and account data are kept while your account exists and as needed to operate active
        games. You can delete your account at any time from <strong>Account → Delete account</strong>
        in the app. Deletion permanently removes your Supabase auth account and associated profile,
        lobby, and game records stored on our servers. Local manual scorecard data remains on your
        device until you reset it or uninstall the app.
      </p>
      <p>
        You can also email us to request account deletion or ask privacy questions:
        <a href="${mailto}">${email}</a>.
      </p>

      <h2>Children</h2>
      <p>The app is not directed at children under 13, and we do not knowingly collect personal information from them.</p>

      <h2>Changes</h2>
      <p>We may update this policy from time to time. The "Last updated" date at the top will change when we do.</p>

      <h2>Contact</h2>
      <p>Privacy and support: <a href="${mailto}">${email}</a></p>
    </div>
  </main>
</body>
</html>`;
}

const ANALYTICS_SDK_PATTERNS = [
  /FirebaseAnalytics/i,
  /FirebaseCrashlytics/i,
  /Crashlytics/i,
  /GoogleAnalytics/i,
  /Amplitude/i,
  /Mixpanel/i,
  /Sentry/i,
  /SegmentAnalytics/i,
  /AppsFlyer/i,
  /FacebookCore/i,
  /FBSDKCoreKit/i,
];

/** Static audit of repo code vs. privacy-policy claims (for CI and App Store alignment). */
export function auditPrivacyCompliance(): PrivacyComplianceCheck[] {
  const checks: PrivacyComplianceCheck[] = [];

  const authView = readRepoFile("ios/GinRummyApp/GinRummyApp/AuthView.swift");
  checks.push({
    id: "collects-email",
    requirement: "App collects email when users sign up or sign in",
    status: authView.includes("textContentType(.emailAddress)") && authView.includes("signUp(email:") ? "pass" : "fail",
    detail: authView ? "AuthView collects email for sign-in and sign-up." : "AuthView.swift not found.",
  });

  const serverTs = readRepoFile("backend/api/src/server.ts");
  const initSql = readRepoFile("supabase/migrations/20260420000000_init.sql");
  checks.push({
    id: "stores-gameplay",
    requirement: "Server stores gameplay/lobby/game state in the database",
    status:
      serverTs.includes('.from("lobbies")') &&
      serverTs.includes('.from("games")') &&
      initSql.includes("create table if not exists public.games")
        ? "pass"
        : "fail",
    detail: "Lobbies, games, and move logs are persisted via Supabase.",
  });

  const infoPlist = readRepoFile("ios/GinRummyApp/GinRummyApp/Info.plist");
  const apiPkg = readRepoFile("backend/api/package.json");
  checks.push({
    id: "uses-supabase",
    requirement: "App and API use Supabase for auth/database",
    status:
      infoPlist.includes("SUPABASE_URL") &&
      apiPkg.includes("@supabase/supabase-js")
        ? "pass"
        : "fail",
    detail: "Supabase URL/keys in Info.plist; @supabase/supabase-js in API.",
  });

  checks.push({
    id: "uses-railway",
    requirement: "Backend may be hosted on Railway",
    status:
      infoPlist.includes("railway.app") || serverTs.includes("RAILWAY_ENVIRONMENT")
        ? "pass"
        : "warn",
    detail: "Production Info.plist points at railway.app; server adapts bind host for Railway.",
  });

  checks.push({
    id: "no-sell",
    requirement: "Policy states we do not sell personal data",
    status: renderPrivacyPolicyPage({ contactEmail: "test@example.com" }).includes("do not sell")
      ? "pass"
      : "fail",
    detail: "Privacy policy page includes a no-sale statement.",
  });

  const iosTree = [
    readRepoFile("ios/GinRummyApp/GinRummyApp.xcodeproj/project.pbxproj"),
    authView,
    readRepoFile("ios/GinRummyApp/GinRummyApp/AppModel.swift"),
  ].join("\n");
  const analyticsHit = ANALYTICS_SDK_PATTERNS.find((re) => re.test(iosTree) || re.test(apiPkg));
  checks.push({
    id: "no-third-party-analytics",
    requirement: "No third-party analytics/crash SDKs in app or API dependencies",
    status: analyticsHit ? "fail" : "pass",
    detail: analyticsHit
      ? `Found possible analytics SDK reference: ${analyticsHit.source}`
      : "No Firebase/Sentry/Amplitude/etc. detected in iOS project or API package.json.",
  });

  const accountSettings = readRepoFile("ios/GinRummyApp/GinRummyApp/AccountSettingsView.swift");
  const apiClient = readRepoFile("ios/GinRummyApp/GinRummyApp/APIClient.swift");
  checks.push({
    id: "account-deletion",
    requirement: "Users can request account deletion in-app; API implements deletion",
    status:
      accountSettings.includes("Delete account") &&
      apiClient.includes("/account/delete") &&
      serverTs.includes('app.post("/account/delete"')
        ? "pass"
        : "fail",
    detail: "Account settings UI calls POST /account/delete which removes the Supabase user.",
  });

  const contact = privacyContactEmail();
  checks.push({
    id: "contact-email",
    requirement: "Privacy policy includes a contact email for privacy/support",
    status: contact.includes("@") ? "pass" : "fail",
    detail: `Contact: ${contact}`,
  });

  checks.push({
    id: "privacy-page-route",
    requirement: "API serves a public /privacy HTML page",
    status: serverTs.includes('app.get("/privacy"') ? "pass" : "fail",
    detail: "GET /privacy returns the privacy policy HTML.",
  });

  const authHasLink =
    authView.includes("privacyPolicyURL") || authView.includes("/privacy");
  const accountHasLink =
    accountSettings.includes("privacyPolicyURL") || accountSettings.includes("/privacy");
  checks.push({
    id: "in-app-privacy-link",
    requirement: "App links to the privacy policy from auth or account screens",
    status: authHasLink || accountHasLink ? "pass" : "fail",
    detail: authHasLink || accountHasLink
      ? "Privacy policy URL linked in the iOS app."
      : "Add a Privacy Policy link in AuthView or AccountSettingsView.",
  });

  const manualStore = readRepoFile("ios/GinRummyApp/GinRummyApp/ManualScoreStore.swift");
  const policyHtml = renderPrivacyPolicyPage({ contactEmail: contact });
  checks.push({
    id: "discloses-local-scorecard",
    requirement: "Policy discloses optional on-device manual scorecard data",
    status:
      manualStore.includes("UserDefaults") && policyHtml.includes("manual scorecard")
        ? "pass"
        : "warn",
    detail: "Manual score sheet uses UserDefaults; policy should mention it for Apple accuracy.",
  });

  checks.push({
    id: "discloses-chat",
    requirement: "Policy discloses in-game chat message storage",
    status:
      readRepoFile("supabase/migrations/20260511000000_game_chat.sql").includes("game_chat_messages") &&
      policyHtml.includes("chat")
        ? "pass"
        : "warn",
    detail: "Chat messages are stored server-side and should be disclosed.",
  });

  checks.push({
    id: "apple-privacy-manifest",
    requirement: "iOS PrivacyInfo.xcprivacy manifest present (App Store)",
    status: existsSync(join(REPO_ROOT, "ios/GinRummyApp/GinRummyApp/PrivacyInfo.xcprivacy"))
      ? "pass"
      : "warn",
    detail: "Apple may require PrivacyInfo.xcprivacy for UserDefaults/Keychain API declarations.",
  });

  return checks;
}

export function failingComplianceChecks(checks: PrivacyComplianceCheck[] = auditPrivacyCompliance()): PrivacyComplianceCheck[] {
  return checks.filter((c) => c.status === "fail");
}
