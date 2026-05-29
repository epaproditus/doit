import SwiftUI

@main
struct doitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var auth = AuthModel()
    @State private var push = PushManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(push)
                .task {
                    appDelegate.pushManager = push
                    auth.bootstrap()
                }
                .onChange(of: auth.state) { _, newValue in
                    if case .signedIn(let userID) = newValue {
                        push.register(userID: userID)
                    }
                }
        }
    }
}
