import AuthenticationServices
import SwiftUI

/// Branded Sign in with Apple control for auth screens. Exchanges the Apple
/// identity token with Supabase and adopts the session via `AppModel`.
struct GinAppleSignInButton: View {
    @EnvironmentObject private var app: AppModel
    @Binding var busy: Bool
    var onError: (String) -> Void
    var onClearError: () -> Void = {}

    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            onClearError()
            let nonce = AppleSignInNonce.random()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256(nonce)
        } onCompletion: { result in
            Task { await handleCompletion(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .disabled(busy)
        .opacity(busy ? 0.65 : 1)
    }

    @MainActor
    private func handleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            currentNonce = nil
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            onError(UserFeedback.from(error))
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                currentNonce = nil
                onError("Sign in with Apple didn’t return a valid credential. Try again.")
                return
            }
            guard let nonce = currentNonce else {
                onError("Sign in with Apple expired — tap the button and try again.")
                return
            }
            currentNonce = nil
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                onError("Sign in with Apple didn’t return an identity token. Try again.")
                return
            }

            busy = true
            defer { busy = false }
            do {
                let resp = try await app.api.signInWithApple(identityToken: identityToken, nonce: nonce)
                app.adoptSession(resp)
                onClearError()
            } catch {
                onError(UserFeedback.from(error))
            }
        }
    }
}
