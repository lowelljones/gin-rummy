import XCTest

@testable import GinRummyApp

/// Guards the sizing that App Review rejected 1.0 (9) over: the play table's
/// furniture was fixed at iPhone-15-class heights, so on a short canvas the
/// pinned action bar ran off the bottom of the window.
///
/// Two canvases matter and neither is a modern iPhone:
///   • 375 × 721 — the iPhone-compatibility window iPadOS hands this app; the
///     exact size the reviewer saw on an iPad Air 11".
///   • 375 × 667 — iPhone SE (3rd gen).
///
/// `TableLayoutMetrics.fit` is handed the space left *below* the status bar and
/// the table's top bar, so the budgets below are the window height minus that
/// chrome.
final class TableLayoutMetricsTests: XCTestCase {
    /// Window height minus status bar and top bar, for each canvas of interest.
    private static let iPadCompatibilityWindow: CGFloat = 721 - 38
    private static let iPhoneSE: CGFloat = 667 - 20 - 38

    // Heights of the parts the metrics don't scale. Measured off the rendered
    // layout; a little pessimistic on purpose, so drift shows up here first.

    /// Score / dealer / turn pills.
    private static let statusRowHeight: CGFloat = 34
    /// Below each pile: 6 pt gap plus the caption.
    private static let pileCaptionHeight: CGFloat = 22
    /// One line of the footnote-sized activity log.
    private static let logLineHeight: CGFloat = 18
    /// Prompt line, primary buttons, the redeal button, and the bar's padding.
    private static let actionBarHeight: CGFloat = 148
    /// statusRow, fan, centerTable, log, hand, actionBar + three collapsed spacers.
    private static let rowGapCount: CGFloat = 8

    /// Everything the table must draw at its tallest, for a given canvas.
    private func stackedHeight(_ m: TableLayoutMetrics) -> CGFloat {
        let knockRow = m.showsKnockLimitCard
            ? CardMetrics.height(for: m.knockCardWidth) + m.rowSpacing
            : 0
        let piles = CardMetrics.height(for: m.pileCardWidth) + Self.pileCaptionHeight
        let log = CGFloat(m.statusLogLineLimit) * Self.logLineHeight

        return Self.statusRowHeight
            + m.opponentFanHeight
            + knockRow + piles
            + log
            + m.handHeight
            + Self.actionBarHeight
            + m.rowSpacing * Self.rowGapCount
    }

    private func assertFits(_ height: CGFloat, _ message: String, line: UInt = #line) {
        let m = TableLayoutMetrics.fit(availableHeight: height)
        XCTAssertLessThanOrEqual(stackedHeight(m), height, message, line: line)
    }

    func testFitsTheIPadCompatibilityWindowThatWasRejected() {
        assertFits(Self.iPadCompatibilityWindow, "This canvas is the rejection — it must fit.")
    }

    func testFitsIPhoneSE() {
        assertFits(Self.iPhoneSE, "iPhone SE is a supported device and was overflowing too.")
    }

    /// Includes the point where the knock-limit row switches back on, which is
    /// where a naive threshold would blow the budget.
    func testFitsEveryHeightFromTheFloorUp() {
        for height in stride(from: TableLayoutMetrics.compactHeight, through: 1000, by: 5) {
            assertFits(height, "Table furniture must fit a \(Int(height)) pt canvas.")
        }
    }

    func testShorterCanvasesNeverGrowTheFurniture() {
        var previous = TableLayoutMetrics.fit(availableHeight: 400)
        for height in stride(from: CGFloat(410), through: 1200, by: 10) {
            let m = TableLayoutMetrics.fit(availableHeight: height)
            XCTAssertGreaterThanOrEqual(m.handHeight, previous.handHeight)
            XCTAssertGreaterThanOrEqual(m.opponentFanHeight, previous.opponentFanHeight)
            XCTAssertGreaterThanOrEqual(m.pileCardWidth, previous.pileCardWidth)
            XCTAssertGreaterThanOrEqual(m.knockCardWidth, previous.knockCardWidth)
            previous = m
        }
    }

    func testClampsAtBothEnds() {
        let tiny = TableLayoutMetrics.fit(availableHeight: 0)
        let floor = TableLayoutMetrics.fit(availableHeight: TableLayoutMetrics.compactHeight)
        XCTAssertEqual(tiny, floor, "Below the floor the metrics must clamp, not go negative.")

        let reference = TableLayoutMetrics.fit(availableHeight: TableLayoutMetrics.referenceHeight)
        let huge = TableLayoutMetrics.fit(availableHeight: 2000)
        XCTAssertEqual(huge, reference, "Past the reference height the design must stop scaling up.")
        XCTAssertEqual(reference.handHeight, 152, "Roomy canvases keep the original hand size.")
        XCTAssertEqual(reference.opponentFanHeight, 74)
    }

    /// The layoff screen sizes its cards with `deadwoodRowWidth`, which assumes the
    /// row wraps. It used to render a flat row instead, so a ten-card hand laid out
    /// ~630 pt wide inside a 375 pt window and dragged the rest of the screen off
    /// the right edge. Sizing and rendering have to agree about the wrap point.
    func testDeadwoodRowFitsTheWidthItWasSizedFor() {
        for count in 1 ... 11 {
            let available: CGFloat = 375 - 16
            let width = CardMetrics.handEndCardWidth(
                availableWidth: available,
                meldCardCounts: [],
                maxDeadwoodCount: count
            )
            let perRow = CardMetrics.deadwoodCardsInWidestRow(cardCount: count)
            let spacing = max(4, width * 0.10)
            let rendered = CGFloat(perRow) * width + spacing * CGFloat(perRow - 1)
            XCTAssertLessThanOrEqual(
                rendered, available,
                "\(count) unmelded cards wrap to \(perRow) per row and must fit."
            )
        }
    }
}
