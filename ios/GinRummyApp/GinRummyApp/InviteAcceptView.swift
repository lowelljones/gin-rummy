import SwiftUI

struct InviteAcceptView: View {
    @EnvironmentObject private var app: AppModel
    /// Snapshot at presentation time — stays stable while the sheet is up even if shared state changes.
    let inviteCode: String

    @State private var preview: LobbyInvitePreviewResponse?
    @State private var loading = true
    @State private var loadError = ""
    @State private var joinBusy = false
    @State private var bottomMessage = ""
    @State private var bottomIsError = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Checking invite…")
                        .tint(GinRummyPalette.gold)
                        .foregroundStyle(GinRummyPalette.cream)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !loadError.isEmpty {
                    VStack(spacing: 16) {
                        Text(loadError)
                            .foregroundStyle(GinRummyPalette.cream)
                            .multilineTextAlignment(.center)
                        Button("Close") {
                            app.rejectInviteFromDeepLink()
                        }
                        .buttonStyle(GinPrimaryButtonStyle())
                    }
                    .padding()
                } else {
                    invitationContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GinRummyPalette.bgDeep.opacity(0.98))
            .navigationTitle("Game invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GinRummyPalette.bgPanel.opacity(0.9), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(GinRummyPalette.gold)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject") {
                        app.rejectInviteFromDeepLink()
                    }
                    .foregroundStyle(GinRummyPalette.gold)
                    .disabled(joinBusy)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .task {
            await loadPreview()
        }
    }

    @ViewBuilder
    private var invitationContent: some View {
        let hostLabel = preview?.host_display_name ?? "Someone"
        let open = preview?.status == "open"

        VStack(spacing: 28) {
            Spacer(minLength: 24)
            Image(systemName: "person.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(GinRummyPalette.gold)

            Text("\(hostLabel) invited you to a game")
                .font(.title2.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(open ? "Code \(inviteCode)" : preview?.status == "closed" ? "This lobby has ended." : "This game already started.")
                .font(.subheadline)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                .multilineTextAlignment(.center)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    Task { await joinTapped() }
                } label: {
                    Label(joinBusy ? "Joining…" : "Join", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(!open || joinBusy)

                Button("Reject invitation") {
                    app.rejectInviteFromDeepLink()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.sage.opacity(1.06))
                .disabled(joinBusy)

                if !bottomMessage.isEmpty {
                    FeedbackLine(text: bottomMessage, isError: bottomIsError, privateClubStyle: true)
                }
            }
            .padding()
        }
    }

    private func loadPreview() async {
        loading = true
        loadError = ""
        do {
            preview = try await app.api.lobbyInvitePreview(inviteCode: inviteCode)
            loading = false
        } catch {
            loading = false
            loadError = UserFeedback.from(error)
        }
    }

    private func joinTapped() async {
        guard let token = app.accessToken else { return }
        joinBusy = true
        bottomMessage = ""
        bottomIsError = true
        defer { joinBusy = false }
        do {
            try await app.api.joinLobby(code: inviteCode, token: token)
            app.finishInviteAcceptedJoin(inviteCode: inviteCode.uppercased())
        } catch {
            bottomMessage = UserFeedback.from(error)
            bottomIsError = true
        }
    }
}
