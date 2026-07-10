import SwiftUI

/// Session scorecard: white grid on felt, cells sized so text sits inside the lines.
struct ScorecardView: View {
    @EnvironmentObject private var app: AppModel
    let inviteCode: String?
    let gameId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var recap: SessionRecapResponse?
    @State private var loadError: String?
    @State private var busy = false

    private let contentInset: CGFloat = 16
    private let minDisplayGameColumns = 4
    private let cellPaddingH: CGFloat = 6

    var body: some View {
        NavigationStack {
            Group {
                if let recap {
                    scorecardContent(recap)
                } else if busy {
                    ProgressView("Loading scorecard…")
                        .tint(GinRummyPalette.gold)
                } else if let loadError {
                    ContentUnavailableView(
                        "Couldn't load scorecard",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView("Loading scorecard…")
                        .tint(GinRummyPalette.gold)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GinRummyPalette.gold)
                }
            }
            .onAppear { Task { await loadRecap() } }
            .onDisappear {
                recap = nil
                loadError = nil
                busy = false
            }
        }
        .ginFeltChrome()
    }

    // MARK: - Layout model

    private struct DisplayColumn: Identifiable {
        let id: Int
        let match: SessionMatchRecapDTO?
        var isPlaceholder: Bool { match == nil }
        var title: String { "Game \((match?.matchNumber ?? id + 1))" }
        var isLive: Bool { match?.isCurrent ?? false }
    }

    private struct GridMetrics {
        let gridWidth: CGFloat
        let gridHeight: CGFloat
        let labelWidth: CGFloat
        let gamesWidth: CGFloat
        let gameColumnWidth: CGFloat
        let halfColumnWidth: CGFloat
        let rowHeight: CGFloat

        init(contentWidth: CGFloat, gridHeight: CGFloat, columnCount: Int, sectionRows: CGFloat) {
            let safeWidth = max(0, contentWidth)
            let safeHeight = max(0, gridHeight)
            gridWidth = safeWidth
            self.gridHeight = safeHeight
            labelWidth = max(0, floor(safeWidth * 0.26))
            gamesWidth = max(0, safeWidth - labelWidth)
            gameColumnWidth = max(0, floor(gamesWidth / CGFloat(max(columnCount, 1))))
            halfColumnWidth = max(0, floor(gameColumnWidth / 2))
            rowHeight = max(36, floor(safeHeight / max(sectionRows, 1)))
        }
    }

