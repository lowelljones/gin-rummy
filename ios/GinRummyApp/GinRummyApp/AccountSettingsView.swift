import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var busy = false
    @State private var feedback = ""
    @State private var feedbackIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !feedback.isEmpty {
                    FeedbackLine(text: feedback, isError: feedbackIsError, privateClubStyle: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Signed in as")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.sage)
                    Text(app.userEmail ?? "Your account")
                        .font(.body)
                        .foregroundStyle(GinRummyPalette.cream)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(GinRummyPalette.bgPanel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 14) {
                    Button("Sign out", role: .destructive) {
                        app.signOut()
                        dismiss()
                    }
                    .buttonStyle(GinGhostButtonStyle())

                    Button(busy ? "Deleting…" : "Delete account", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(GinGhostButtonStyle())
                    .disabled(busy)
                }

                Text("Deleting your account permanently removes your profile, lobby history, and game records. This cannot be undone.")
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GinRummyPalette.bgDeep.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and all associated game data. You will need to create a new account to play again.")
        }
    }

    private func deleteAccount() async {
        guard let token = app.accessToken else { return }
        busy = true
        feedback = ""
        defer { busy = false }
        do {
            try await app.api.deleteAccount(token: token)
            app.signOut()
            dismiss()
        } catch {
            if case APIError.badStatus(404, _) = error {
                feedback = "Account deletion isn’t available on the game server yet. Deploy the latest API, then try again."
            } else {
                feedback = UserFeedback.from(error)
            }
            feedbackIsError = true
        }
    }
}
