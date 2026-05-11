import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var app: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                GinRummyLogoBlock(subtitle: "Sign in to play")
                    .padding(.top, 32)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .ginOutlinedField()

                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                    SecureField("", text: $password)
                        .ginOutlinedField()

                    Button(busy ? "Working…" : "Sign in") {
                        Task { await signIn() }
                    }
                    .buttonStyle(GinPrimaryButtonStyle())
                    .disabled(busy || email.isEmpty || password.isEmpty)
                    .opacity(busy ? 0.7 : 1)

                    Button("Create account (sign up)") {
                        Task { await signUp() }
                    }
                    .buttonStyle(GinGhostButtonStyle())
                    .disabled(busy || email.isEmpty || password.isEmpty)

                    if !message.isEmpty {
                        FeedbackLine(text: message, isError: messageIsError, privateClubStyle: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
    }

    private func signIn() async {
        busy = true
        message = ""
        messageIsError = true
        defer { busy = false }
        do {
            let resp = try await app.api.signIn(email: email, password: password)
            app.adoptSession(resp)
            message = "Signed in."
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }

    private func signUp() async {
        busy = true
        message = ""
        messageIsError = true
        defer { busy = false }
        do {
            if let resp = try await app.api.signUp(email: email, password: password) {
                /* Email confirmation is OFF — Supabase returned a session, sign in transparently. */
                app.adoptSession(resp)
                message = "Account created. You're signed in."
            } else {
                message = "Check email for confirmation, then sign in."
            }
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}
