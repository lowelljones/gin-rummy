import XCTest
@testable import GinRummyApp

@MainActor
final class PasswordResetURLTests: XCTestCase {
    func testCustomSchemeResetLinkParsesTokens() {
        let url = URL(string: "ginrummy://reset-password#access_token=abc123&refresh_token=ref456&expires_in=3600&type=recovery")!
        XCTAssertTrue(AppModel.isPasswordResetURL(url))
        let session = AppModel.parsePasswordResetSession(from: url)
        XCTAssertEqual(session?.accessToken, "abc123")
        XCTAssertEqual(session?.refreshToken, "ref456")
        XCTAssertEqual(session?.expiresIn, 3600)
    }

    func testHttpsResetLinkParsesTokens() {
        let url = URL(string: "https://gin-rummy-production.up.railway.app/reset-password#access_token=tok&refresh_token=rt")!
        XCTAssertTrue(AppModel.isPasswordResetURL(url))
        XCTAssertEqual(AppModel.parsePasswordResetSession(from: url)?.accessToken, "tok")
    }

    func testInviteLinksAreNotPasswordReset() {
        let invite = URL(string: "ginrummy://join/URKCZSD2")!
        XCTAssertFalse(AppModel.isPasswordResetURL(invite))
        XCTAssertNil(AppModel.parsePasswordResetSession(from: invite))
    }

    func testResetLinkWithoutFragmentReturnsNil() {
        let url = URL(string: "ginrummy://reset-password")!
        XCTAssertTrue(AppModel.isPasswordResetURL(url))
        XCTAssertNil(AppModel.parsePasswordResetSession(from: url))
    }
}
