import XCTest
@testable import GinRummyApp

final class CardMetricsHandEndTests: XCTestCase {
    func testMeldRowWidthGrowsWithCardCount() {
        let w = CardMetrics.meldRowWidth(cardWidth: 50, cardCount: 4)
        XCTAssertGreaterThan(w, 50)
        XCTAssertLessThan(w, 50 * 4)
    }

    func testHandEndCardWidthShrinksForWideLayouts() {
        // Two 7-card runs side-by-side on a narrow phone (~359 pt content width).
        let narrow = CardMetrics.handEndCardWidth(
            availableWidth: 359,
            meldCardCounts: [7, 7],
            maxDeadwoodCount: 3
        )
        let wide = CardMetrics.handEndCardWidth(
            availableWidth: 800,
            meldCardCounts: [7, 7],
            maxDeadwoodCount: 3
        )
        XCTAssertLessThan(narrow, CardMetrics.compactWidth)
        XCTAssertEqual(wide, CardMetrics.compactWidth)
    }

    func testHandEndCardWidthRespectsDeadwoodRow() {
        let width = CardMetrics.handEndCardWidth(
            availableWidth: 320,
            meldCardCounts: [3],
            maxDeadwoodCount: 10
        )
        let deadwood = CardMetrics.deadwoodRowWidth(cardWidth: width, cardCount: 10)
        XCTAssertLessThanOrEqual(deadwood, 320)
    }

    func testHandEndCardWidthNeverBelowMinimum() {
        let width = CardMetrics.handEndCardWidth(
            availableWidth: 200,
            meldCardCounts: [7, 7, 7],
            maxDeadwoodCount: 10,
            minWidth: 34
        )
        XCTAssertGreaterThanOrEqual(width, 34)
    }
}
