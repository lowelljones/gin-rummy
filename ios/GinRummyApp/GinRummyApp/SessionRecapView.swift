import SwiftUI

/// Full sitting recap: every consecutive match in the lobby with scores and box (bucket) results.
struct SessionRecapView: View {
    @EnvironmentObject private var app: AppModel
    let inviteCode: String?
    let gameId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var recap: SessionRecapResponse?
    @State private var loadError: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                if let recap {
                    recapContent(recap)
                } else if busy {
                    ProgressView("Loading session…")
                        .tint(GinRummyPalette.gold)
                } else if let loadError {
                    ContentUnavailableView(
                        "Couldn't load session",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView("Loading session…")
                        .tint(GinRummyPalette.gold)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GinRummyPalette.bgDeep.opacity(0.98))
            .navigationTitle("Session results")
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
                    .accessibilityLabel("Refresh session")
                }
            }
            .task { await loadRecap() }
        }
        .ginFeltChrome()
    }

    @ViewBuilder
    private func recapContent(_ recap: SessionRecapResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sessionHeader(recap)
                if recap.matches.isEmpty {
                    Text("No matches recorded yet.")
                        .font(.subheadline)
                        .foregroundStyle(GinRummyPalette.sage)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(recap.matches) { match in
                        matchCard(match, players: recap.players)
                    }
                }
                if recap.totals.completedMatches > 0 {
                    totalsFooter(recap)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func sessionHeader(_ recap: SessionRecapResponse) -> some View {
        let seat0 = recap.players.first(where: { $0.seat == 0 })?.displayName ?? "Seat 0"
        let seat1 = recap.players.first(where: { $0.seat == 1 })?.displayName
            ?? (recap.players.count == 1 ? app.opponentDisplayName : "Seat 1")

        VStack(alignment: .leading, spacing: 8) {
            Text("\(seat0) vs \(seat1)")
                .font(.title3.bold())
                .foregroundStyle(GinRummyPalette.cream)
            Text("Match wins · \(recap.totals.matchWins[0]) – \(recap.totals.matchWins[1])")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            if recap.totals.completedMatches > 0 {
                Text("Session boxes · \(recap.totals.totalBuckets) total · \(recap.totals.totalBettingRaw) raw")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(GinRummyPalette.bgPanel.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GinRummyPalette.gold.opacity(0.28)))
    }

    @ViewBuilder
    private func matchCard(_ match: SessionMatchRecapDTO, players: [LobbyPlayerDTO]) -> some View {
        let mySeat = players.first(where: { $0.isSelf })?.seat
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Match \(match.matchNumber)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                Spacer(minLength: 8)
                statusBadge(match)
            }

            Text("Score · \(match.scores[0]) – \(match.scores[1])")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(GinRummyPalette.cream.opacity(0.95))
            Text("Hands won · \(match.handsWon[0]) – \(match.handsWon[1])")
                .font(.caption.monospacedDigit())
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))

            if let winner = match.winnerSeat {
                Text(winnerLabel(winner: winner, mySeat: mySeat, players: players))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.gold)
            }

            if let bucket = match.bettingBucket,
               let raw = match.bettingRaw,
               match.scores.count == 2,
               match.handsWon.count == 2,
               let breakdown = BettingSettlementBreakdown.compute(
                   scores: match.scores,
                   handsWon: match.handsWon,
                   raceTarget: match.raceTarget
               ) {
                Divider().overlay(GinRummyPalette.gold.opacity(0.25))
                HStack {
                    Text("Box (bucket)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(bucket)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(GinRummyPalette.gold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    boxRow("Win bonus", breakdown.winBonus)
                    boxRow("Score margin", breakdown.scoreDiff)
                    if breakdown.shutoutBonus > 0 {
                        boxRow("Blitz shutout", breakdown.shutoutBonus)
                    }
                    boxRow("Net boxes (25 × \(breakdown.netHands))", breakdown.handsBonus)
                    boxRow("Raw", raw, emphasized: true)
                    Text("\(raw) raw → bucket \(bucket) (\(BettingSettlementBreakdown.bucketRangeLabel(for: bucket)))")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                }
            } else if match.status == "active" {
                Text("Match still in progress — box settles when someone reaches \(match.raceTarget).")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            } else if match.status == "abandoned" {
                Text("Match ended early — no box settlement.")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(match.isCurrent ? GinRummyPalette.navy.opacity(0.35) : GinRummyPalette.bgPanel.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    match.isCurrent ? GinRummyPalette.gold.opacity(0.55) : GinRummyPalette.gold.opacity(0.22),
                    lineWidth: match.isCurrent ? 1.5 : 1
                )
        )
    }

    @ViewBuilder
    private func statusBadge(_ match: SessionMatchRecapDTO) -> some View {
        let label: String
        let color: Color
        switch match.status {
        case "active":
            label = match.isCurrent ? "In progress" : "Active"
            color = GinRummyPalette.sage
        case "abandoned":
            label = "Abandoned"
            color = GinRummyPalette.burgundy.opacity(0.9)
        default:
            label = "Complete"
            color = GinRummyPalette.gold
        }
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(GinRummyPalette.navy)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.92)))
    }

    @ViewBuilder
    private func totalsFooter(_ recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session totals")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream)
            Text("Matches completed · \(recap.totals.completedMatches)")
                .font(.caption)
            Text("Match wins · \(recap.totals.matchWins[0]) – \(recap.totals.matchWins[1])")
                .font(.caption.monospacedDigit())
            Text("Combined boxes · \(recap.totals.totalBuckets) · \(recap.totals.totalBettingRaw) raw")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(GinRummyPalette.burgundy.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GinRummyPalette.burgundy.opacity(0.35)))
    }

    private func boxRow(_ label: String, _ value: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .caption.weight(.semibold) : .caption)
            Spacer()
            Text(value >= 0 ? "+\(value)" : "\(value)")
                .font(emphasized ? .caption.weight(.semibold).monospacedDigit() : .caption.monospacedDigit())
        }
        .foregroundStyle(GinRummyPalette.cream.opacity(emphasized ? 1 : 0.92))
    }

    private func winnerLabel(winner: Int, mySeat: Int?, players: [LobbyPlayerDTO]) -> String {
        if winner == mySeat { return "You won this match" }
        let name = players.first(where: { $0.seat == winner })?.displayName ?? app.opponentDisplayName
        return "\(name) won this match"
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
