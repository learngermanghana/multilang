
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Logged in ✅").font(.title2)
                Button("Log out") { auth.logout() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Falowen")
        }
    }
}
