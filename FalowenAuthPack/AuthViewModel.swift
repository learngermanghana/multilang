import Foundation
import SwiftUI

// What we keep in Keychain
struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String
    let expiry: Date
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var errorMessage: String?

    private let accountKey = "falowen.tokenpair"
    private var bootstrapping = false   // prevent overlapping bootstraps

    // Restore session at launch / foreground
    func bootstrap() async {
        // Ensure Keychain is readable (esp. right after device reboot)
        await ProtectedData.waitIfNeeded()

        // Avoid concurrent runs from .task and .onChange
        if bootstrapping { return }
        bootstrapping = true
        defer { bootstrapping = false }

        do {
            if let pair: TokenPair = try Keychain.shared.readCodable(TokenPair.self, account: accountKey) {
                #if DEBUG
                print("🔐 Keychain token found. Expiry:", pair.expiry)
                #endif

                // If token valid for >60s, accept; otherwise refresh once.
                if pair.expiry > Date().addingTimeInterval(60) {
                    isAuthenticated = true
                    errorMessage = nil
                } else {
                    let newPair = try await AuthAPI.refresh(using: pair.refreshToken)
                    try Keychain.shared.saveCodable(newPair, account: accountKey)
                    isAuthenticated = true
                    errorMessage = nil
                    #if DEBUG
                    print("♻️ Refreshed token. New expiry:", newPair.expiry)
                    #endif
                }
            } else {
                #if DEBUG
                print("ℹ️ No TokenPair in Keychain; showing login")
                #endif
                isAuthenticated = false
                // Keep errorMessage nil here—this isn’t an error state
                errorMessage = nil
            }
        } catch {
            // If decode or other errors occur, clear and show login
            #if DEBUG
            print("‼️ Bootstrap error:", error.localizedDescription)
            #endif
            try? Keychain.shared.delete(account: accountKey)
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    // Sign in (uses stub or live based on AuthAPI)
    func login(email: String, password: String) async {
        do {
            let pair = try await AuthAPI.login(email: email, password: password)
            try Keychain.shared.saveCodable(pair, account: accountKey)

            // 🔎 round-trip check (optional; comment out in prod)
            if let rt: TokenPair = try Keychain.shared.readCodable(TokenPair.self, account: accountKey) {
                print("🔎 Keychain round-trip OK. Expiry:", rt.expiry)
            } else {
                print("🔎 Keychain round-trip FAILED")
            }

            isAuthenticated = true
            errorMessage = nil
            #if DEBUG
            print("✅ Login saved. Expiry:", pair.expiry)
            #endif
        } catch {
            isAuthenticated = false
            errorMessage = error.localizedDescription
            #if DEBUG
            print("❌ Login failed:", error.localizedDescription)
            #endif
        }
    }

    // Sign out
    func logout() {
        do {
            try Keychain.shared.delete(account: accountKey)
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("⚠️ Logout keychain error:", error.localizedDescription)
            #endif
        }
        isAuthenticated = false
    }

    // Attach Bearer to requests (optional helper)
    func authorizedRequest(url: URL) throws -> URLRequest {
        guard let pair: TokenPair = try Keychain.shared.readCodable(TokenPair.self, account: accountKey)
        else { throw URLError(.userAuthenticationRequired) }
        var req = URLRequest(url: url)
        req.addValue("Bearer \(pair.accessToken)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }
}