    private func displayColumns(from matches: [SessionMatchRecapDTO]) -> [DisplayColumn] {
        let count = max(matches.count, minDisplayGameColumns)
        return (0 ..< count).map { i in
            DisplayColumn(id: i, match: i < matches.count ? matches[i] : nil)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func scorecardContent(_ recap: SessionRecapResponse) -> some View {
        let mySeat = recap.players.first(where: { $0.isSelf })?.seat ?? 0
        let matches = recap.matches
        let columns = displayColumns(from: matches)

        GeometryReader { geo in
            let contentWidth = max(0, geo.size.width - contentInset * 2)
            let realMaxHands = matches.map(\.handScores.count).max() ?? 0
            let handRows = max(realMaxHands, 1)
            // tier header + 2 players + game row + we/they row + hands + 3 footer rows
            let sectionRows: CGFloat = 2 + 2 + 1 + CGFloat(handRows) + 3
            let metrics = GridMetrics(
                contentWidth: contentWidth,
                gridHeight: max(0, geo.size.height - 96),
                columnCount: columns.count,
                sectionRows: sectionRows
            )

            VStack(spacing: 0) {
                scorecardHeader()
                    .padding(.horizontal, contentInset)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                scorecardGrid(
                    recap: recap,
                    mySeat: mySeat,
                    matches: matches,
                    columns: columns,
                    metrics: metrics,
                    realMaxHands: realMaxHands,
                    handRows: handRows
                )
                .padding(.horizontal, contentInset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    private func scorecardHeader() -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GIN RUMMY")
                    .font(GinRummyPalette.titleFont(size: 24))
                    .foregroundStyle(GinRummyPalette.cream)
                    .tracking(2.5)
                Text("Score sheet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .textCase(.uppercase)
            }
            Spacer(minLength: 8)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(GinRummyPalette.gold)
        }
    }

    @ViewBuilder
    private func scorecardGrid(
        recap: SessionRecapResponse,
        mySeat: Int,
        matches: [SessionMatchRecapDTO],
        columns: [DisplayColumn],
        metrics: GridMetrics,
        realMaxHands: Int,
        handRows: Int
    ) -> some View {
        VStack(spacing: 0) {
            boxBettingSection(
                matches: matches,
                mySeat: mySeat,
                recap: recap,
                metrics: metrics
            )

            sectionDivider

            handGridSection(
                columns: columns,
                matches: matches,
                handRows: handRows,
                realMaxHands: realMaxHands,
                mySeat: mySeat,
                metrics: metrics
            )

            Spacer(minLength: 0)

            sectionDivider

            totalsSection(
                columns: columns,
                matches: matches,
                mySeat: mySeat,
                metrics: metrics
            )
        }
        .frame(width: metrics.gridWidth, height: metrics.gridHeight, alignment: .top)
        .overlay(gridOuterBorder)
    }

    // MARK: - Match tier totals

    @ViewBuilder
    private func boxBettingSection(
        matches: [SessionMatchRecapDTO],
        mySeat: Int,
        recap: SessionRecapResponse,
        metrics: GridMetrics
    ) -> some View {
        let h = metrics.rowHeight
        let youLabel = playerLabels(recap: recap, mySeat: mySeat).first(where: { $0.seat == mySeat })?.label ?? "You"

        gridRow(height: h) {
            labelCell("Players", width: metrics.labelWidth, height: h, bold: true)
            valueCell(
                "Game Totals",
                width: metrics.gamesWidth,
                height: h,
                alignment: .leading,
                style: .muted,
                uppercase: true
            )
        }

        gridRow(height: h) {
            labelCell(youLabel, width: metrics.labelWidth, height: h, bold: true)
            boxTotalsCell(matches: matches, seat: mySeat, width: metrics.gamesWidth, height: h)
        }
    }

    @ViewBuilder
    private func boxTotalsCell(
        matches: [SessionMatchRecapDTO],
        seat: Int,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            if matches.isEmpty {
                numericText("…", style: .muted)
                    .frame(width: width, height: height)
            } else {
                ForEach(Array(matches.enumerated()), id: \.element.id) { idx, match in
                    let slotW = slotWidth(index: idx, count: matches.count, totalWidth: width)
                    let text = boxCellText(for: match, seat: seat)
                    numericText(text, style: scoreStyle(for: text))
                        .frame(width: slotW, height: height, alignment: .center)
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
    }

    private func slotWidth(index: Int, count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return totalWidth }
        let base = floor(totalWidth / CGFloat(count))
        let remainder = totalWidth - base * CGFloat(count)
        return index == count - 1 ? base + remainder : base
    }

    private func boxCellText(for match: SessionMatchRecapDTO, seat: Int) -> String {
        ScorecardScoring.gameBettingBucketLabel(for: match, seat: seat)
    }

    // MARK: - Hand grid

    @ViewBuilder
    private func handGridSection(
        columns: [DisplayColumn],
        matches: [SessionMatchRecapDTO],
        handRows: Int,
        realMaxHands: Int,
        mySeat: Int,
        metrics: GridMetrics
    ) -> some View {
        let h = metrics.rowHeight
        let gcw = metrics.gameColumnWidth
        let hcw = metrics.halfColumnWidth

        gridRow(height: h) {
            labelCell("", width: metrics.labelWidth, height: h)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                gameHeaderCell(
                    column: col,
                    width: columnWidth(index: idx, count: columns.count, columnWidth: gcw, gamesWidth: metrics.gamesWidth),
                    height: h
                )
            }
        }

        gridRow(height: h) {
            labelCell("", width: metrics.labelWidth, height: h)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                weTheyPairHeader(
                    column: col,
                    width: columnWidth(index: idx, count: columns.count, columnWidth: gcw, gamesWidth: metrics.gamesWidth),
                    halfWidth: hcw,
                    height: h
                )
            }
        }

        ForEach(0 ..< handRows, id: \.self) { row in
            gridRow(height: h) {
                labelCell(
                    handRowLabel(matches: matches, row: row, realMaxHands: realMaxHands),
                    width: metrics.labelWidth,
                    height: h
                )
                ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                    let colW = columnWidth(index: idx, count: columns.count, columnWidth: gcw, gamesWidth: metrics.gamesWidth)
                    if let match = col.match {
                        weTheyDataPair(
                            we: handWePoints(match: match, row: row, mySeat: mySeat),
                            they: handTheyPoints(match: match, row: row, mySeat: mySeat),
                            width: colW,
                            halfWidth: hcw,
                            height: h,
                            empty: row >= match.handScores.count,
                            live: col.isLive
                        )
                    } else {
                        emptyWeTheyPair(width: colW, halfWidth: hcw, height: h, placeholder: true)
                    }
                }
            }
        }
    }

    private func columnWidth(index: Int, count: Int, columnWidth: CGFloat, gamesWidth: CGFloat) -> CGFloat {
        let base = columnWidth
        let remainder = gamesWidth - base * CGFloat(count)
        return index == count - 1 ? base + remainder : base
    }

    private func handRowLabel(matches: [SessionMatchRecapDTO], row: Int, realMaxHands: Int) -> String {
        if realMaxHands == 0 && row == 0 { return "Hands" }
        guard row < realMaxHands else { return "" }
        let anyHand = matches.compactMap { m in
            m.handScores.indices.contains(row) ? m.handScores[row] : nil
        }.first
        if let anyHand { return "Hand \(anyHand.handIndex + 1)" }
        return "Hand \(row + 1)"
    }

    // MARK: - Totals

    @ViewBuilder
    private func totalsSection(
        columns: [DisplayColumn],
        matches: [SessionMatchRecapDTO],
        mySeat: Int,
        metrics: GridMetrics
    ) -> some View {
        let h = metrics.rowHeight
        let gcw = metrics.gameColumnWidth
        let hcw = metrics.halfColumnWidth

        gridRow(height: h) {
            labelCell("Total", width: metrics.labelWidth, height: h, bold: true)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                let colW = columnWidth(index: idx, count: columns.count, columnWidth: gcw, gamesWidth: metrics.gamesWidth)
                if let match = col.match {
                    weTheyDataPair(
                        we: String(myScore(in: match, seat: mySeat)),
                        they: String(myScore(in: match, seat: 1 - mySeat)),
                        width: colW,
                        halfWidth: hcw,
                        height: h,
                        empty: false,
                        live: col.isLive,
                        emphasized: true
                    )
                } else {
                    emptyWeTheyPair(width: colW, halfWidth: hcw, height: h, placeholder: true)
                }
            }
        }

        gridRow(height: h) {
            labelCell("Hands", width: metrics.labelWidth, height: h, bold: true)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                let colW = columnWidth(index: idx, count: columns.count, columnWidth: gcw, gamesWidth: metrics.gamesWidth)
                if let match = col.match {
                    valueCell(
                        ScorecardScoring.netHandsLabel(for: match, seat: mySeat),
                        width: colW,
                        height: h,
                        style: match.handScores.isEmpty && !col.isLive ? .muted : .score,
                        live: col.isLive
                    )
                } else {
                    valueCell("", width: colW, height: h, style: .placeholder, placeholder: true)
                }
            }
        }

        gridRow(height: h) {
            labelCell("Match pts", width: metrics.labelWidth, height: h, bold: true)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                let colW = columnWidth(index: idx, count: columns.count, columnWidth: gcw, gamesWidth: metrics.gamesWidth)
                if let match = col.match {
                    let label = ScorecardScoring.interimNetLabel(for: match, seat: mySeat)
                    valueCell(
                        label,
                        width: colW,
                        height: h,
                        style: label == "…" || label == "—" ? .muted : .score,
                        live: col.isLive
                    )
                } else {
                    valueCell("", width: colW, height: h, style: .placeholder, placeholder: true)
                }
            }
        }
    }

    // MARK: - Cell primitives

    private enum CellTextStyle {
        case label, muted, score, placeholder

        var color: Color {
            switch self {
            case .label: GinRummyPalette.cream.opacity(0.95)
            case .muted: GinRummyPalette.sage.opacity(0.9)
            case .score: GinRummyPalette.cream.opacity(0.95)
            case .placeholder: GinRummyPalette.sage.opacity(0.25)
            }
        }
    }

    private func scoreStyle(for text: String) -> CellTextStyle {
        if text.hasPrefix("+") { return .score }
        if text.hasPrefix("-") { return .score }
        if text == "…" || text == "—" { return .muted }
        return .score
    }

    private func scoreColor(for text: String) -> Color {
        if text.hasPrefix("+") { return GinRummyPalette.gold }
        if text.hasPrefix("-") { return Color(red: 0.95, green: 0.55, blue: 0.52) }
        return GinRummyPalette.cream.opacity(0.95)
    }

    @ViewBuilder
    private func gridRow(height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(height: height)
        .overlay(rowDivider, alignment: .bottom)
    }

    @ViewBuilder
    private func labelCell(_ text: String, width: CGFloat, height: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .font(bold ? .caption.weight(.semibold) : .caption2)
            .foregroundStyle(bold ? CellTextStyle.label.color : CellTextStyle.muted.color)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, cellPaddingH)
            .frame(width: width, height: height, alignment: .leading)
            .overlay(cellBorder(right: true))
    }

    @ViewBuilder
    private func valueCell(
        _ text: String,
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment = .center,
        style: CellTextStyle = .score,
        uppercase: Bool = false,
        live: Bool = false,
        placeholder: Bool = false
    ) -> some View {
        ZStack {
            if live { liveColumnTint }
            Text(uppercase ? text.uppercased() : (text.isEmpty ? " " : text))
                .font(.caption2.weight(style == .muted ? .bold : .regular))
                .foregroundStyle(placeholder ? CellTextStyle.placeholder.color : style.color)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, cellPaddingH)
                .frame(width: width, height: height, alignment: alignment)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
    }

    @ViewBuilder
    private func numericText(_ text: String, style: CellTextStyle) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(style == .score ? scoreColor(for: text) : style.color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func gameHeaderCell(column: DisplayColumn, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if column.isLive, !column.isPlaceholder { liveColumnTint }
            VStack(spacing: 2) {
                Text(column.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(column.isPlaceholder ? CellTextStyle.placeholder.color : CellTextStyle.label.color)
                if column.isLive, !column.isPlaceholder {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(GinRummyPalette.gold)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
    }

    @ViewBuilder
    private func weTheyPairHeader(column: DisplayColumn, width: CGFloat, halfWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            subHeaderCell("We", width: halfWidth, height: height, muted: column.isPlaceholder)
            subHeaderCell("They", width: max(0, width - halfWidth), height: height, muted: column.isPlaceholder)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
        .background(column.isLive && !column.isPlaceholder ? liveColumnTint : nil)
    }

    @ViewBuilder
    private func subHeaderCell(_ title: String, width: CGFloat, height: CGFloat, muted: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(muted ? CellTextStyle.placeholder.color : CellTextStyle.muted.color)
            .frame(width: width, height: height)
            .overlay(cellBorder(right: true))
    }

    @ViewBuilder
    private func weTheyDataPair(
        we: String,
        they: String,
        width: CGFloat,
        halfWidth: CGFloat,
        height: CGFloat,
        empty: Bool,
        live: Bool,
        emphasized: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            dataCell(
                empty ? "" : we,
                width: halfWidth,
                height: height,
                emphasized: emphasized,
                placeholder: empty && we.isEmpty
            )
            dataCell(
                empty ? "" : they,
                width: max(0, width - halfWidth),
                height: height,
                emphasized: emphasized,
                placeholder: empty && they.isEmpty
            )
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
        .background(live ? liveColumnTint : nil)
    }

    @ViewBuilder
    private func emptyWeTheyPair(width: CGFloat, halfWidth: CGFloat, height: CGFloat, placeholder: Bool) -> some View {
        weTheyDataPair(
            we: "",
            they: "",
            width: width,
            halfWidth: halfWidth,
            height: height,
            empty: true,
            live: false
        )
        .opacity(placeholder ? 0.55 : 1)
    }

    @ViewBuilder
    private func dataCell(
        _ text: String,
        width: CGFloat,
        height: CGFloat,
        emphasized: Bool = false,
        placeholder: Bool = false
    ) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(emphasized ? .caption.weight(.bold).monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(placeholder ? CellTextStyle.placeholder.color : scoreColor(for: text))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, height: height, alignment: .center)
            .overlay(cellBorder(right: true))
    }

    private var liveColumnTint: Color {
        GinRummyPalette.gold.opacity(0.06)
    }

    @ViewBuilder
    private func cellBorder(right: Bool) -> some View {
        if right {
            Rectangle()
                .fill(lineColor.opacity(0.32))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(lineColor.opacity(0.28))
            .frame(height: 1)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(lineColor.opacity(0.42))
            .frame(height: 1.5)
    }

    private var gridOuterBorder: some View {
        Rectangle()
            .strokeBorder(lineColor.opacity(0.5), lineWidth: 1.5)
    }

    private var lineColor: Color { GinRummyPalette.cream }

    // MARK: - Helpers

    private func handWePoints(match: SessionMatchRecapDTO, row: Int, mySeat: Int) -> String {
        guard row < match.handScores.count else { return "" }
        let hand = match.handScores[row]
        guard hand.winnerSeat == mySeat else { return "" }
        return String(hand.pointsAwarded)
    }

    private func handTheyPoints(match: SessionMatchRecapDTO, row: Int, mySeat: Int) -> String {
        guard row < match.handScores.count else { return "" }
        let hand = match.handScores[row]
        guard hand.winnerSeat != mySeat else { return "" }
        return String(hand.pointsAwarded)
    }

    private func myScore(in match: SessionMatchRecapDTO, seat: Int) -> Int {
        guard match.scores.indices.contains(seat) else { return 0 }
        return match.scores[seat]
    }

    private func playerLabels(recap: SessionRecapResponse, mySeat: Int) -> [(seat: Int, label: String)] {
        let seat0Name = recap.players.first(where: { $0.seat == 0 })?.displayName ?? "Player 1"
        let seat1Name = recap.players.first(where: { $0.seat == 1 })?.displayName
            ?? (recap.players.count == 1 ? app.opponentDisplayName : "Player 2")
        return [
            (0, mySeat == 0 ? "You" : seat0Name),
            (1, mySeat == 1 ? "You" : seat1Name),
        ]
    }

    private func loadRecap() async {
        guard let token = app.accessToken else { return }
        await MainActor.run {
            busy = true
            loadError = nil
            recap = nil
        }
        defer { Task { @MainActor in busy = false } }
        do {
            let loaded: SessionRecapResponse
            if let gameId {
                loaded = try await app.api.sessionRecapForGame(gameId: gameId, token: token)
            } else if let inviteCode {
                loaded = try await app.api.sessionRecap(inviteCode: inviteCode, token: token)
            } else {
                await MainActor.run { loadError = "No lobby linked to this table." }
                return
            }
            await MainActor.run { recap = loaded }
        } catch {
            await MainActor.run { loadError = UserFeedback.from(error) }
        }
    }
}
