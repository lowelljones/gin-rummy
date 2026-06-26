import { readRepoFile } from "./privacyPolicy.js";
import type { PrivacyComplianceCheck } from "./privacyPolicy.js";
import { privacyContactEmail } from "./privacyPolicy.js";

export const TERMS_OF_SERVICE_LAST_UPDATED = "June 26, 2026";

export interface TermsOfServiceOptions {
  contactEmail: string;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function renderTermsOfServicePage(opts: TermsOfServiceOptions): string {
  const email = escapeHtml(opts.contactEmail);
  const mailto = `mailto:${email}`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Terms of Service — Gin Rummy</title>
<meta name="description" content="Terms of Service for the Gin Rummy iOS app." />
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
      <h1>Terms of Service</h1>
      <p class="updated">Last updated: ${escapeHtml(TERMS_OF_SERVICE_LAST_UPDATED)}</p>
      <p>
        These Terms of Service ("Terms") govern your use of the Gin Rummy iOS app ("the app")
        and its online multiplayer services ("the service"). By creating an account, signing in,
        or using the app, you agree to these Terms and to our
        <a href="/privacy">Privacy Policy</a>.
      </p>

      <h2>Eligibility</h2>
      <p>
        You must be at least 13 years old to use the service. If you are under the age of majority
        in your jurisdiction, you may use the app only with permission from a parent or legal guardian
        who accepts these Terms on your behalf.
      </p>

      <h2>Your account</h2>
      <ul>
        <li>You are responsible for activity under your account and for keeping your sign-in credentials secure.</li>
        <li>Provide accurate account information and do not impersonate others or create accounts for abusive purposes.</li>
        <li>You may delete your account at any time from <strong>Account → Delete account</strong> in the app.</li>
      </ul>

      <h2>Acceptable use</h2>
      <p>When using multiplayer features, lobbies, chat, and invite links, you agree not to:</p>
      <ul>
        <li>Harass, threaten, or abuse other players.</li>
        <li>Send spam, offensive, or illegal content in chat or display names.</li>
        <li>Cheat, exploit bugs, automate play, or interfere with other users' games.</li>
        <li>Attempt to reverse engineer, scrape, or overload the service.</li>
        <li>Use the app for unlawful purposes or in violation of applicable law.</li>
      </ul>
      <p>
        We may filter or reject chat messages, remove content, suspend access, or terminate accounts
        that violate these rules or that we reasonably believe harm the service or other users.
      </p>

      <h2>Gameplay and scorekeeping</h2>
      <p>
        Gin Rummy is a social card game for entertainment. The app tracks match scores and optional
        betting totals <em>within a game session</em> for convenience among friends. These are
        not real-money wagers, casino services, or regulated gambling. You and your friends are
        responsible for any side arrangements you make outside the app.
      </p>
      <p>
        Game rules are enforced by our server, but occasional delays, disconnects, or errors may
        occur. We do not guarantee uninterrupted play or that every outcome will match offline
        house rules you may prefer.
      </p>

      <h2>Intellectual property</h2>
      <p>
        The app, its design, and our content are owned by us or our licensors. We grant you a
        personal, non-exclusive, non-transferable license to use the app as intended. Do not copy,
        modify, or redistribute the app or its content except as allowed by law.
      </p>

      <h2>Service changes</h2>
      <p>
        We may update, limit, or discontinue features at any time. When we make material changes
        to these Terms, we will update the "Last updated" date above. Continued use after changes
        means you accept the revised Terms.
      </p>

      <h2>Termination</h2>
      <p>
        You may stop using the app at any time. We may suspend or terminate your access if you
        breach these Terms or if needed to protect the service. Sections that by their nature
        should survive (such as disclaimers and limits of liability) continue after termination.
      </p>

      <h2>Disclaimers</h2>
      <p>
        THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND,
        WHETHER EXPRESS OR IMPLIED, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
        PARTICULAR PURPOSE, AND NON-INFRINGEMENT.
      </p>

      <h2>Limitation of liability</h2>
      <p>
        TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE AND OUR SUPPLIERS WILL NOT BE LIABLE FOR ANY
        INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF DATA,
        PROFITS, OR GOODWILL, ARISING FROM YOUR USE OF THE APP. OUR TOTAL LIABILITY FOR ANY CLAIM
        RELATING TO THE SERVICE IS LIMITED TO THE GREATER OF (A) USD $50 OR (B) THE AMOUNT YOU
        PAID US FOR THE APP IN THE TWELVE MONTHS BEFORE THE CLAIM (IF ANY).
      </p>

      <h2>Contact</h2>
      <p>Questions about these Terms: <a href="${mailto}">${email}</a></p>
    </div>
  </main>
</body>
</html>`;
}

/** Static audit for Terms of Service / EULA alignment (App Store + in-app links). */
export function termsComplianceChecks(): PrivacyComplianceCheck[] {
  const checks: PrivacyComplianceCheck[] = [];
  const serverTs = readRepoFile("backend/api/src/server.ts");
  const authView = readRepoFile("ios/GinRummyApp/GinRummyApp/AuthView.swift");
  const accountSettings = readRepoFile("ios/GinRummyApp/GinRummyApp/AccountSettingsView.swift");
  const contact = privacyContactEmail();
  const termsHtml = renderTermsOfServicePage({ contactEmail: contact });

  checks.push({
    id: "terms-page-route",
    requirement: "API serves a public /terms HTML page",
    status: serverTs.includes('app.get("/terms"') ? "pass" : "fail",
    detail: "GET /terms returns the Terms of Service HTML.",
  });

  const authHasLink =
    authView.includes("termsOfServiceURL") || authView.includes("/terms");
  const accountHasLink =
    accountSettings.includes("termsOfServiceURL") || accountSettings.includes("/terms");
  checks.push({
    id: "in-app-terms-link",
    requirement: "App links to the Terms of Service from auth or account screens",
    status: authHasLink || accountHasLink ? "pass" : "fail",
    detail: authHasLink || accountHasLink
      ? "Terms of Service URL linked in the iOS app."
      : "Add a Terms of Service link in AuthView or AccountSettingsView.",
  });

  checks.push({
    id: "terms-contact-email",
    requirement: "Terms of Service includes a contact email",
    status: contact.includes("@") && termsHtml.includes(contact) ? "pass" : "fail",
    detail: `Contact: ${contact}`,
  });

  checks.push({
    id: "terms-privacy-crosslink",
    requirement: "Terms page references the Privacy Policy",
    status: termsHtml.includes("/privacy") ? "pass" : "fail",
    detail: "Terms page links to /privacy for data practices.",
  });

  return checks;
}

export function failingTermsComplianceChecks(
  checks: PrivacyComplianceCheck[] = termsComplianceChecks(),
): PrivacyComplianceCheck[] {
  return checks.filter((c) => c.status === "fail");
}
