
import Foundation

// Set to false when you wire your real backend.
private let USE_STUB = true

enum AuthAPIError: LocalizedError {
    case http(Int), badResponse, decodeError
    var errorDescription: String? {
        switch self {
        case .http(let code): return "Server error (\(code))"
        case .badResponse:    return "Invalid server response"
        case .decodeError:    return "Couldn’t decode server response"
        }
    }
}

// Response model that can decode snake_case or camelCase
private struct LoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresIn
        case access_token, refresh_token, expires_in
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let access = try c.decodeIfPresent(String.self, forKey: .accessToken) ??
                         c.decodeIfPresent(String.self, forKey: .access_token),
            let refresh = try c.decodeIfPresent(String.self, forKey: .refreshToken) ??
                          c.decodeIfPresent(String.self, forKey: .refresh_token),
            let expires = try c.decodeIfPresent(Int.self, forKey: .expiresIn) ??
                          c.decodeIfPresent(Int.self, forKey: .expires_in)
        else { throw AuthAPIError.decodeError }
        accessToken = access
        refreshToken = refresh
        expiresIn = expires
    }
}

enum AuthAPI {
    // Uses the resolver’s discovered base URL
    static var base: URL { get async { await ServerResolver.shared.baseURL } }

    static func login(email: String, password: String) async throws -> TokenPair {
        if USE_STUB {
            try await Task.sleep(nanoseconds: 300_000_000)
            return TokenPair(
                accessToken: "access_" + UUID().uuidString,
                refreshToken: "refresh_" + UUID().uuidString,
                expiry: Date().addingTimeInterval(60 * 60)
            )
        } else {
            return try await liveLogin(email: email, password: password)
        }
    }

    static func refresh(using refreshToken: String) async throws -> TokenPair {
        if USE_STUB {
            try await Task.sleep(nanoseconds: 200_000_000)
            return TokenPair(
                accessToken: "access_" + UUID().uuidString,
                refreshToken: refreshToken,
                expiry: Date().addingTimeInterval(60 * 60)
            )
        } else {
            return try await liveRefresh(using: refreshToken)
        }
    }

    // MARK: Live calls

    private static func liveLogin(email: String, password: String) async throws -> TokenPair {
        let baseURL = await base
        var req = URLRequest(url: baseURL.appendingPathComponent("/auth/login"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthAPIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw AuthAPIError.http(http.statusCode) }

        let lr = try JSONDecoder().decode(LoginResponse.self, from: data)
        return TokenPair(
            accessToken: lr.accessToken,
            refreshToken: lr.refreshToken,
            expiry: Date().addingTimeInterval(TimeInterval(lr.expiresIn))
        )
    }

    private static func liveRefresh(using refreshToken: String) async throws -> TokenPair {
        let baseURL = await base
        var req = URLRequest(url: baseURL.appendingPathComponent("/auth/refresh"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthAPIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw AuthAPIError.http(http.statusCode) }

        let lr = try JSONDecoder().decode(LoginResponse.self, from: data)
        return TokenPair(
            accessToken: lr.accessToken,
            refreshToken: lr.refreshToken,
            expiry: Date().addingTimeInterval(TimeInterval(lr.expiresIn))
        )
    }
}
