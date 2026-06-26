import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayNameDraft = ""
    @State private var showDeleteConfirm = false
    @State private var profileBusy = false
    @State private var saveBusy = false
    @State private var busy = false
    @State private var feedback = ""
    @State private var feedbackIsError = false
    @State private var blockedUsers: [BlockedUserDTO] = []
    @State private var blockedBusy = false
    @State private var unblockTarget: BlockedUserDTO?

    @FocusState private var displayNameFocused: Bool

    private var saveDisabled: Bool {
        saveBusy || profileBusy || trimmedDraft == app.displayName || trimmedDraft.count < 2
    }

    private var trimmedDraft: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !feedback.isEmpty {
                    FeedbackLine(text: feedback, isError: feedbackIsError, privateClubStyle: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Display name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.sage)
                    TextField("", text: $displayNameDraft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($displayNameFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveDisplayName() } }
                        .ginOutlinedField()
                        .disabled(profileBusy || saveBusy)

                    Text("Friends see this name in lobbies and invites — not your email.")
                        .font(.footnote)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.85))

                    Button(saveBusy ? "Saving…" : "Save display name") {
                        Task { await saveDisplayName() }
                    }
                    .buttonStyle(GinPrimaryButtonStyle())
                    .disabled(saveDisabled)
                    .opacity(saveDisabled && !saveBusy ? 0.65 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(GinRummyPalette.bgPanel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Blocked players")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.sage)
                    if blockedBusy && blockedUsers.isEmpty {
                        ProgressView()
                            .tint(GinRummyPalette.gold)
                    } else if blockedUsers.isEmpty {
                        Text("No blocked players. Block someone from in-game chat if their messages are objectionable.")
                            .font(.footnote)
                            .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
                    } else {
                        ForEach(blockedUsers) { user in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.body)
                                        .foregroundStyle(GinRummyPalette.cream)
                                }
                                Spacer()
                                Button("Unblock") {
                                    unblockTarget = user
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                            }
                        }
                    }
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

                if let privacyURL = AppConfig.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyURL)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GinRummyPalette.bgDeep.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
            await loadBlockedUsers()
        }
        .onChange(of: app.displayName) { _, name in
            if !displayNameFocused {
                displayNameDraft = name
            }
        }
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
        .confirmationDialog(
            unblockTarget.map { "Unblock \($0.displayName)?" } ?? "Unblock player?",
            isPresented: Binding(
                get: { unblockTarget != nil },
                set: { if !$0 { unblockTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unblock") {
                Task { await confirmUnblock() }
            }
            Button("Cancel", role: .cancel) {
                unblockTarget = nil
            }
        } message: {
            Text("Their chat messages will appear again in future games.")
        }
    }

    private func loadBlockedUsers() async {
        guard let token = app.accessToken else { return }
        blockedBusy = true
        defer { blockedBusy = false }
        do {
            let r = try await app.api.fetchBlockedUsers(token: token)
            blockedUsers = r.users
            await app.syncBlockedUsers()
        } catch {
            if blockedUsers.isEmpty {
                feedback = UserFeedback.from(error)
                feedbackIsError = true
            }
        }
    }

    private func confirmUnblock() async {
        guard let target = unblockTarget else { return }
        blockedBusy = true
        defer {
            blockedBusy = false
            unblockTarget = nil
        }
        do {
            try await app.unblockUser(target.userId)
            blockedUsers.removeAll { $0.userId == target.userId }
            feedback = "\(target.displayName) unblocked."
            feedbackIsError = false
        } catch {
            feedback = UserFeedback.from(error)
            feedbackIsError = true
        }
    }

    private func loadProfile() async {
        profileBusy = true
        defer { profileBusy = false }
        displayNameDraft = app.displayName
        await app.refreshProfile()
        displayNameDraft = app.displayName
    }

    private func saveDisplayName() async {
        guard !saveDisabled else { return }
        saveBusy = true
        feedback = ""
        defer { saveBusy = false }
        do {
            try await app.saveDisplayName(trimmedDraft)
            displayNameDraft = app.displayName
            displayNameFocused = false
            feedback = "Display name saved."
            feedbackIsError = false
        } catch {
            feedback = UserFeedback.from(error)
            feedbackIsError = true
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
