//
//  AppDelegate.swift
//  WriterAIHotkeyAgent
//
//  Created by Max Kul on 31/03/2025.
//

import AppKit
import Foundation
import UserNotifications
import ServiceManagement
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var monitor = [Any]()
    private var statusItem: NSStatusItem?
    // Read port from Rust config or use default. Best to match default.
    // Using explicit IP address instead of localhost to avoid DNS resolution issues in sandbox
    private let rustServiceUrl: URL = {
        guard let url = URL(string: "http://127.0.0.1:8989/process") else {
            // This should never fail for a hardcoded, valid URL, but we'll handle it gracefully
            fatalError("Failed to create URL for Rust service: Invalid URL format")
        }
        return url
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up logging
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.writer-ai.WriterAIHotkeyAgent", category: "startup")
        logger.info("WriterAI Hotkey Agent started.")
        
        // Disable debug settings
        UserDefaults.standard.removeObject(forKey: "UseAppleScriptForPaste")
        UserDefaults.standard.removeObject(forKey: "UseTestMode")
        UserDefaults.standard.removeObject(forKey: "ProvideTestContentOnFailure")
        
        // Handle agent mode by relaunching if needed
        setupAgentMode()
        
        // Make sure app is completely hidden from Dock and app switcher
        // Use a safer approach to setting activation policy
        DispatchQueue.main.async {
            // Set activation policy to completely hide from Dock and Cmd+Tab
            NSApplication.shared.setActivationPolicy(.prohibited)
            ProcessInfo.processInfo.automaticTerminationSupportEnabled = true
        }
        
        // Check if we were recently restarted - if so, skip immediate accessibility check
        let restartFlag = UserDefaults.standard.bool(forKey: "WasRecentlyRestarted")
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error)")
            }
        }
        
        if restartFlag {
            // Clear the flag for next time
            UserDefaults.standard.removeObject(forKey: "WasRecentlyRestarted")
            print("App was recently restarted - skipping immediate accessibility check")
            
            // Just print the current status without prompting or showing alerts
            let accessEnabled = AXIsProcessTrusted()
            print("Current accessibility permissions status: \(accessEnabled ? "Enabled" : "Disabled")")
        } else {
            // Normal first run - prompt for permissions if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // This will cause the system to prompt for accessibility permissions
                let checkOpt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
                let accessEnabled = AXIsProcessTrustedWithOptions([checkOpt: true] as CFDictionary)
                
                if accessEnabled {
                    print("Accessibility access granted.")
                } else {
                    print("WARNING: Accessibility access is required for hotkey and paste functionality.")
                    print("Please grant access in System Settings > Privacy & Security > Accessibility.")
                    
                    // Create a system alert to make it more visible
                    let alert = NSAlert()
                    alert.messageText = "Accessibility Permission Required"
                    alert.informativeText = "This app needs accessibility permissions to detect hotkeys and manipulate text.\n\nPlease go to System Settings > Privacy & Security > Accessibility and add this app to the list."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open Accessibility Settings")
                    alert.addButton(withTitle: "Later")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        // Open the accessibility settings
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        
        // Try to set up the hotkey monitor anyway, it will start working once permissions are granted
        setupHotkeyMonitor()
        
        // Create a status bar menu item for the app
        createStatusItem()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        for monitor in monitor {
            NSEvent.removeMonitor(monitor)
        }
        print("All event monitors removed.")
    }
    
    private func setupHotkeyMonitor() {
    // Read hotkey configuration from Info.plist
    let hotkeyConfig = readHotkeyConfiguration()
    let keyName = hotkeyConfig.keyName
    let modifierNames = hotkeyConfig.modifierFlagNames.joined(separator: "+")
    
    print("Setting up simplified global hotkey monitor for \(modifierNames)+\(keyName)...")

    // Remove any previously added monitors if this function were called again
    for oldMonitor in monitor {
        NSEvent.removeMonitor(oldMonitor)
    }
    monitor.removeAll()

    let requiredFlags = hotkeyConfig.modifierFlags
    let keyCode = hotkeyConfig.keyCode

    let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        // Use intersection to ensure ONLY the required flags (and potentially Caps Lock) are present.
        // Or use contains() if you want to allow other modifiers like Fn. Test which works best for you.
        // Let's start with contains() as it's more forgiving.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask) // Isolate relevant flags

        // Only print key presses with modifiers for basic monitoring
        if event.keyCode == keyCode && requiredFlags.contains(where: { flag in flags.contains(flag) }) {
            print("\(keyName) Key Pressed with modifiers - \(hotkeyConfig.modifierFlags.map { "\($0): \(flags.contains($0))" }.joined(separator: ", "))")
        }

        if event.keyCode == keyCode && requiredFlags.allSatisfy({ flags.contains($0) }) {
             // Optional: Check if ONLY required flags are pressed ( stricter )
             // if event.keyCode == keyCode && flags == requiredFlags {
             print("✅ GLOBAL HOTKEY DETECTED: \(modifierNames)+\(keyName)")
             self?.handleHotkey()
         }
    }

    if let globalMonitor = globalMonitor {
        monitor.append(globalMonitor)
        print("Successfully added global key down monitor.")
    } else {
        print("🚨 ERROR: Failed to add global key down monitor. Accessibility permissions likely missing or inactive.")
        // Consider showing an alert here or updating the status menu immediately
        DispatchQueue.main.async {
             self.showErrorNotification(title: "Hotkey Monitor Failed", message: "Could not set up the global hotkey. Please ensure Accessibility permissions are granted in System Settings and restart the app if necessary.")
             self.updateAccessibilityStatus() // Update menu item status
        }
    }
}
    
    // This function has been intentionally removed as part of the simplification process
    // The functionality is now handled by the simplified setupHotkeyMonitor() function
    
    // MARK: - Agent Mode & Process Management
    
    private func setupAgentMode() {
        // Check if we're already running in agent mode
        // If Info.plist is configured correctly with LSUIElement, this should always be true
        let isAgent = ProcessInfo.processInfo.environment["LSUIElement"] == "1" || 
                      UserDefaults.standard.bool(forKey: "ForceAgentMode")
        
        if isAgent {
            print("Running in agent mode")
        } else {
            print("Note: App was launched without agent flag. Using native app mode.")
            // We'll set activation policy in applicationDidFinishLaunching instead of relaunching
            UserDefaults.standard.set(true, forKey: "ForceAgentMode")
        }
    }
    
    // MARK: - Login Item Management
    
    @objc private func toggleLoginItemSetting(_ sender: NSMenuItem) {
        let isLoginItemEnabled = sender.state == .on
        
        // Toggle the state
        if isLoginItemEnabled {
            // Currently enabled, so disable it
            disableLoginItem()
            sender.state = .off
        } else {
            // Currently disabled, so enable it
            enableLoginItem()
            sender.state = .on
        }
    }
    
    private func enableLoginItem() {
        if #available(macOS 13.0, *) {
            // Modern method using SMAppService
            do {
                let loginItem = SMAppService.loginItem(identifier: Bundle.main.bundleIdentifier!)
                if loginItem.status == .enabled {
                    print("Login item is already enabled")
                } else {
                    try loginItem.register()
                    print("Successfully registered login item")
                }
            } catch {
                print("Failed to register login item: \(error)")
                showErrorNotification(title: "Autostart Setup Failed", message: "Could not enable automatic startup: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions - use AppleScript
            let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(Bundle.main.bundlePath)", hidden:true}
            end tell
            """
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            
            if let error = error {
                print("Failed to enable login item: \(error)")
                showErrorNotification(title: "Autostart Setup Failed", message: "Could not enable automatic startup")
            } else {
                print("Successfully enabled login item using AppleScript")
            }
        }
    }
    
    private func disableLoginItem() {
        if #available(macOS 13.0, *) {
            // Modern method using SMAppService
            do {
                let loginItem = SMAppService.loginItem(identifier: Bundle.main.bundleIdentifier!)
                try loginItem.unregister()
                print("Successfully unregistered login item")
            } catch {
                print("Failed to unregister login item: \(error)")
                showErrorNotification(title: "Autostart Removal Failed", message: "Could not disable automatic startup: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions - use AppleScript
            let script = """
            tell application "System Events"
                delete (every login item whose path contains "\(Bundle.main.bundlePath)")
            end tell
            """
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            
            if let error = error {
                print("Failed to disable login item: \(error)")
                showErrorNotification(title: "Autostart Removal Failed", message: "Could not disable automatic startup")
            } else {
                print("Successfully disabled login item using AppleScript")
            }
        }
    }
    
    private func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            // Modern method using SMAppService
            let loginItem = SMAppService.loginItem(identifier: Bundle.main.bundleIdentifier!)
            return loginItem.status == .enabled
        } else {
            // For older macOS versions, we can check via AppleScript
            let script = """
            tell application "System Events"
                return exists (every login item whose path contains "\(Bundle.main.bundlePath)")
            end tell
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            return result?.booleanValue ?? false
        }
    }
    
    // MARK: - Status Menu
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Set the status item to show "W" as text with custom styling
        if let button = statusItem?.button {
            // Use a text-based icon (capital W for Writer)
            button.title = "W"
            
            // Apply custom font and styling
            button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            
            // Set accessibility description for the button
            button.setAccessibilityLabel("WriterAI")
        }
        
        // Create the menu
        let menu = NSMenu()
        
        // Add a status item
        let statusMenuItem = NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        // Add a hotkey info item
        let hotkeyConfig = readHotkeyConfiguration()
        let hotkeyInfoItem = NSMenuItem(title: "Hotkey: \(hotkeyConfig.displayName)", action: nil, keyEquivalent: "")
        hotkeyInfoItem.isEnabled = false
        menu.addItem(hotkeyInfoItem)
        
        // Add an item to check accessibility permissions
        let checkPermissionItem = NSMenuItem(title: "Check Accessibility Permissions", action: #selector(checkAccessibilityPermissions(_:)), keyEquivalent: "c")
        checkPermissionItem.target = self
        menu.addItem(checkPermissionItem)
        
        // Add an item to open accessibility settings
        let openSettingsItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings(_:)), keyEquivalent: "o")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)
        
        // Add an item to open automation settings
        let openAutomationItem = NSMenuItem(title: "Open Automation Settings", action: #selector(openAutomationSettings(_:)), keyEquivalent: "a")
        openAutomationItem.target = self
        menu.addItem(openAutomationItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add a hotkey test item
        let testHotkeyItem = NSMenuItem(title: "Test Hotkey Processing", action: #selector(testHotkey(_:)), keyEquivalent: "t")
        testHotkeyItem.target = self
        menu.addItem(testHotkeyItem)
        
        // Add a test connection item
        let testConnectionItem = NSMenuItem(title: "Test Rust Service Connection", action: #selector(testRustConnection(_:)), keyEquivalent: "r")
        testConnectionItem.target = self
        menu.addItem(testConnectionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add a login item toggle
        let loginItemEnabled = isLoginItemEnabled()
        let loginItemToggle = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItemSetting(_:)), keyEquivalent: "l")
        loginItemToggle.target = self
        loginItemToggle.state = loginItemEnabled ? .on : .off
        menu.addItem(loginItemToggle)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add a quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        // Set the menu
        statusItem?.menu = menu
        
        // Update the status immediately
        updateAccessibilityStatus()
    }
    
    @objc private func checkAccessibilityPermissions(_ sender: Any?) {
        updateAccessibilityStatus()
    }
    
    @objc private func openAccessibilitySettings(_ sender: Any?) {
        // Try to open the security preferences directly to the accessibility pane
        if let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            if NSWorkspace.shared.open(accessibilityURL) {
                print("Opened System Settings > Privacy & Security > Accessibility")
            } else {
                // Fallback to opening Security & Privacy in general
                if let securityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(securityURL)
                    print("Opened System Settings > Privacy & Security")
                } else {
                    print("Failed to open System Settings")
                }
            }
        } else {
            print("Failed to create preferences URL")
        }
    }
    
    @objc private func openAutomationSettings(_ sender: Any?) {
        // Try to open the security preferences directly to the automation pane
        if let automationURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            if NSWorkspace.shared.open(automationURL) {
                print("Opened System Settings > Privacy & Security > Automation")
            } else {
                // Fallback to opening Security & Privacy in general
                if let securityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(securityURL)
                    print("Opened System Settings > Privacy & Security")
                } else {
                    print("Failed to open System Settings")
                }
            }
        } else {
            print("Failed to create preferences URL")
        }
    }
    
    @objc private func testHotkey(_ sender: Any?) {
        print("Manual test of hotkey processing triggered")
        
        // Start timing for the test
        let testStartTime = Date()
        
        // Use the input dialog for test mode since we're being explicit about testing
        self.showManualTextEntryDialog(completion: { text in
            if let text = text, !text.isEmpty {
                // Get time for dialog input completion
                let inputDuration = Date().timeIntervalSince(testStartTime)
                
                // Process the manually entered text with timing information
                self.processTextWithFallbacks(text, originalTypes: nil, originalContent: nil, 
                                             timing: (start: testStartTime, copy: inputDuration))
            }
        })
    }
    
    @objc private func testRustConnection(_ sender: Any?) {
        print("Testing connection to Rust service...")
        
        // Show a dialog to get test text input
        self.showManualTextEntryDialog(completion: { text in
            guard let text = text, !text.isEmpty else { return }
            
            print("Testing connection with text: \(text)")
            
            // Create a dedicated session with custom configuration
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 30.0  // 30 seconds timeout
            sessionConfig.waitsForConnectivity = true      // Wait for connectivity if not available
            // Session is used implicitly by sendToRustService
            
            // Send text directly to service to test connection
            self.sendToRustService(text: text) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let response):
                        print("✅ Connection test successful!")
                        
                        // Show success with response preview
                        let alert = NSAlert()
                        alert.messageText = "Connection Successful"
                        alert.informativeText = "Successfully connected to Rust service.\n\nResponse: \(response.prefix(300))\(response.count > 300 ? "..." : "")"
                        alert.alertStyle = .informational
                        alert.runModal()
                        
                    case .failure(let error):
                        print("❌ Connection test failed: \(error.localizedDescription)")
                        
                        // Show error notification
                        self.showErrorNotification(title: "Connection Failed", 
                                                  message: "Could not connect to Rust service: \(error.localizedDescription)")
                        
                        // Show alert with helpful info
                        let alert = NSAlert()
                        alert.messageText = "Connection to Rust Service Failed"
                        alert.informativeText = "Could not connect to the Rust service at \(self.rustServiceUrl).\n\nError: \(error.localizedDescription)\n\nPlease ensure the Rust service is running on port 8989."
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        })
    }
    
    // Removed testDirectTextProcessing() since it's now handled by the testRustConnection method
    
    // This function has been intentionally removed as part of the simplification process
    // The functionality is now handled directly by the sendToRustService function
    
    // Removed handleRequestResult since it's now handled directly in the appropriate methods
    
    private func showSuccessNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering notification: \(error)")
            }
        }
    }
    
    private func updateAccessibilityStatus() {
        // Use a different API call to check permissions 
        // First try direct method
        let accessEnabled = AXIsProcessTrusted()
        print("DEBUG: AXIsProcessTrusted() returned: \(accessEnabled)")
        
        // Check current macOS version for additional context
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        print("DEBUG: macOS version: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        
        // Check if we're a hardened runtime
        let hardenedRuntime = Bundle.main.infoDictionary?["com.apple.security.get-task-allow"] != nil
        print("DEBUG: App using hardened runtime: \(hardenedRuntime)")
        
        // Try a simple AppleScript to test if we can actually control the system
        var canControlSystem = false
        
        // Try several different AppleScript tests to pinpoint the issue
        let testScripts = [
            "Basic test": "tell application \"System Events\" to return name of first process",
            "Clipboard test": "set the clipboard to \"test\"",
            "Key press test": "tell application \"System Events\" to keystroke \"a\"",
        ]
        
        for (testName, scriptSource) in testScripts {
            print("DEBUG: Running AppleScript test: \(testName)")
            let appleScript = NSAppleScript(source: scriptSource)
            var error: NSDictionary?
            if let scriptResult = appleScript?.executeAndReturnError(&error) {
                print("DEBUG: AppleScript \(testName) succeeded with result: \(scriptResult.stringValue ?? "no value")")
                // If any test passes, we have some level of control
                canControlSystem = true
            } else if let err = error {
                print("DEBUG: AppleScript \(testName) failed: \(err)")
                if let errMsg = err[NSAppleScript.errorMessage] as? String {
                    print("DEBUG: AppleScript \(testName) error message: \(errMsg)")
                }
            }
        }
        
        // Try direct TCC database check (won't work in sandboxed apps)
        print("DEBUG: Checking app bundle identifier: \(Bundle.main.bundleIdentifier ?? "unknown")")
        
        // Update the status menu item
        if let menu = statusItem?.menu, let statusItem = menu.item(at: 0) {
            if canControlSystem {
                statusItem.title = "Status: Accessibility Working ✅"
            } else if accessEnabled {
                statusItem.title = "Status: Permission Granted (Restart Required) ⚠️"
            } else {
                statusItem.title = "Status: Accessibility Disabled ❌"
            }
        }
        
        // Also log to console with more context
        print("Accessibility permissions - API status: \(accessEnabled ? "Enabled" : "Disabled"), Can control system: \(canControlSystem ? "Yes" : "No")")
        
        // If accessibility is granted according to API but we can't control the system,
        // there might be additional permissions needed or a restart required
        if accessEnabled && !canControlSystem {
            // Check if Automation permissions are enabled
            let automationScript = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
            var automationError: NSDictionary?
            automationScript?.executeAndReturnError(&automationError)
            
            // Check if this is a permission issue or something else
            let isPermissionIssue = automationError?[NSAppleScript.errorNumber] as? Int == -1743
            
            print("⚠️ Permission appears to be granted but not effective. Try restarting the app.")
            print("DEBUG: Is this an automation permission issue? \(isPermissionIssue)")
            
            // Check if we were recently restarted
            let wasRecentlyRestarted = UserDefaults.standard.bool(forKey: "WasRecentlyRestarted")
            if wasRecentlyRestarted {
                // We already tried restarting, so that didn't help
                print("⚠️ App was already restarted but permissions still not effective.")
                print("⚠️ Try completely quitting the app, verifying permissions, and starting fresh.")
                
                // Only show this once
                UserDefaults.standard.removeObject(forKey: "WasRecentlyRestarted")
                
                // Show alert with more detailed troubleshooting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = "Permission Issues Persist"
                    alert.informativeText = "Try these steps:\n\n1. Quit this app completely\n2. Go to System Settings > Privacy & Security > Accessibility\n3. Remove this app from the list\n4. Add it back and ensure the checkbox is enabled\n5. IMPORTANT: Also check System Settings > Privacy & Security > Automation and add this app if not present\n6. Restart your Mac completely\n7. Start the app again"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open Accessibility Settings")
                    alert.addButton(withTitle: "Open Automation Settings")
                    alert.addButton(withTitle: "Quit App")
                    alert.addButton(withTitle: "Continue Anyway")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.openAccessibilitySettings(nil)
                    } else if response == .alertSecondButtonReturn {
                        // Open Automation settings
                        self.openAutomationSettings(nil)
                    } else if response == .alertThirdButtonReturn {
                        NSApp.terminate(nil)
                    }
                }
            } else {
                // First time noticing this issue - suggest restart and check Automation
                // Show restart recommendation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = "App Restart Recommended"
                    alert.informativeText = "Accessibility permission has been granted, but you also need to grant Automation permission.\n\n1. Open System Settings > Privacy & Security > Automation\n2. Find this app in the list and enable it for \"System Events\"\n3. Restart the app\n\nWould you like to open Automation settings now?"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Open Automation Settings")
                    alert.addButton(withTitle: "Restart App")
                    alert.addButton(withTitle: "Later")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        // Open Automation settings
                        self.openAutomationSettings(nil)
                    } else if response == .alertSecondButtonReturn {
                        self.restartApp(nil)
                    }
                }
            }
        }
    }
    
    @objc private func restartApp(_ sender: Any?) {
        // Get the path to the current executable
        guard let executablePath = Bundle.main.executablePath else {
            print("ERROR: Could not get executable path")
            return
        }
        
        // Set a flag to indicate this is a restart to avoid permission check loop
        UserDefaults.standard.set(true, forKey: "WasRecentlyRestarted")
        UserDefaults.standard.synchronize()
        
        // Launch a new instance first so we don't lose the app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        try? process.run()
        
        // Create a small delay to allow the new instance to start before terminating this one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Terminate the current process
            exit(0)
        }
    }
    
    // Track if we're already handling a hotkey to prevent double-triggers
    private var isHandlingHotkey = false
    
    private func handleHotkey() {
        // Prevent multiple simultaneous processing of the same hotkey event
        if isHandlingHotkey {
            print("⚠️ Already handling a hotkey event, ignoring this one")
            return
        }
        
        // Start timing for the entire operation
        let hotkeyStartTime = Date()
        
        // Get the current hotkey config for accurate logging
        let hotkeyConfig = readHotkeyConfiguration()
        print("🔥 HOTKEY HANDLER ACTIVATED: \(hotkeyConfig.modifierFlagNames.joined(separator: "+"))+\(hotkeyConfig.keyName) 🔥")
        
        // Set flag to prevent duplicate triggers
        isHandlingHotkey = true
        
        // Reset flag after a reasonable timeout even if processing fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.isHandlingHotkey = false
        }
        
        // Instead of relying on AppleScript, let's use our CGEvent approach directly
        // No need to check automation permissions for the direct approach
        print("⌨️ Hotkey triggered - processing selected text...")
        
        // Use normal workflow - copy selected text and process it
        print("Using production workflow - will copy selected text and process it")
        
        // 1. Get selected text via Copy simulation
        // Store the original types instead of trying to copy the items directly
        let originalPasteboard = NSPasteboard.general
        let originalTypes = originalPasteboard.types
        let originalContent = originalTypes?.compactMap { type in
            return originalPasteboard.string(forType: type)
        }
        
        // Start timing for the copy operation
        let copyStartTime = Date()
        
        // Use direct CGEvent approach for copy
        simulateCopy { success in
            let copyDuration = Date().timeIntervalSince(copyStartTime)
            print("TIMING: simulateCopy took \(copyDuration * 1000) ms")
            
            guard success else {
                self.showErrorNotification(title: "Copy Failed", message: "Could not simulate Cmd+C. Check Accessibility permissions.")
                self.restorePasteboard(originalTypes: originalTypes, originalContent: originalContent)
                self.isHandlingHotkey = false
                print("✅ Hotkey handler reset after copy failure - ready for next hotkey")
                return
            }
            
            // Reduced delay for clipboard to update reliably (from 0.25s to 0.15s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let selectedText = NSPasteboard.general.string(forType: .string), !selectedText.isEmpty else {
                    print("No text found on clipboard after copy attempt.")
                    self.restorePasteboard(originalTypes: originalTypes, originalContent: originalContent)
                    self.isHandlingHotkey = false
                    print("✅ Hotkey handler reset after no text found - ready for next hotkey")
                    return
                }
                
                print("Selected Text Length: \(selectedText.count)")
                
                // Start timing for text processing (including network request)
                let processStartTime = Date()
                
                // 2. Process text directly
                self.processTextWithFallbacks(selectedText, originalTypes: originalTypes, originalContent: originalContent, 
                                              timing: (start: hotkeyStartTime, copy: copyDuration))
            }
        }
    }
    
    private func processTextWithFallbacks(_ text: String, originalTypes: [NSPasteboard.PasteboardType]?, originalContent: [String]?, 
                              timing: (start: Date, copy: TimeInterval)? = nil) {
        print("Processing text directly using URLSession...")
        
        // Start timing for network request
        let networkStartTime = Date()
        
        // Send text to Rust service using direct method
        self.sendToRustService(text: text) { result in
            let networkDuration = Date().timeIntervalSince(networkStartTime)
            print("TIMING: Network request took \(networkDuration * 1000) ms")
            
            // Ensure UI updates (paste simulation, notifications) are on main thread
            DispatchQueue.main.async {
                switch result {
                case .success(let llmResponse):
                    print("Received LLM Response Length: \(llmResponse.count)")
                    print("DEBUG: About to paste: \"\(llmResponse)\"")
                    
                    // Start timing for paste operation
                    let pasteStartTime = Date()
                    
                    // Paste the response
                    self.simulatePaste(text: llmResponse) { pasteSuccess in
                        let pasteDuration = Date().timeIntervalSince(pasteStartTime)
                        print("TIMING: simulatePaste took \(pasteDuration * 1000) ms")
                        
                        if !pasteSuccess {
                            self.showErrorNotification(title: "Paste Failed", message: "Could not simulate Cmd+V. Response copied to clipboard. Check Accessibility.")
                            // Put response on clipboard as fallback
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(llmResponse, forType: .string)
                        } else {
                            print("Paste simulation successful.")
                        }
                        
                        // Report total operation time if we have the start time
                        if let timing = timing {
                            let totalDuration = Date().timeIntervalSince(timing.start)
                            print("TIMING SUMMARY:")
                            print("- Copy operation: \(timing.copy * 1000) ms")
                            print("- Network request: \(networkDuration * 1000) ms")
                            print("- Paste operation: \(pasteDuration * 1000) ms")
                            print("- Total operation: \(totalDuration * 1000) ms")
                        }
                        
                        // Reset the hotkey handling flag on both success and failure
                        self.isHandlingHotkey = false
                        print("✅ Hotkey handler reset - ready for next hotkey")
                    }
                    
                case .failure(let error):
                    // Log detailed error
                    print("Error processing text: \(error.localizedDescription)")
                    // Show user-friendly notification
                    let errorMessage = self.friendlyErrorMessage(for: error)
                    self.showErrorNotification(title: "Processing Error", message: errorMessage)
                    // Restore original clipboard on error
                    self.restorePasteboard(originalTypes: originalTypes, originalContent: originalContent)
                    
                    // Report timing even in case of failure
                    if let timing = timing {
                        let totalDuration = Date().timeIntervalSince(timing.start)
                        print("TIMING ERROR SUMMARY:")
                        print("- Copy operation: \(timing.copy * 1000) ms")
                        print("- Failed network request: \(networkDuration * 1000) ms")
                        print("- Total operation until error: \(totalDuration * 1000) ms")
                    }
                    
                    // Reset hotkey handling flag on error
                    self.isHandlingHotkey = false
                    print("✅ Hotkey handler reset after error - ready for next hotkey")
                }
            }
        }
    }
    
    // This function has been intentionally removed as part of the simplification process
    // The functionality is now handled directly in the processTextWithFallbacks function
    
    // MARK: - Clipboard & Simulation Helpers
    
    private func simulateCopy(completion: @escaping (Bool) -> Void) {
        print("Simulating Cmd+C...")
        
        // Clear pasteboard *before* copy to help ensure we get the new content
        NSPasteboard.general.clearContents()
        
        // Reduced delay before triggering copy
        let delayTime = DispatchTime.now() + 0.15 // Reduced from 0.25s to 0.15s
        DispatchQueue.main.asyncAfter(deadline: delayTime) {
            let source = CGEventSource(stateID: .combinedSessionState)
            
            // Create key down event for command key (modifiers)
            let cmdKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // 0x37 is Command key
            cmdKeyDown?.flags = .maskCommand
            cmdKeyDown?.post(tap: .cghidEventTap)
            
            // Create key down event for 'c' key
            let cKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 0x08 is 'c' key
            cKeyDown?.flags = .maskCommand
            cKeyDown?.post(tap: .cghidEventTap)
            
            // Create key up event for 'c' key
            let cKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            cKeyUp?.post(tap: .cghidEventTap)
            
            // Create key up event for command key
            let cmdKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            cmdKeyUp?.post(tap: .cghidEventTap)
            
            // Reduced delay for clipboard check
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // Reduced from 0.5s to 0.15s
                // DEBUG: Add the suggested debug print
                print("DEBUG: Clipboard content after copy simulation: \(NSPasteboard.general.string(forType: .string) ?? "nil")")
                
                let hasPasteboardContent = NSPasteboard.general.string(forType: .string) != nil
                if hasPasteboardContent {
                    completion(true)
                } else {
                    // If we're testing, provide fallback content
                    if UserDefaults.standard.bool(forKey: "ProvideTestContentOnFailure") {
                        print("Copy failed, but providing test content anyway due to defaults setting")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("Fallback test content for WriterAI", forType: .string)
                        completion(true)
                    } else {
                        // Check if we have automation permissions before falling back
                        let automationWorking = self.checkAutomationPermission()
                        if automationWorking {
                            // Fallback to AppleScript if CGEvent approach fails and we have permissions
                            print("CGEvent copy failed, falling back to AppleScript...")
                            self.runAppleScript(script: #"tell application "System Events" to keystroke "c" using {command down}"#, completion: completion)
                        } else {
                            // Show an alert about copy failure and prompt for manual entry
                            print("Copy simulation failed and automation unavailable")
                            
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Copy Operation Failed"
                                alert.informativeText = "We couldn't access your selected text. Would you like to enter text manually for processing?"
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "Enter Text Manually")
                                alert.addButton(withTitle: "Cancel")
                                
                                let response = alert.runModal()
                                if response == .alertFirstButtonReturn {
                                    // Show input dialog
                                    self.showManualTextEntryDialog(completion: { text in
                                        if let text = text, !text.isEmpty {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(text, forType: .string)
                                            completion(true)
                                        } else {
                                            completion(false)
                                        }
                                    })
                                } else {
                                    completion(false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func showManualTextEntryDialog(completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Enter Text to Process"
        alert.informativeText = "Please enter or paste the text you want WriterAI to process:"
        alert.alertStyle = .informational
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textField.placeholderString = "Enter text here..."
        textField.isEditable = true
        textField.isSelectable = true
        
        // Create a scroll view to contain the text field for better UX with long text
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = textField
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        alert.accessoryView = scrollView
        
        alert.addButton(withTitle: "Process")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            completion(textField.stringValue)
        } else {
            completion(nil)
        }
    }
    
    private func simulatePaste(text: String, completion: @escaping (Bool) -> Void) {
        print("Simulating Cmd+V...")
        // Set clipboard content *before* pasting
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Reduced delay before paste (from 0.3s to 0.1s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Use NSAppleScript as a fallback method
            // This is cleaner and avoids double-paste issues that might occur with CGEvent
            let pasteScript = "tell application \"System Events\" to keystroke \"v\" using command down"
            self.runAppleScript(script: pasteScript) { success in
                print("DEBUG: Paste complete via AppleScript - success: \(success)")
                print("DEBUG: Clipboard contains: \(NSPasteboard.general.string(forType: .string) ?? "nil")")
                
                if !success {
                    // Fallback to CGEvent approach if AppleScript fails
                    print("DEBUG: AppleScript paste failed, trying CGEvent method")
                    
                    let source = CGEventSource(stateID: .combinedSessionState)
                    
                    // Command down
                    let cmdKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
                    cmdKeyDown?.flags = .maskCommand
                    cmdKeyDown?.post(tap: .cghidEventTap)
                    
                    // V down
                    let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
                    vKeyDown?.flags = .maskCommand
                    vKeyDown?.post(tap: .cghidEventTap)
                    
                    // V up
                    let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
                    vKeyUp?.post(tap: .cghidEventTap)
                    
                    // Command up
                    let cmdKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
                    cmdKeyUp?.post(tap: .cghidEventTap)
                }
                
                // Reduced delay after paste (from 0.2s to 0.1s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    completion(true)
                }
            }
        }
    }
    
    // Helper function to check if automation permission is working
    private func checkAutomationPermission() -> Bool {
        // Try a simple AppleScript to test if we can control System Events
        let testScript = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        if let _ = testScript?.executeAndReturnError(&error) {
            return true
        }
        return false
    }
    
    private func restorePasteboard(originalTypes: [NSPasteboard.PasteboardType]?, originalContent: [String]?) {
        guard let types = originalTypes, let contents = originalContent, 
              types.count == contents.count, !types.isEmpty else { 
            print("No original clipboard content to restore.")
            return 
        }
        
        NSPasteboard.general.clearContents()
        
        // Restore each type and content
        for (index, type) in types.enumerated() {
            if NSPasteboard.general.setString(contents[index], forType: type) {
                print("Restored content for type: \(type)")
            }
        }
        
        print("Original clipboard content restored.")
    }
    
    private func runAppleScript(script: String, completion: @escaping (Bool) -> Void) {
        print("DEBUG: Attempting to run AppleScript: \(script)")
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            print("DEBUG: Failed to initialize NSAppleScript.")
            completion(false)
            return
        }
        
        // Execute AppleScript off the main thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            print("DEBUG: Executing AppleScript...")
            let result = appleScript.executeAndReturnError(&error)
            // Return result to main thread for safe completion handling
            DispatchQueue.main.async {
                if let err = error {
                    print("DEBUG: AppleScript Error: \(err)")
                    // Print more detailed error information
                    if let errCode = err[NSAppleScript.errorNumber] as? NSNumber {
                        print("DEBUG: AppleScript Error Code: \(errCode)")
                    }
                    if let errMsg = err[NSAppleScript.errorMessage] as? String {
                        print("DEBUG: AppleScript Error Message: \(errMsg)")
                    }
                    
                    // Check if we got a permissions error
                    let errDesc = (err[NSAppleScript.errorMessage] as? String) ?? ""
                    if errDesc.contains("not authorized") || errDesc.contains("not allowed") || errDesc.contains("permission") {
                        print("DEBUG: AppleScript permission error - verify accessibility permissions")
                        
                        // Show a notification about permissions
                        let alert = NSAlert()
                        alert.messageText = "Accessibility Permission Issue"
                        alert.informativeText = "WriterAI is having trouble controlling your keyboard. Please make sure it's enabled in System Settings > Privacy & Security > Accessibility."
                        alert.addButton(withTitle: "Open Settings")
                        alert.addButton(withTitle: "Later")
                        
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            self.openAccessibilitySettings(nil)
                        }
                    }
                    
                    completion(false)
                } else {
                    print("DEBUG: AppleScript executed successfully: \(result.stringValue ?? "no return value")")
                    completion(true)
                }
            }
        }
    }
    
    // MARK: - Network Communication
    
    private func sendToRustService(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: rustServiceUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["text": text]
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            completion(.failure(AppError.encodingFailed))
            return
        }
        request.httpBody = jsonData
        
        print("Sending request to Rust service at \(rustServiceUrl)...")
        // Create a dedicated session with custom configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 180.0  // 3 minutes timeout, matching Rust service
        sessionConfig.waitsForConnectivity = true      // Wait for connectivity if not available
        let session = URLSession(configuration: sessionConfig)
        
        session.dataTask(with: request) { data, response, error in
            // Handle network errors (e.g., connection refused)
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Ensure we have an HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AppError.invalidResponse))
                return
            }
            
            // Ensure we have data
            guard let data = data else {
                completion(.failure(AppError.noData))
                return
            }
            
            // Handle non-success HTTP status codes specifically
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to parse error JSON from Rust service if available
                if let jsonError = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let errMsg = jsonError["error"] as? String {
                    completion(.failure(AppError.backendError(status: httpResponse.statusCode, message: errMsg)))
                } else {
                    // Fallback if error JSON parsing fails or isn't provided
                    let responseBody = String(data: data, encoding: .utf8)?.prefix(500) ?? "Non-UTF8 data"
                    completion(.failure(AppError.serverError(status: httpResponse.statusCode, body: String(responseBody))))
                }
                return
            }
            
            // Decode the successful JSON response
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let llmText = jsonResponse["response"] as? String {
                        completion(.success(llmText))
                    } else {
                        completion(.failure(AppError.unexpectedStructure)) // Missing "response" key
                    }
                } else {
                    completion(.failure(AppError.invalidJson)) // Data wasn't a dictionary
                }
            } catch {
                completion(.failure(AppError.decodingFailed(error))) // JSON parsing threw an error
            }
            
        }.resume()
    }
    
    // MARK: - Error Handling & Notifications
    
    // Custom Error enum for better error handling in Swift client
    enum AppError: Error, LocalizedError {
        case encodingFailed
        case invalidResponse
        case noData
        case serverError(status: Int, body: String)
        case backendError(status: Int, message: String) // Error explicitly from Rust backend JSON
        case invalidJson
        case unexpectedStructure
        case decodingFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode request."
            case .invalidResponse: return "Received an invalid response from the server."
            case .noData: return "No data received from the server."
            case .serverError(let status, let body): return "Server returned error \(status). Body: \(body)..."
            case .backendError(_, let message): return "Backend error: \(message)" // Use message from Rust
            case .invalidJson: return "Server response was not valid JSON."
            case .unexpectedStructure: return "Server response JSON structure was unexpected."
            case .decodingFailed(let underlyingError): return "Failed to decode server response: \(underlyingError.localizedDescription)"
            }
        }
    }
    
    // Helper to make error messages slightly more user-friendly
    private func friendlyErrorMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        } else if let urlError = error as? URLError {
            // Provide hints for common network issues
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "Could not connect to the backend service (Port \(rustServiceUrl.port ?? 8989)). Is it running?"
            case .timedOut:
                return "Request timed out. The LLM might be taking too long or the backend is unresponsive."
            default:
                return "Network error: \(urlError.localizedDescription)"
            }
        } else {
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    private func showErrorNotification(title: String, message: String) {
        // Use modern UNUserNotificationCenter for notifications
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil) // Show immediately
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering notification: \(error)")
            }
        }
    }
    
    // MARK: - Hotkey Configuration
    
    /// Structure to hold hotkey configuration details
    struct HotkeyConfig {
        let keyCode: UInt16
        let keyName: String
        let modifierFlags: [NSEvent.ModifierFlags]
        let modifierFlagNames: [String]
        let displayName: String
    }
    
    /// Reads hotkey configuration from Info.plist or returns default values
    private func readHotkeyConfiguration() -> HotkeyConfig {
        // Print the bundle identifier for debugging
        print("DEBUG: Reading config for bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
        
        // Print all keys in the Info.plist
        if let infoPlist = Bundle.main.infoDictionary {
            print("DEBUG: Info.plist keys: \(infoPlist.keys.sorted().joined(separator: ", "))")
        } else {
            print("DEBUG: Could not read Info.plist at all!")
        }
        
        guard let infoPlist = Bundle.main.infoDictionary,
              let hotkeyConfig = infoPlist["HotkeyConfiguration"] as? [String: Any] else {
            // Default to Ctrl+Shift+N if no configuration found
            print("No hotkey configuration found in Info.plist, using default Ctrl+Shift+N")
            return HotkeyConfig(
                keyCode: 45,
                keyName: "N",
                modifierFlags: [.control, .shift],
                modifierFlagNames: ["Control", "Shift"],
                displayName: "⌃⇧N (Ctrl+Shift+N)"
            )
        }
        
        // Read key code and name
        let keyCode = (hotkeyConfig["KeyCode"] as? NSNumber)?.uint16Value ?? 45
        let keyName = (hotkeyConfig["KeyName"] as? String) ?? "N"
        
        // Read modifier flags
        let modifierFlagsString = (hotkeyConfig["ModifierFlags"] as? String) ?? "control,shift"
        let modifierNames = modifierFlagsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Convert string flags to NSEvent.ModifierFlags
        let modifierFlags = modifierNames.compactMap { flagName -> NSEvent.ModifierFlags? in
            switch flagName.lowercased() {
            case "command", "cmd":
                return .command
            case "shift":
                return .shift
            case "control", "ctrl":
                return .control
            case "option", "alt":
                return .option
            case "function", "fn":
                return .function
            default:
                print("Unknown modifier flag: \(flagName)")
                return nil
            }
        }
        
        // Read display name or generate one
        let displayName = (hotkeyConfig["HotkeyDisplayName"] as? String) ?? {
            // Generate default display name if not provided
            let symbols = modifierNames.map { name -> String in
                switch name.lowercased() {
                case "command", "cmd":
                    return "⌘"
                case "shift":
                    return "⇧"
                case "control", "ctrl":
                    return "⌃"
                case "option", "alt":
                    return "⌥"
                case "function", "fn":
                    return "fn"
                default:
                    return name
                }
            }.joined()
            
            let readableNames = modifierNames.map { name -> String in
                switch name.lowercased() {
                case "command", "cmd":
                    return "Command"
                case "shift":
                    return "Shift"
                case "control", "ctrl":
                    return "Control"
                case "option", "alt":
                    return "Option"
                case "function", "fn":
                    return "Function"
                default:
                    return name.capitalized
                }
            }.joined(separator: "+")
            
            return "\(symbols)\(keyName) (\(readableNames)+\(keyName))"
        }()
        
        print("Loaded hotkey configuration: Key=\(keyName) (code \(keyCode)), Modifiers=\(modifierNames.joined(separator: "+"))")
        
        return HotkeyConfig(
            keyCode: keyCode,
            keyName: keyName,
            modifierFlags: modifierFlags,
            modifierFlagNames: modifierNames.map { $0.capitalized },
            displayName: displayName
        )
    }
    
    // This function has been intentionally removed as part of the simplification process
    // We no longer need shell command execution after removing curl fallbacks
}
