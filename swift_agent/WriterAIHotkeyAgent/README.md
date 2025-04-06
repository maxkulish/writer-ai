**Analysis of Current Project Status and Structure**

1.  **Purpose:** The project is a macOS agent (`LSUIElement = true`) designed to run in the background, listen for a global hotkey (defined in `Info.plist`, currently `Ctrl+Shift+E`), capture selected text (via simulated Cmd+C), send it to a local Rust backend service (`http://127.0.0.1:8989/process`), receive a processed response, and paste it back (via simulated Cmd+V).
2.  **Core Logic:** Resides almost entirely within `AppDelegate.swift`.
3.  **UI:** It's primarily a background agent with a status bar icon ("W") and menu. There's no main window (`ContentView` is unused).
4.  **Hotkey Handling:** Uses `NSEvent.addGlobalMonitorForEvents` to detect `keyDown` events globally. Checks for the specific key code and modifier flags.
5.  **Text Interaction:** Relies heavily on simulating Cmd+C (copy) and Cmd+V (paste) using `CGEvent`s, with AppleScript as a fallback. This requires Accessibility permissions.
6.  **Backend Communication:** Uses `URLSession` to POST JSON data (`{"text": "..."}`) to the Rust service and expects a JSON response (`{"response": "..."}`). Handles basic network errors and timeouts.
7.  **Permissions:**
    *   **Accessibility:** Crucial for hotkey detection and clipboard simulation. The app prompts the user if access is missing and includes menu items to open settings.
    *   **Automation:** Likely needed for AppleScript fallbacks and potentially for `CGEvent`s to function correctly across different apps. The app includes checks and prompts related to this.
    *   **Network:** `NSAllowsLocalNetworking` and `NSExceptionDomains` are configured in `Info.plist` for HTTP communication with `127.0.0.1`. The `com.apple.security.network.client` entitlement is present.
    *   **Sandbox:** Disabled (`com.apple.security.app-sandbox = false` in entitlements). This simplifies direct system interaction (like `CGEvent` posting) but has security implications.
8.  **Configuration:** Hotkey combination is configurable via `Info.plist`.
9.  **Status Menu:** Provides status info, hotkey display, permission checks/openers, testing functions (hotkey, connection), launch at login toggle, and quit.
10. **Restart Logic:** Exists in `restartApp(_:)` but is only triggered via a conditional `NSAlert` that appears specifically when Accessibility permission *seems* granted (`AXIsProcessTrusted` is true) but system control tests (like basic AppleScript) fail.
