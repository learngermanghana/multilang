import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        .task { await auth.bootstrap() }                                     // first launch
        .onChange(of: scenePhase, initial: false) { _, newPhase in           // iOS 17+
            if newPhase == .active {
                Task { await auth.bootstrap() }                               // app foreground → recheck/refresh
            }
        }
    }
}
