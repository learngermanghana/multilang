
import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        Group {
            if auth.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
    }
}
