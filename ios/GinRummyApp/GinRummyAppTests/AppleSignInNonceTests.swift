import CryptoKit
import XCTest
@testable import GinRummyApp

final class AppleSignInNonceTests: XCTestCase {
    func testSha256MatchesCryptoKit() {
        let raw = "test-nonce-123"
        let expected = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(AppleSignInNonce.sha256(raw), expected)
    }

    func testRandomNonceLengthAndCharset() {
        let nonce = AppleSignInNonce.random(length: 40)
        XCTAssertEqual(nonce.count, 40)
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        XCTAssertTrue(nonce.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
}
