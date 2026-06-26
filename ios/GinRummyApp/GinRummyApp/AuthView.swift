import SwiftUI

/// Landing screen: choose to sign in or create an account. Each choice pushes a
/// dedicated form so the first tap isn't gated behind filling in fields.
struct AuthView: View {
    @EnvironmentObject private var app: AppModel

    private enum Route: Hashable {
        case signIn
        case signUp
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 48)

            GinRummyLogoBlock(subtitle: "Play with friends")

            Spacer(minLength: 16)

            VStack(spacing: 14) {
                if let lastError = app.lastError, !lastError.isEmpty {
                    FeedbackLine(text: lastError, isError: true, privateClubStyle: true)
                        .padding(.bottom, 4)
                }

                NavigationLink(value: Route.signIn) {
                    Text("Sign in")
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { app.lastError = nil })

                NavigationLink(value: Route.signUp) {
                    Text("Create account")
                }
                .buttonStyle(GinGhostButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { app.lastError = nil })
            }
            .padding(.horizontal, 24)

            if let privacyURL = AppConfig.privacyPolicyURL {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
                    .padding(.bottom, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .signIn: AuthFormView(mode: .signIn)
            case .signUp: AuthFormView(mode: .signUp)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
    }
}

/// Dedicated sign-in / create-account form.
struct AuthFormView: View {
    enum Mode {
        case signIn
        case signUp

        var navTitle: String { self == .signIn ? "Sign in" : "Create account" }
        var subtitle: String { self == .signIn ? "Welcome back" : "Join the table" }
        var cta: String { self == .signIn ? "Sign in" : "Create account" }
    }

    let mode: Mode

    @EnvironmentObject private var app: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true

    @FocusState private var focused: Field?
    private enum Field { case email, password, confirm }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GinRummyLogoBlock(subtitle: mode.subtitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                fieldLabel("Email")
                TextField("", text: $email)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .ginOutlinedField()

                fieldLabel("Password")
                SecureField("", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .focused($focused, equals: .password)
                    .submitLabel(mode == .signUp ? .next : .go)
                    .onSubmit {
                        if mode == .signUp { focused = .confirm } else { Task { await submit() } }
                    }
                    .ginOutlinedField()

                if mode == .signUp {
                    fieldLabel("Confirm password")
                    SecureField("", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .ginOutlinedField()

                    Text("Use at least 6 characters.")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
                }

                Button(busy ? "Working…" : mode.cta) {
                    Task { await submit() }
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(busy ? 0.7 : 1)
                .padding(.top, 4)

                if !message.isEmpty {
                    FeedbackLine(text: message, isError: messageIsError, privateClubStyle: true)
                        .padding(.top, 4)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(mode.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = .email }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
    }

    private var canSubmit: Bool {
        guard !busy, !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return password.count >= 6 && password == confirmPassword
        }
        return true
    }

    private func submit() async {
        switch mode {
        case .signIn: await signIn()
        case .signUp: await signUp()
        }
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
        guard password == confirmPassword else {
            message = "Those passwords don't match. Re-enter them and try again."
            messageIsError = true
            return
        }
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
                message = "Account created. Check your email for a confirmation link, then come back and sign in."
            }
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}
