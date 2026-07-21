import SwiftUI

struct RootView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(AppSetupModeStore.self) private var setupMode
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(ConversationStore.self) private var conversationStore

    @State private var selectedTab = 0

    var body: some View {
        if let mode = setupMode.mode {
            switch mode {
            case .hosted:
                authRoutedView
            case .byoConnector:
                if AppConfig.byoConnectorEnabled {
                    if setupMode.isHoldingForBYOPairing {
                        SetupModeView()
                    } else {
                        switch auth.state {
                        case .loading:
                            loadingView
                        case .signedOut:
                            SetupModeView()
                        case .signedIn(let userID):
                            if onboarding.isReady {
                                mainTabView(userID: userID)
                            } else {
                                OnboardingView()
                            }
                        }
                    }
                } else {
                    SetupModeView()
                }
            case .selfHost:
                SelfHostInfoView()
            }
        } else {
            SetupModeView()
        }
    }

    @ViewBuilder
    private var authRoutedView: some View {
        switch auth.state {
        case .loading:
            loadingView
        case .signedOut:
            SignInView()
        case .signedIn(let userID):
            if onboarding.isReady {
                mainTabView(userID: userID)
            } else {
                OnboardingView()
            }
        }
    }

    @ViewBuilder
    private func mainTabView(userID: UUID) -> some View {
        TabView(selection: $selectedTab) {
            ChatListView(userID: userID)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .tag(0)

            TodoListView(userID: userID)
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(1)
        }
        .tint(AppSemanticColors.accentColor)
        .task {
            conversationStore.start(userID: userID)
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppSemanticColors.screenBackground.ignoresSafeArea())
    }
}
