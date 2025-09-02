
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

    // Restore session at launch
    func bootstrap() async {
        do {
            if let pair: TokenPair = try Keychain.shared.readCodable(TokenPair.self, account: accountKey) {
                if pair.expiry > Date().addingTimeInterval(60) {
                    isAuthenticated = true
                } else {
                    // try refresh
                    let newPair = try await AuthAPI.refresh(using: pair.refreshToken)
                    try Keychain.shared.saveCodable(newPair, account: accountKey)
                    isAuthenticated = true
                }
            } else {
                isAuthenticated = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
    }

    // Sign in (uses stub or live based on AuthAPI)
    func login(email: String, password: String) async {
        do {
            let pair = try await AuthAPI.login(email: email, password: password)
            try Keychain.shared.saveCodable(pair, account: accountKey)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
    }

    // Sign out
    func logout() {
        do { try Keychain.shared.delete(account: accountKey) }
        catch { errorMessage = error.localizedDescription }
        isAuthenticated = false
    }

    // Attach Bearer to requests (optional helper)
    func authorizedRequest(url: URL) throws -> URLRequest {
        guard let pair: TokenPair = try Keychain.shared.readCodable(TokenPair.self, account: accountKey)
        else { throw URLError(.userAuthenticationRequired) }
        var req = URLRequest(url: url)
        req.addValue("Bearer \(pair.accessToken)", forHTTPHeaderField: "Authorization")
        return req
    }
}
