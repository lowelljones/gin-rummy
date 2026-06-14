import SwiftUI

/// Session scorecard styled like a paper gin-rummy sheet: player box rows, per-game We/They
/// hand columns, and totals — for every match played in the same lobby sitting.
struct ScorecardView: View {
    @EnvironmentObject private var app: AppModel
    let inviteCode: String?
    let gameId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var recap: SessionRecapResponse?
    @State private var loadError: String?
    @State private var busy = false

    private let cellMinWidth: CGFloat = 44
    private let labelWidth: CGFloat = 72

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
            .background(GinRummyPalette.bgDeep.opacity(0.98))
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GinRummyPalette.gold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await loadRecap() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(busy)
                    .accessibilityLabel("Refresh scorecard")
                }
            }
            .task { await loadRecap() }
        }
        .ginFeltChrome()
    }

    @ViewBuilder
    private func scorecardContent(_ recap: SessionRecapResponse) -> some View {
        let mySeat = recap.players.first(where: { $0.isSelf })?.seat ?? 0
        let matches = recap.matches

        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                scorecardHeader()
                scorecardSheet(recap: recap, mySeat: mySeat, matches: matches)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func scorecardHeader() -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GIN RUMMY")
                    .font(GinRummyPalette.titleFont(size: 22))
                    .foregroundStyle(GinRummyPalette.cream)
                    .tracking(2.5)
                Text("Score sheet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .textCase(.uppercase)
            }
            Spacer(minLength: 8)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(GinRummyPalette.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func scorecardSheet(
        recap: SessionRecapResponse,
        mySeat: Int,
        matches: [SessionMatchRecapDTO]
    ) -> some View {
        let playerRows = playerLabels(recap: recap, mySeat: mySeat)
        let maxHands = matches.map(\.handScores.count).max() ?? 0

        VStack(spacing: 0) {
            // Player box rows (betting +/- per game)
            boxBettingSection(
                matches: matches,
                playerRows: playerRows,
                mySeat: mySeat
            )

            gridDivider(thick: true)

            // Hand-by-hand We / They grid
            handGridSection(
                matches: matches,
                maxHands: maxHands,
                mySeat: mySeat
            )

            gridDivider(thick: true)

            // Totals footer
            totalsSection(
                matches: matches,
                playerRows: playerRows,
                mySeat: mySeat,
                totals: recap.totals
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GinRummyPalette.cream.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(GinRummyPalette.burgundy.opacity(0.72), lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(GinRummyPalette.burgundy.opacity(0.45), lineWidth: 1)
                .padding(3)
        )
        .colorScheme(.light)
    }

    // MARK: - Box betting rows

    @ViewBuilder
    private func boxBettingSection(
        matches: [SessionMatchRecapDTO],
        playerRows: [(seat: Int, label: String)],
        mySeat: Int
    ) -> some View {
        HStack(spacing: 0) {
            cornerCell("Players")
            ForEach(matches) { match in
                gameHeaderCell(match: match)
            }
        }

        ForEach(playerRows, id: \.seat) { row in
            HStack(spacing: 0) {
                labelCell(row.label, bold: true)
                ForEach(matches) { match in
                    boxCell(for: match, seat: row.seat)
                }
            }
            .overlay(gridDivider(), alignment: .bottom)
        }
    }

    @ViewBuilder
    private func boxCell(for match: SessionMatchRecapDTO, seat: Int) -> some View {
        let text: String
        if let bucket = match.bettingBucket, let winner = match.winnerSeat {
            if winner == seat {
                text = "+\(bucket)"
            } else {
                text = "-\(bucket)"
            }
        } else if match.isCurrent {
            text = "…"
        } else {
            text = "—"
        }
        dataCell(text, emphasized: match.bettingBucket != nil, compact: true)
            .frame(minWidth: cellMinWidth * 2)
            .overlay(gridDividerVertical(), alignment: .trailing)
    }

    // MARK: - Hand grid

    @ViewBuilder
    private func handGridSection(
        matches: [SessionMatchRecapDTO],
        maxHands: Int,
        mySeat: Int
    ) -> some View {
        HStack(spacing: 0) {
            cornerCell("")
            ForEach(matches) { match in
                weTheyHeader(match: match)
            }
        }

        if maxHands == 0 {
            HStack(spacing: 0) {
                labelCell("No scored hands yet", bold: false)
                ForEach(matches) { _ in
                    weTheyEmptyCell()
                }
            }
        } else {
            ForEach(0 ..< maxHands, id: \.self) { row in
                HStack(spacing: 0) {
                    let anyHand = matches.compactMap { $0.handScores.indices.contains(row) ? $0.handScores[row] : nil }.first
                    let handLabel = anyHand.map { "Hand \($0.handIndex + 1)" } ?? "Hand \(row + 1)"
                    labelCell(handLabel, bold: false)
                    ForEach(matches) { match in
                        handRowCell(match: match, row: row, mySeat: mySeat)
                    }
                }
                .overlay(gridDivider(), alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func weTheyEmptyCell() -> some View {
        HStack(spacing: 0) {
            dataCell("—", compact: true)
            dataCell("—", compact: true, trailing: true)
        }
        .overlay(Rectangle().frame(width: 1).foregroundStyle(gridLineColor), alignment: .leading)
    }

    @ViewBuilder
    private func weTheyHeader(match: SessionMatchRecapDTO) -> some View {
        HStack(spacing: 0) {
            subHeaderCell("We")
            subHeaderCell("They", trailing: true)
        }
        .overlay(Rectangle().frame(width: 1).foregroundStyle(gridLineColor), alignment: .leading)
    }

    @ViewBuilder
    private func handRowCell(
        match: SessionMatchRecapDTO,
        row: Int,
        mySeat: Int
    ) -> some View {
        let hand = row < match.handScores.count ? match.handScores[row] : nil
        let wePoints = hand.flatMap { pointsForSelf(hand: $0, mySeat: mySeat) }
        let theyPoints = hand.flatMap { pointsForOpponent(hand: $0, mySeat: mySeat) }

        HStack(spacing: 0) {
            dataCell(wePoints.map(String.init) ?? "", compact: true)
            dataCell(theyPoints.map(String.init) ?? "", compact: true, trailing: true)
        }
        .overlay(Rectangle().frame(width: 1).foregroundStyle(gridLineColor), alignment: .leading)
    }

    private func pointsForSelf(hand: HandScoreRecapDTO, mySeat: Int) -> Int? {
        guard hand.winnerSeat == mySeat else { return nil }
        return hand.pointsAwarded
    }

    private func pointsForOpponent(hand: HandScoreRecapDTO, mySeat: Int) -> Int? {
        guard hand.winnerSeat != mySeat else { return nil }
        return hand.pointsAwarded
    }

    // MARK: - Totals

    @ViewBuilder
    private func totalsSection(
        matches: [SessionMatchRecapDTO],
        playerRows: [(seat: Int, label: String)],
        mySeat: Int,
        totals: SessionTotalsDTO
    ) -> some View {
        HStack(spacing: 0) {
            labelCell("Total", bold: true)
            ForEach(matches) { match in
                totalCell(match: match, mySeat: mySeat)
            }
        }
        .overlay(gridDivider(), alignment: .bottom)

        HStack(spacing: 0) {
            labelCell("Box", bold: true)
            ForEach(matches) { match in
                let bucketText = match.bettingBucket.map(String.init) ?? (match.isCurrent ? "…" : "—")
                dataCell(bucketText, emphasized: match.bettingBucket != nil, compact: true)
                    .frame(minWidth: cellMinWidth * 2)
                    .overlay(gridDividerVertical(), alignment: .trailing)
            }
        }
        .overlay(gridDivider(thick: true), alignment: .bottom)

        // Net boxes row spanning full width
        let myNet = netBoxes(for: mySeat, matches: matches)
        let oppSeat = 1 - mySeat
        let oppNet = netBoxes(for: oppSeat, matches: matches)

        HStack(spacing: 0) {
            labelCell("Net boxes", bold: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(playerRows, id: \.seat) { row in
                    let net = row.seat == mySeat ? myNet : oppNet
                    Text("\(row.label) · \(signed(net))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(scoreInk)
                }
                if totals.completedMatches > 0 {
                    Text("Session · \(totals.totalBuckets) boxes · \(totals.totalBettingRaw) raw")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(scoreInk.opacity(0.75))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GinRummyPalette.gold.opacity(0.22))
    }

    @ViewBuilder
    private func totalCell(match: SessionMatchRecapDTO, mySeat: Int) -> some View {
        let myScore = match.scores.count > mySeat ? match.scores[mySeat] : 0
        let theirScore = match.scores.count > (1 - mySeat) ? match.scores[1 - mySeat] : 0
        HStack(spacing: 0) {
            dataCell("\(myScore)", emphasized: true, compact: true)
            dataCell("\(theirScore)", emphasized: true, compact: true, trailing: true)
        }
        .overlay(Rectangle().frame(width: 1).foregroundStyle(gridLineColor), alignment: .leading)
    }

    private func netBoxes(for seat: Int, matches: [SessionMatchRecapDTO]) -> Int {
        matches.reduce(0) { sum, match in
            guard let bucket = match.bettingBucket, let winner = match.winnerSeat else { return sum }
            return sum + (winner == seat ? bucket : -bucket)
        }
    }

    // MARK: - Grid cells

    private var scoreInk: Color { GinRummyPalette.navy.opacity(0.92) }
    private var gridLineColor: Color { GinRummyPalette.navy.opacity(0.18) }
    private var headerFill: Color { GinRummyPalette.bgPanel.opacity(0.12) }

    @ViewBuilder
    private func cornerCell(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(scoreInk.opacity(0.8))
            .textCase(.uppercase)
            .frame(width: labelWidth, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(headerFill)
            .overlay(gridDividerVertical(), alignment: .trailing)
    }

    @ViewBuilder
    private func gameHeaderCell(match: SessionMatchRecapDTO) -> some View {
        VStack(spacing: 2) {
            Text("Game \(match.matchNumber)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(scoreInk)
            if match.isCurrent {
                Text("live")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(GinRummyPalette.burgundy)
            }
        }
        .frame(minWidth: cellMinWidth * 2)
        .padding(.vertical, 6)
        .background(headerFill)
        .overlay(gridDividerVertical(), alignment: .trailing)
    }

    @ViewBuilder
    private func subHeaderCell(_ title: String, trailing: Bool = false) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(scoreInk.opacity(0.85))
            .frame(minWidth: cellMinWidth)
            .padding(.vertical, 5)
            .background(headerFill.opacity(0.85))
            .overlay(gridDividerVertical(), alignment: trailing ? .trailing : .leading)
    }

    @ViewBuilder
    private func labelCell(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(bold ? .caption.weight(.bold) : .caption2)
            .foregroundStyle(scoreInk.opacity(bold ? 0.95 : 0.8))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(width: labelWidth, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(bold ? headerFill.opacity(0.5) : Color.clear)
            .overlay(gridDividerVertical(), alignment: .trailing)
    }

    @ViewBuilder
    private func dataCell(
        _ text: String,
        emphasized: Bool = false,
        compact: Bool = false,
        trailing: Bool = false
    ) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(emphasized ? .caption.weight(.semibold).monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(
                text.hasPrefix("+") ? GinRummyPalette.bgDeep :
                text.hasPrefix("-") ? GinRummyPalette.burgundy :
                scoreInk
            )
            .frame(minWidth: compact ? cellMinWidth : cellMinWidth * 2)
            .padding(.vertical, 5)
            .overlay(gridDividerVertical(), alignment: trailing ? .trailing : .leading)
    }

    @ViewBuilder
    private func gridDivider(thick: Bool = false) -> some View {
        Rectangle()
            .fill(GinRummyPalette.navy.opacity(thick ? 0.28 : 0.15))
            .frame(height: thick ? 1.5 : 1)
    }

    @ViewBuilder
    private func gridDividerVertical() -> some View {
        Rectangle()
            .fill(gridLineColor)
            .frame(width: 1)
    }

    // MARK: - Helpers

    private func playerLabels(recap: SessionRecapResponse, mySeat: Int) -> [(seat: Int, label: String)] {
        let seat0Name = recap.players.first(where: { $0.seat == 0 })?.displayName ?? "Player 1"
        let seat1Name = recap.players.first(where: { $0.seat == 1 })?.displayName
            ?? (recap.players.count == 1 ? app.opponentDisplayName : "Player 2")
        return [
            (0, mySeat == 0 ? "You" : seat0Name),
            (1, mySeat == 1 ? "You" : seat1Name),
        ]
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private func loadRecap() async {
        guard let token = app.accessToken else { return }
        await MainActor.run {
            busy = true
            loadError = nil
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
