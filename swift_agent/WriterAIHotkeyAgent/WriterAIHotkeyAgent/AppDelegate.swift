//
//  AppDelegate.swift
//  WriterAIHotkeyAgent
//
//  Created by Max Kul on 31/03/2025.
//

import AppKit
import Foundation
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var monitor = [Any]()
    private var statusItem: NSStatusItem?
    // Read port from Rust config or use default. Best to match default.
    // Using explicit IP address instead of localhost to avoid DNS resolution issues in sandbox
    private let rustServiceUrl = URL(string: "http://127.0.0.1:8989/process")!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("WriterAI Hotkey Agent started.")
        
        // Enable AppleScript for paste as suggested for debugging
        UserDefaults.standard.set(true, forKey: "UseAppleScriptForPaste")
        
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
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
    print("Setting up simplified global hotkey monitor for Cmd+Shift+A...")

    // Remove any previously added monitors if this function were called again
    for oldMonitor in monitor {
        NSEvent.removeMonitor(oldMonitor)
    }
    monitor.removeAll()

    let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
    let A_KEYCODE: UInt16 = 0 // Keycode for 'A'

    let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        // Use intersection to ensure ONLY the required flags (and potentially Caps Lock) are present.
        // Or use contains() if you want to allow other modifiers like Fn. Test which works best for you.
        // Let's start with contains() as it's more forgiving.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask) // Isolate relevant flags

        // --- DEBUGGING --- 
        // Always print every key press for debugging
        print("Global KeyDown: Code=\(event.keyCode), Flags=\(flags.rawValue), Chars='\(event.characters ?? "-")'")
        if event.keyCode == A_KEYCODE {
            print("A Key Pressed: Flags=\(flags.rawValue), Required=\(requiredFlags.rawValue)")
            print("  -> Has Command: \(flags.contains(.command))")
            print("  -> Has Shift: \(flags.contains(.shift))")
        }
        // --- END DEBUGGING ---

        if event.keyCode == A_KEYCODE && flags.contains(requiredFlags) {
             // Optional: Check if ONLY required flags are pressed ( stricter )
             // if event.keyCode == A_KEYCODE && flags == requiredFlags {
             print("✅ GLOBAL HOTKEY DETECTED: Cmd+Shift+A")
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
    
    // MARK: - Status Menu
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Set the image or title for the status item
        if let button = statusItem?.button {
            button.title = "⌨️" // Use a text emoji instead of system symbol which might not be available
        }
        
        // Create the menu
        let menu = NSMenu()
        
        // Add a status item
        let statusMenuItem = NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        // Add a hotkey info item
        let hotkeyInfoItem = NSMenuItem(title: "Hotkey: ⇧⌘A (Shift+Command+A)", action: nil, keyEquivalent: "")
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
        let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if NSWorkspace.shared.open(accessibilityURL) {
            print("Opened System Settings > Privacy & Security > Accessibility")
        } else {
            // Fallback to opening Security & Privacy in general
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
            print("Opened System Settings > Privacy & Security")
        }
    }
    
    @objc private func testHotkey(_ sender: Any?) {
        print("Manual test of hotkey processing triggered")
        
        // Try manually triggering the full hotkey handler for complete testing
        handleHotkey()
    }
    
    @objc private func testRustConnection(_ sender: Any?) {
        print("Testing connection to Rust service...")
        
        // Create a simple HTTP request to check if the server is responding
        var request = URLRequest(url: rustServiceUrl)
        request.timeoutInterval = 10 // 10 seconds timeout for connection test
        
        // Create a dedicated session with custom configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10.0  // 10 seconds timeout 
        sessionConfig.waitsForConnectivity = true      // Wait for connectivity if not available
        let session = URLSession(configuration: sessionConfig)
        
        session.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
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
                    
                } else if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    print("✅ Connection test completed with status code: \(statusCode)")
                    
                    // Even a 404 or error status code means the server is responding
                    self.showSuccessNotification(title: "Connection Successful", 
                                               message: "Successfully connected to Rust service (Status: \(statusCode))")
                    
                    // Now try a sample text processing after confirming connection
                    self.testDirectTextProcessing()
                }
            }
        }.resume()
    }
    
    private func testDirectTextProcessing() {
        print("Testing direct text processing with sample text...")
        
        // Use a predefined sample text
        let sampleText = "This is a test of the WriterAI system."
        print("Sample input: \"\(sampleText)\"")
        
        // Use the direct URLSession method
        sendToRustService(text: sampleText) { result in
            self.handleRequestResult(result)
        }
    }
    
    // This function has been intentionally removed as part of the simplification process
    // The functionality is now handled directly by the sendToRustService function
    
    private func handleRequestResult(_ result: Result<String, Error>) {
        DispatchQueue.main.async {
            switch result {
            case .success(let response):
                print("✅ Got response from Rust service!")
                print("Response: \"\(response)\"")
                
                // Show a success notification
                self.showSuccessNotification(title: "Test Successful", 
                                           message: "Successfully processed text. Response: \"\(response.prefix(50))\"")
                
            case .failure(let error):
                print("❌ Error from Rust service: \(error)")
                
                // Show a more detailed error for troubleshooting
                let errorMessage = self.friendlyErrorMessage(for: error)
                self.showErrorNotification(title: "Test Failed", 
                                         message: "Error processing text: \(errorMessage)")
            }
        }
    }
    
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
        
        // Try a simple AppleScript to test if we can actually control the system
        var canControlSystem = false
        let appleScript = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        if let scriptResult = appleScript?.executeAndReturnError(&error) {
            print("DEBUG: AppleScript control test succeeded with result: \(scriptResult.stringValue ?? "no value")")
            canControlSystem = true
        } else if let err = error {
            print("DEBUG: AppleScript control test failed: \(err)")
            if let errMsg = err[NSAppleScript.errorMessage] as? String {
                print("DEBUG: AppleScript control test error message: \(errMsg)")
            }
        }
        
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
        
        // Also log to console
        print("Accessibility permissions - API status: \(accessEnabled ? "Enabled" : "Disabled"), Can control system: \(canControlSystem ? "Yes" : "No")")
        
        // If accessibility is granted according to API but we can't control the system,
        // the app likely needs to be restarted to pick up the permission
        if accessEnabled && !canControlSystem {
            print("⚠️ Permission appears to be granted but not effective. Try restarting the app.")
            
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
                    alert.informativeText = "Try these steps:\n\n1. Quit this app completely\n2. Go to System Settings > Privacy & Security > Accessibility\n3. Remove this app from the list\n4. Add it back and ensure the checkbox is enabled\n5. Start the app again"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open Accessibility Settings")
                    alert.addButton(withTitle: "Quit App")
                    alert.addButton(withTitle: "Continue Anyway")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.openAccessibilitySettings(nil)
                    } else if response == .alertSecondButtonReturn {
                        NSApp.terminate(nil)
                    }
                }
            } else {
                // First time noticing this issue - suggest restart
                // Show restart recommendation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = "App Restart Recommended"
                    alert.informativeText = "Accessibility permission has been granted, but macOS may require the app to be restarted for it to take effect.\n\nWould you like to restart the app now?"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Restart Now")
                    alert.addButton(withTitle: "Later")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.restartApp(nil)
                    }
                }
            }
        }
    }
    
    @objc private func restartApp(_ sender: Any?) {
        // Get the path to the current executable
        let executablePath = Bundle.main.executablePath!
        
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
    
    private func handleHotkey() {
        print("🔥 HOTKEY HANDLER ACTIVATED: Command+Shift+A 🔥")
        
        // Test if we can actually control the system rather than just check the API
        var canControlSystem = false
        let testScript = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        print("DEBUG: Checking if we can control the system before proceeding...")
        if let scriptResult = testScript?.executeAndReturnError(&error) {
            print("DEBUG: AppleScript control test succeeded: \(scriptResult.stringValue ?? "no result")")
            canControlSystem = true
        } else if let err = error {
            print("DEBUG: AppleScript control test failed: \(err)")
            if let errMsg = err[NSAppleScript.errorMessage] as? String {
                print("DEBUG: AppleScript control test error message: \(errMsg)")
            }
        }
        
        // Check UserDefaults for a flag to bypass accessibility check (for troubleshooting)
        let bypassAccessibilityCheck = UserDefaults.standard.bool(forKey: "BypassAccessibilityCheck")
        
        // Force bypass already set at app launch
        
        if !canControlSystem && !bypassAccessibilityCheck {
            print("ERROR: Accessibility functionality is not working properly.")
            
            // Check the API status
            let accessEnabled = AXIsProcessTrusted()
            
            // Check if we've already tried restarting
            let wasRecentlyRestarted = UserDefaults.standard.bool(forKey: "WasRecentlyRestarted")
            
            if accessEnabled {
                if wasRecentlyRestarted {
                    // We already tried restarting and it didn't work
                    let alert = NSAlert()
                    alert.messageText = "Accessibility Issues Persist"
                    alert.informativeText = "Despite app restart, accessibility permissions are still not working properly.\n\nWould you like to:\n1. Try again with manual text entry\n2. Proceed anyway (results may be limited)\n3. Quit the app to troubleshoot"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Try Manual Text Entry")
                    alert.addButton(withTitle: "Proceed Anyway")
                    alert.addButton(withTitle: "Quit App")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        // Use manual text entry
                        testDirectTextProcessing()
                        return
                    } else if response == .alertSecondButtonReturn {
                        // Bypass check for this session
                        UserDefaults.standard.set(true, forKey: "BypassAccessibilityCheck")
                        print("⚠️ Bypassing accessibility check for this session")
                        // Continue with execution
                    } else {
                        NSApp.terminate(nil)
                        return
                    }
                } else {
                    // First time noticing this issue - suggest restart
                    print("⚠️ Permission appears to be granted but not effective. Try restarting the app.")
                    
                    let alert = NSAlert()
                    alert.messageText = "App Restart Required"
                    alert.informativeText = "Accessibility permission has been granted, but macOS requires the app to be restarted for it to take effect.\n\nWould you like to restart the app now?"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Restart Now")
                    alert.addButton(withTitle: "Use Manual Text Entry")
                    alert.addButton(withTitle: "Later")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        restartApp(nil)
                        return
                    } else if response == .alertSecondButtonReturn {
                        // Use manual text entry
                        testDirectTextProcessing()
                        return
                    } else {
                        return
                    }
                }
            } else {
                // Permission not granted
                showErrorNotification(title: "Accessibility Required", 
                                     message: "Writer AI needs accessibility permissions to copy and paste text.")
                
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Writer AI needs accessibility permissions to detect hotkeys and manipulate text.\n\nPlease go to System Settings > Privacy & Security > Accessibility and add this app to the list."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Accessibility Settings")
                alert.addButton(withTitle: "Use Manual Text Entry")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    openAccessibilitySettings(nil)
                    return
                } else if response == .alertSecondButtonReturn {
                    // Use manual text entry
                    testDirectTextProcessing()
                    return
                } else {
                    return
                }
            }
        }
        
        // If we got this far, either accessibility works or we're bypassing the check
        
        print("⌨️ Hotkey triggered - processing selected text...")
        
        // 1. Get selected text via Copy simulation
        // Store the original types instead of trying to copy the items directly
        let originalPasteboard = NSPasteboard.general
        let originalTypes = originalPasteboard.types
        let originalContent = originalTypes?.compactMap { type in
            return originalPasteboard.string(forType: type)
        }
        
        simulateCopy { success in
            guard success else {
                self.showErrorNotification(title: "Copy Failed", message: "Could not simulate Cmd+C. Check Accessibility permissions.")
                self.restorePasteboard(originalTypes: originalTypes, originalContent: originalContent)
                return
            }
            
            // Short delay for clipboard to update reliably
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { // 250ms delay
                guard let selectedText = NSPasteboard.general.string(forType: .string), !selectedText.isEmpty else {
                    print("No text found on clipboard after copy attempt.")
                    self.restorePasteboard(originalTypes: originalTypes, originalContent: originalContent)
                    return
                }
                
                print("Selected Text Length: \(selectedText.count)")
                
                // 2. Process text - first try via curl, then fallback to direct method
                self.processTextWithFallbacks(selectedText, originalTypes: originalTypes, originalContent: originalContent)
            }
        }
    }
    
    private func processTextWithFallbacks(_ text: String, originalTypes: [NSPasteboard.PasteboardType]?, originalContent: [String]?) {
        print("Processing text directly using URLSession...")
        
        // Send text to Rust service using direct method
        self.sendToRustService(text: text) { result in
            // Ensure UI updates (paste simulation, notifications) are on main thread
            DispatchQueue.main.async {
                switch result {
                case .success(let llmResponse):
                    print("Received LLM Response Length: \(llmResponse.count)")
                    // DEBUG: Add the suggested debug print
                    print("DEBUG: About to paste: \"\(llmResponse)\"")
                    // Paste the response
                    self.simulatePaste(text: llmResponse) { pasteSuccess in
                        if !pasteSuccess {
                            self.showErrorNotification(title: "Paste Failed", message: "Could not simulate Cmd+V. Response copied to clipboard. Check Accessibility.")
                            // Put response on clipboard as fallback
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(llmResponse, forType: .string)
                        } else {
                            print("Paste simulation successful.")
                        }
                    }
                    
                case .failure(let error):
                    // Log detailed error
                    print("Error processing text: \(error.localizedDescription)")
                    // Show user-friendly notification
                    let errorMessage = self.friendlyErrorMessage(for: error)
                    self.showErrorNotification(title: "Processing Error", message: errorMessage)
                    // Restore original clipboard on error
                    self.restorePasteboard(originalTypes: originalTypes, originalContent: originalContent)
                }
            }
        }
    }
    
    // This function has been intentionally removed as part of the simplification process
    // The functionality is now handled directly in the processTextWithFallbacks function
    
    // MARK: - Clipboard & Simulation Helpers
    
    private func simulateCopy(completion: @escaping (Bool) -> Void) {
        print("Simulating Cmd+C...")
        // For testing, let's use a hardcoded text so we don't need to actually copy
        if UserDefaults.standard.bool(forKey: "UseTestMode") {
            print("Using test mode with hardcoded text")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("This is test text that will be processed by WriterAI", forType: .string)
            completion(true)
            return
        }
        
        // Clear pasteboard *before* copy to help ensure we get the new content
        NSPasteboard.general.clearContents()
        
        // Try direct key event simulation for better reliability
        let delayTime = DispatchTime.now() + 0.25 // Increased delay before triggering copy
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
            
            // Check if we got something in the pasteboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // DEBUG: Add the suggested debug print
                print("DEBUG: Clipboard content after copy simulation: \(NSPasteboard.general.string(forType: .string) ?? "nil")")
                
                let hasPasteboardContent = NSPasteboard.general.string(forType: .string) != nil
                if hasPasteboardContent {
                    completion(true)
                } else {
                    // Fallback to AppleScript if CGEvent approach fails
                    print("CGEvent copy failed, falling back to AppleScript...")
                    self.runAppleScript(script: #"tell application "System Events" to keystroke "c" using {command down}"#, completion: completion)
                }
            }
        }
    }
    
    private func simulatePaste(text: String, completion: @escaping (Bool) -> Void) {
        print("Simulating Cmd+V...")
        // Set clipboard content *before* pasting
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Small delay for clipboard to settle before pasting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { // 250ms delay
            // Try direct key event simulation for better reliability
            let source = CGEventSource(stateID: .combinedSessionState)
            
            // Create key down event for command key (modifiers)
            let cmdKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // 0x37 is Command key
            cmdKeyDown?.flags = .maskCommand
            cmdKeyDown?.post(tap: .cghidEventTap)
            
            // Create key down event for 'v' key
            let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 is 'v' key
            vKeyDown?.flags = .maskCommand
            vKeyDown?.post(tap: .cghidEventTap)
            
            // Create key up event for 'v' key
            let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vKeyUp?.post(tap: .cghidEventTap)
            
            // Create key up event for command key
            let cmdKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            cmdKeyUp?.post(tap: .cghidEventTap)
            
            // Check if paste succeeded (no foolproof way except timing)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // DEBUG: Check if pasteboard still contains the expected text
                print("DEBUG: Clipboard content before paste: \(NSPasteboard.general.string(forType: .string) ?? "nil")")
                
                // Fallback to AppleScript if user reports issues with CGEvent approach
                if UserDefaults.standard.bool(forKey: "UseAppleScriptForPaste") {
                    print("Using AppleScript for paste based on user preference...")
                    self.runAppleScript(script: #"tell application "System Events" to keystroke "v" using {command down}"#, completion: completion)
                } else {
                    // Assume CGEvent worked
                    print("DEBUG: Using CGEvent paste - assuming it worked")
                    completion(true)
                }
            }
        }
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
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
    
    // This function has been intentionally removed as part of the simplification process
    // We no longer need shell command execution after removing curl fallbacks
}
