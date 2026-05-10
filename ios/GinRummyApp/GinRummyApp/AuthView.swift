import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var app: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true

    var body: some View {
        Form {
            Section("Supabase auth") {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Password", text: $password)
                Button(busy ? "Working…" : "Sign in") {
                    Task { await signIn() }
                }
                .disabled(busy || email.isEmpty || password.isEmpty)

                Button("Create account (sign up)") {
                    Task { await signUp() }
                }
                .disabled(busy || email.isEmpty || password.isEmpty)
            }
            if !message.isEmpty {
                Section {
                    FeedbackLine(text: message, isError: messageIsError)
                }
            }
        }
        .navigationTitle("Gin Rummy")
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
