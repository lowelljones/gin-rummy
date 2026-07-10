import SwiftUI

/// Your profile: display name, match record against real players, and a game
/// log (who you played, result, score, tier, hands). Practice-bot games are
/// listed but never counted toward the record.
struct ProfileView: View {
    @EnvironmentObject private var app: AppModel

    @State private var log: AccountGameLogResponse?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let totals = log?.totals {
                    recordCard(totals: totals)
                }

                gameLogSection

                NavigationLink(value: LobbyRoute.account) {
                    HStack {
                        Image(systemName: "gearshape")
                            .foregroundStyle(GinRummyPalette.goldAccentSoft)
                        Text("Account settings")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(GinRummyPalette.cream)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GinRummyPalette.sage)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GinRummyPalette.cream.opacity(0.14), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .background(GinRummyPalette.bgDeep)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLog() }
        .refreshable { await loadLog() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(GinRummyPalette.burgundy.opacity(0.5))
                    .overlay(Circle().stroke(GinRummyPalette.goldAccent.opacity(0.6), lineWidth: 1.2))
                Text(initials)
                    .font(GinRummyPalette.titleFont(size: 22))
                    .foregroundStyle(GinRummyPalette.cream)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                if let email = app.userEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var initials: String {
        let parts = app.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        if letters.isEmpty { return "♠" }
        return letters.map(String.init).joined().uppercased()
    }

    // MARK: - Record

    private func recordCard(totals: AccountGameLogTotalsDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECORD · REAL PLAYERS")
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(GinRummyPalette.sage)

            HStack(spacing: 0) {
                statBlock(value: "\(totals.wins)–\(totals.losses)", label: "Won–Lost")
                statBlock(value: winPercentLabel(totals), label: "Win rate")
                statBlock(value: ScorecardScoring.signed(totals.netBuckets), label: "Net tiers")
                statBlock(value: "\(totals.handsPlayed)", label: "Hands")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GinRummyPalette.bgPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(GinRummyPalette.goldAccent.opacity(0.28), lineWidth: 1)
        )
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(GinRummyPalette.cream)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
        }
        .frame(maxWidth: .infinity)
    }

    private func winPercentLabel(_ totals: AccountGameLogTotalsDTO) -> String {
        guard totals.completedGames > 0 else { return "—" }
        let pct = Double(totals.wins) / Double(totals.completedGames) * 100
        return "\(Int(pct.rounded()))%"
    }

    // MARK: - Game log

    @ViewBuilder
    private var gameLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GAME LOG")
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(GinRummyPalette.sage)

            if let errorText {
                FeedbackLine(text: errorText, isError: true, privateClubStyle: true)
            } else if loading, log == nil {
                HStack {
                    Spacer(minLength: 0)
                    ProgressView().tint(GinRummyPalette.gold)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 24)
            } else if let games = log?.games, !games.isEmpty {
                VStack(spacing: 8) {
                    ForEach(games) { game in
                        gameRow(game)
                    }
                }
            } else if log != nil {
                Text("Finished matches show up here — invite a friend and play one out.")
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .padding(.vertical, 12)
            }
        }
    }

    private func gameRow(_ game: AccountGameLogEntryDTO) -> some View {
        HStack(alignment: .center, spacing: 12) {
            resultBadge(game)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(game.opponentDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.cream)
                        .lineLimit(1)
                    if game.isBotGame {
                        Text("PRACTICE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(GinRummyPalette.sage)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().stroke(GinRummyPalette.sage.opacity(0.5), lineWidth: 1))
                    }
                }
                Text(detailLine(game))
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(game.myScore)–\(game.opponentScore)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(GinRummyPalette.cream)
                if let tier = game.signedTierLabel {
                    Text("\(tier) tier")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(tier.hasPrefix("-")
                            ? Color(red: 0.95, green: 0.55, blue: 0.52)
                            : GinRummyPalette.goldAccentSoft)
                }
            }
        }
        .padding(12)
        .background(GinRummyPalette.bgPanel.opacity(game.isBotGame ? 0.42 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func resultBadge(_ game: AccountGameLogEntryDTO) -> some View {
        let (text, tint): (String, Color) = {
            if let won = game.iWon {
                return won ? ("W", GinRummyPalette.goldAccent) : ("L", GinRummyPalette.burgundy)
            }
            return ("—", GinRummyPalette.sage.opacity(0.6))
        }()
        Text(text)
            .font(.headline.weight(.bold))
            .foregroundStyle(GinRummyPalette.cream)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint.opacity(0.55)))
            .overlay(Circle().stroke(tint, lineWidth: 1.2))
    }

    private func detailLine(_ game: AccountGameLogEntryDTO) -> String {
        var parts: [String] = []
        if let date = Self.parseDate(game.updatedAt) {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if game.handsPlayed > 0 {
            parts.append(game.handsPlayed == 1 ? "1 hand" : "\(game.handsPlayed) hands")
        }
        if game.status == "abandoned" {
            parts.append(game.iAbandoned == true ? "You left" : "They left")
        }
        return parts.joined(separator: " · ")
    }

    static func parseDate(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)
    }

    // MARK: - Networking

    private func loadLog() async {
        guard let token = app.accessToken else { return }
        loading = true
        defer { loading = false }
        do {
            let response = try await app.api.fetchAccountGames(token: token)
            log = response
            errorText = nil
            // Human opponents feed the manual-scorecard name suggestions.
            KnownOpponentsStore.remember(
                contentsOf: response.games
                    .filter { !$0.isBotGame }
                    .map(\.opponentDisplayName)
            )
        } catch {
            if log == nil { errorText = UserFeedback.from(error) }
        }
    }
}
