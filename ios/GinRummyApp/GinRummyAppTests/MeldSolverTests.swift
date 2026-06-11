import XCTest
@testable import GinRummyApp

/// Keeps the iOS discard/gin/knock button gating aligned with server house rules:
/// plain Discard is always available; Gin and EO are explicit opt-ins.
final class MeldSolverTests: XCTestCase {

    func testPlainDiscardIncludesEveryCardInAn11CardHand() {
        let hand = ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S", "KD"]
        let e = MeldSolver.eligibility(forHand11: hand, knockCheckCard: "KS")
        XCTAssertEqual(e.plain, Set(hand))
    }

    func testGinableDiscardIsAlsoPlainEligible() {
        let hand = ["2S", "3S", "4S", "5H", "6H", "7H", "8C", "8D", "8H", "8S", "KD"]
        let e = MeldSolver.eligibility(forHand11: hand, knockCheckCard: "KS")
        XCTAssertTrue(e.ginable.contains("KD"))
        XCTAssertTrue(e.plain.contains("KD"), "Players may pass up gin to keep playing toward EO")
    }

    func testKnockableAndGinableAreDisjointBuckets() {
        let hand = ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"]
        let e = MeldSolver.eligibility(forHand11: hand, knockCheckCard: "5S")
        XCTAssertTrue(e.knockable.contains("6C"))
        XCTAssertFalse(e.ginable.contains("6C"))
        XCTAssertTrue(e.plain.contains("6C"))
    }

    func testKnockableWhenUnmeldedBelowDownCardValue() {
        let hand = ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"]
        let e = MeldSolver.eligibility(forHand11: hand, knockCheckCard: "TS")
        XCTAssertTrue(e.knockable.contains("6C"), "5 unmelded is within knock limit 10")
    }

    func testAceUpcardDisablesKnockButNotPlainDiscard() {
        let hand = ["2S", "3S", "4S", "5H", "6H", "7H", "8D", "8C", "8S", "AH", "2C"]
        let e = MeldSolver.eligibility(forHand11: hand, knockCheckCard: "AS")
        XCTAssertTrue(e.knockable.isEmpty)
        XCTAssertEqual(e.plain.count, 11)
    }

    func testIsBigGin11MatchesServerEOGate() {
        let eoHand = ["2S", "3S", "4S", "5H", "6H", "7H", "8H", "9C", "9D", "9H", "9S"]
        XCTAssertTrue(MeldSolver.isBigGin11(eoHand))

        let notEo = ["AS", "2S", "3S", "7H", "8H", "9H", "KC", "KD", "KH", "5C", "6C"]
        XCTAssertFalse(MeldSolver.isBigGin11(notEo))
    }

    func testUpcardKnockValueNullForAce() {
        XCTAssertNil(MeldSolver.upcardKnockValue("AS"))
        XCTAssertEqual(MeldSolver.upcardKnockValue("5S"), 5)
    }
}
