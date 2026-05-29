import SwiftUI

struct RootView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        switch auth.state {
        case .loading:
            ProgressView()
        case .signedOut:
            SignInView()
        case .signedIn(let userID):
            TodoListView(userID: userID)
        }
    }
}
