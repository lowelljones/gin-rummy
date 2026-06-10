import XCTest
@testable import GinRummyApp

/// Pins the invite-link round trip that makes "text a link to a friend" work:
///
///   1. The host's share panel produces a URL via `AppConfig.inviteShareURL`.
///   2. The friend taps it; either the HTTPS landing page bounces into the app
///      with `ginrummy://join/CODE`, or (with Universal Links) the app gets the
///      HTTPS URL directly.
///   3. `AppModel.parseInviteCode` must recover the exact invite code from
///      every one of those URL forms — otherwise the friend sees a dead end.
@MainActor
final class InviteLinkRoundTripTests: XCTestCase {

    func testParsesCustomSchemeBounceLink() {
        let url = URL(string: "ginrummy://join/URKCZSD2")!
        XCTAssertEqual(AppModel.parseInviteCode(from: url), "URKCZSD2")
    }

    func testParsesHTTPSLandingPageLink() {
        let url = URL(string: "https://gin-rummy-production.up.railway.app/join/URKCZSD2")!
        XCTAssertEqual(AppModel.parseInviteCode(from: url), "URKCZSD2")
    }

    func testParsesLowercasedPathAndNormalizesViaHandler() {
        // Codes are stored uppercased; the parser returns the raw path segment
        // and handleInviteURL uppercases. Here we only assert extraction works.
        let url = URL(string: "https://example.org/join/urkczsd2")!
        XCTAssertEqual(AppModel.parseInviteCode(from: url)?.uppercased(), "URKCZSD2")
    }

    func testRejectsURLsWithoutAJoinSegment() {
        XCTAssertNil(AppModel.parseInviteCode(from: URL(string: "https://gin-rummy-production.up.railway.app/health")!))
        XCTAssertNil(AppModel.parseInviteCode(from: URL(string: "ginrummy://other/URKCZSD2")!))
    }

    func testShareURLRoundTripsThroughParser() {
        // Whatever URL the share panel hands out must parse back to the code.
        let shared = AppConfig.inviteShareURL(forInviteCode: "URKCZSD2")
        XCTAssertEqual(AppModel.parseInviteCode(from: shared)?.uppercased(), "URKCZSD2")
    }

    func testShareURLIsHTTPSWhenAPIIsHosted() throws {
        // With GIN_API_BASE_URL / GIN_INVITE_WEB_BASE_URL pointing at a public
        // HTTPS domain, the share link must be HTTPS (tappable in Messages),
        // never a bare ginrummy:// link.
        guard !AppConfig.usesInviteCustomURLScheme else {
            throw XCTSkip("Local-dev config without a hosted HTTPS domain")
        }
        let shared = AppConfig.inviteShareURL(forInviteCode: "URKCZSD2")
        XCTAssertEqual(shared.scheme, "https")
        XCTAssertTrue(shared.path.hasSuffix("/join/URKCZSD2"))
    }
}
