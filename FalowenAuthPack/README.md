# Falowen Auth Pack (SwiftUI + Keychain + Auto-Refresh)
Drop these files into your Xcode project (same target). They provide:
- Persistent login via Keychain
- Protected-data wait at boot (prevents false "no token" after reboot)
- Hardened `AuthAPI` decoding for `expires_in` as Int/String/Double
- Central `TokenStore` (single-flight refresh)
- `AuthedClient` that attaches Bearer and retries once on 401 via refresh
- Simple `LoginView` / `ContentView` with example profile fetch

## Files
- AuthAPI.swift
- AuthViewModel.swift
- Keychain.swift
- ProtectedData.swift
- TokenStore.swift
- AuthedClient.swift
- ContentView.swift
- LoginView.swift
- RootView.swift
- FalowenApp.swift
- Profile.swift

## Setup
1) Add all files to your target.
2) Open **AuthAPI.swift** and set:
   - `BASE` to your API host (e.g., `https://api.falowen.app`)
   - `PATH_LOGIN` / `PATH_REFRESH` to match your server
   - `REFRESH_STYLE` to `.snake` or `.camel` for the refresh body parameter name
   - Optionally set `USE_STUB = true` to test Keychain persistence without backend

3) If your dev API is **HTTP**, add ATS exceptions to Info.plist or use HTTPS.

4) Make sure your project uses iOS 15+ (or adjust where needed).

## Test Plan
- Build & run → log in
- Force-quit (swipe up), relaunch → you should still be authenticated
- Reboot simulator/device, unlock once, open app → still authenticated
- Let token expire, reopen → should auto-refresh and keep you in

## Notes
- Do not call `bootstrap()` in two places. This pack only calls it from `RootView`.
- Keychain `service` uses your bundle identifier; keep the same bundle when testing.
- Uninstalling the app clears saved tokens (expected). Force-quit and relaunch is fine.
