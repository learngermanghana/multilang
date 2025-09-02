import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var profile: Profile?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if loading { ProgressView() }

                if let p = profile {
                    VStack {
                        Text("Welcome, \(p.name ?? p.email)").font(.title2)
                        Text("ID: \(p.id)").foregroundStyle(.secondary)
                    }
                } else {
                    Text("Logged in ✅").font(.title2)
                }

                Button("Load Profile") { Task { await loadProfile() } }
                    .buttonStyle(.bordered)

                Button("Log out") { auth.logout() }
                    .buttonStyle(.borderedProminent)

                if let e = error {
                    Text(e).foregroundStyle(.red).font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .navigationTitle("Falowen")
        }
        .task { await loadProfile() } // auto-load on entry if you want
    }

    private func loadProfile() async {
        loading = true; defer { loading = false }
        do {
            // Adjust path to your API (e.g., "/me" or "/api/me")
            profile = try await AuthedClient.shared.getJSON("/me")
            error = nil
        } catch {
            error = error.localizedDescription
            if (error as? APIClientError) == .unauthorized { auth.logout() }
        }
    }
}
