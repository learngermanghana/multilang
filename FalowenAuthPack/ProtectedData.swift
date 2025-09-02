import UIKit

enum ProtectedData {
    /// Suspends until protected data becomes available (e.g., after first unlock).
    /// Uses polling for broad compatibility across deployment targets/toolchains.
    static func waitIfNeeded() async {
        if UIApplication.shared.isProtectedDataAvailable { return }
        while !UIApplication.shared.isProtectedDataAvailable {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
    }
}
