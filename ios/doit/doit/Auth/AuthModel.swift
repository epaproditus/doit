import AuthenticationServices
import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthModel {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(userID: UUID)
    }

    var state: State = .loading
    private var listenerTask: Task<Void, Never>?

    func bootstrap() {
        if listenerTask != nil { return }
        // Pick up any existing session immediately.
        Task {
            let session = try? await Supa.client.auth.session
            self.apply(session: session)
        }
        // Then listen for changes.
        listenerTask = Task { [weak self] in
            for await (_, session) in Supa.client.auth.authStateChanges {
                self?.apply(session: session)
            }
        }
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
        self.state = .signedOut
    }

    /// Exchange an Apple ID credential's identity token for a Supabase session.
    func completeSignInWithApple(_ credential: ASAuthorizationAppleIDCredential) async throws {
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthError.missingIdentityToken
        }
        _ = try await Supa.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: token)
        )
    }

    private func apply(session: Session?) {
        if let s = session {
            self.state = .signedIn(userID: s.user.id)
        } else {
            self.state = .signedOut
        }
    }
}

enum AuthError: Error {
    case missingIdentityToken
}
