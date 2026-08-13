import SwiftUI

/// The terms/privacy line shown wherever an account can be created — the email
/// sign-up form and the landing screen (Sign in with Apple creates an account on
/// first use, so it needs the same disclosure).
///
/// App Review guideline 1.2 expects apps with user-generated content — this one
/// has chat and player-chosen display names — to have terms the user agrees to
/// before using the app, not just a link sitting somewhere in the UI.
struct LegalConsentText: View {
    /// Verb for the action the button next to this line performs.
    var action: String = "continuing"

    /// Built as an `AttributedString` rather than markdown in a `Text`, because a
    /// `foregroundStyle` on the whole `Text` repaints the links in the body color
    /// and they stop looking tappable. Colouring the link runs directly survives it.
    private var sentence: AttributedString? {
        let terms = AppConfig.termsOfServiceURL
        let privacy = AppConfig.privacyPolicyURL
        guard terms != nil || privacy != nil else { return nil }

        var out = plain("By \(action), you agree to our ")
        switch (terms, privacy) {
        case let (terms?, privacy?):
            out += link("Terms of Service", terms)
            out += plain(" and ")
            out += link("Privacy Policy", privacy)
        case let (terms?, nil):
            out += link("Terms of Service", terms)
        case let (nil, privacy?):
            out += link("Privacy Policy", privacy)
        case (nil, nil):
            return nil
        }
        out += plain(".")
        return out
    }

    private func plain(_ text: String) -> AttributedString {
        var s = AttributedString(text)
        s.foregroundColor = GinRummyPalette.sage.opacity(0.85)
        return s
    }

    private func link(_ text: String, _ url: URL) -> AttributedString {
        var s = AttributedString(text)
        s.link = url
        s.foregroundColor = GinRummyPalette.gold
        s.underlineStyle = .single
        return s
    }

    var body: some View {
        if let sentence {
            Text(sentence)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Landing screen: choose to sign in or create an account. Each choice pushes a
/// dedicated form so the first tap isn't gated behind filling in fields.
struct AuthView: View {
    @EnvironmentObject private var app: AppModel
    @State private var appleBusy = false

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

                GinAppleSignInButton(
                    busy: $appleBusy,
                    onError: { app.lastError = $0 },
                    onClearError: { app.lastError = nil }
                )

                authDivider(label: "or use email")

                NavigationLink(value: Route.signIn) {
                    Text("Sign in")
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(appleBusy)
                .simultaneousGesture(TapGesture().onEnded { app.lastError = nil })

                NavigationLink(value: Route.signUp) {
                    Text("Create account")
                }
                .buttonStyle(GinGhostButtonStyle())
                .disabled(appleBusy)
                .simultaneousGesture(TapGesture().onEnded { app.lastError = nil })
            }
            .padding(.horizontal, 24)

            LegalConsentText()
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

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

    private func authDivider(label: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(GinRummyPalette.sage.opacity(0.35))
                .frame(height: 1)
            Text(label)
                .font(.caption)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
            Rectangle()
                .fill(GinRummyPalette.sage.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
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
    @State private var appleBusy = false
    @State private var message = ""
    @State private var messageIsError = true

    @FocusState private var focused: Field?
    private enum Field { case email, password, confirm }

    private var formBusy: Bool { busy || appleBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GinRummyLogoBlock(subtitle: mode.subtitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                if mode == .signIn {
                    GinAppleSignInButton(
                        busy: $appleBusy,
                        onError: { message = $0; messageIsError = true },
                        onClearError: { message = "" }
                    )
                    authDivider(label: "or use email")
                }

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

                if mode == .signIn {
                    NavigationLink {
                        ForgotPasswordView()
                    } label: {
                        Text("Forgot password?")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                    }
                    .padding(.top, -4)
                }

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
                .opacity(formBusy ? 0.7 : 1)
                .padding(.top, 4)

                if mode == .signUp {
                    LegalConsentText(action: "creating an account")
                        .padding(.top, 2)
                }

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
        guard !formBusy, !email.isEmpty, !password.isEmpty else { return false }
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

    private func authDivider(label: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(GinRummyPalette.sage.opacity(0.35))
                .frame(height: 1)
            Text(label)
                .font(.caption)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
            Rectangle()
                .fill(GinRummyPalette.sage.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

/// Request a password-reset email. Supabase sends the link; we don't reveal whether the address exists.
struct ForgotPasswordView: View {
    @EnvironmentObject private var app: AppModel
    @State private var email = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GinRummyLogoBlock(subtitle: "Reset your password")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                Text("Enter the email for your account. We'll send a link to choose a new password.")
                    .font(.subheadline)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Email")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                TextField("", text: $email)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { Task { await sendResetLink() } }
                    .ginOutlinedField()

                Button(busy ? "Sending…" : "Send reset link") {
                    Task { await sendResetLink() }
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .navigationTitle("Forgot password")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func sendResetLink() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        busy = true
        message = ""
        messageIsError = true
        defer { busy = false }
        do {
            try await app.api.requestPasswordReset(email: trimmed)
            message = "If an account exists for that email, we sent a reset link. Check your inbox and spam folder."
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}

/// Shown after the user opens the reset link from email; sets a new password and signs them in.
struct ResetPasswordView: View {
    let presentation: PasswordResetPresentation

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true
    @FocusState private var focused: Field?
    private enum Field { case password, confirm }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GinRummyLogoBlock(subtitle: "Choose a new password")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    Text("Use at least 6 characters.")
                        .font(.subheadline)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))

                    Text("New password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focused = .confirm }
                        .ginOutlinedField()

                    Text("Confirm password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                    SecureField("", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .ginOutlinedField()

                    Button(busy ? "Saving…" : "Update password") {
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
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        app.dismissPasswordReset()
                        dismiss()
                    }
                }
            }
            .onAppear { focused = .password }
        }
        .ginFeltChrome()
    }

    private var canSubmit: Bool {
        !busy && password.count >= 6 && password == confirmPassword
    }

    private func submit() async {
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
            try await app.api.updatePassword(newPassword: password, accessToken: presentation.accessToken)
            let session = AuthTokenResponse(
                access_token: presentation.accessToken,
                refresh_token: presentation.refreshToken,
                expires_in: presentation.expiresIn,
                token_type: "bearer",
                user: nil
            )
            app.finishPasswordReset(adopting: session)
            message = "Password updated. You're signed in."
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}
