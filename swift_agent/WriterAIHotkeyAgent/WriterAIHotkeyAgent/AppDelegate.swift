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
    // Service name for launchd
    private let rustServiceLabel = "com.user.writer_ai_rust_service"
    
    // Use the exact bundle ID from Info.plist to ensure consistency
    private let logger = Logger(subsystem: "com.writer-ai.WriterAIHotkeyAgent", category: "general")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("WriterAI Hotkey Agent started.")
        
        // Ensure the app runs in agent mode
        setupAgentMode()
        
        // Make app completely hidden from Dock and app switcher
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.prohibited)
            ProcessInfo.processInfo.automaticTerminationSupportEnabled = true
        }
        
        // Request notification permissions early
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error {
                self?.logger.error("Error requesting notification authorization: \(error.localizedDescription)")
            }
        }
        
        // Simplified permission check on startup
        checkInitialPermissions()
        
        // Setup core functionality 
        setupHotkeyMonitor()
        createStatusItem()
    }
    
    private func checkInitialPermissions() {
        let accessEnabled = AXIsProcessTrusted()
        logger.info("Initial Accessibility Check: \(accessEnabled ? "Enabled" : "Disabled")")
        
        if !accessEnabled {
            // Prompt only if permissions are missing on first launch after install
            // Avoid prompting repeatedly if the user explicitly denied.
            logger.warning("Accessibility access is required. Please grant in System Settings > Privacy & Security > Accessibility.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Try to trigger the system prompt gently if needed.
                // This doesn't show UI if already granted or denied.
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: false] as CFDictionary)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        for monitor in monitor {
            NSEvent.removeMonitor(monitor)
        }
        logger.info("All event monitors removed. Application terminating.")
    }
    
    private func setupHotkeyMonitor() {
        // Read hotkey configuration from Info.plist
        let hotkeyConfig = readHotkeyConfiguration()
        let keyName = hotkeyConfig.keyName
        let modifierNames = hotkeyConfig.modifierFlagNames.joined(separator: "+")
        
        logger.info("Setting up global hotkey monitor for \(modifierNames)+\(keyName)...")
        
        // Remove any previously added monitors if this function were called again
        for oldMonitor in monitor {
            NSEvent.removeMonitor(oldMonitor)
        }
        monitor.removeAll()
        
        let requiredFlags = hotkeyConfig.modifierFlags
        let keyCode = hotkeyConfig.keyCode
        
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask) // Isolate relevant flags
            
            if event.keyCode == keyCode && requiredFlags.allSatisfy({ flags.contains($0) }) {
                // Optional: Add stricter check if ONLY required flags should be pressed (ignoring caps lock/fn)
                // let nonRequiredFlags = flags.subtracting(NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.RawValue(UInt(0xFFFF0000)))) // Remove device-dependent flags like caps lock, fn
                // if nonRequiredFlags == NSEvent.ModifierFlags(requiredFlags) { ... }
                
                self.logger.debug("✅ GLOBAL HOTKEY DETECTED: \(modifierNames)+\(keyName)")
                self.handleHotkey()
            }
        }
        
        if let globalMonitor = globalMonitor {
            monitor.append(globalMonitor)
            logger.info("Successfully added global key down monitor.")
        } else {
            logger.error("🚨 ERROR: Failed to add global key down monitor. Accessibility permissions likely missing or inactive.")
            DispatchQueue.main.async {
                self.showErrorNotification(title: "Hotkey Monitor Failed", message: "Could not set up the global hotkey. Please grant Accessibility permissions and restart the agent if needed.")
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
        
        // Log status after toggle for debugging
        if #available(macOS 13.0, *) {
            // Try with the specific bundle ID from the error message
            let specificID = "com.mk.ai.WriterAIHotkeyAgent"
            let loginItem = SMAppService.loginItem(identifier: specificID)
            let status = loginItem.status
            logger.debug("[TOGGLE] Status check for \(specificID): \(status.rawValue)")
            
            // Also check Info.plist ID
            let infoID = "com.writer-ai.WriterAIHotkeyAgent"
            let infoItem = SMAppService.loginItem(identifier: infoID)
            let infoStatus = infoItem.status
            logger.debug("[TOGGLE] Status check for \(infoID): \(infoStatus.rawValue)")
        }
    }
    
    private func enableLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                // Use the exact bundle ID from the error message
                let bundleID = "com.mk.ai.WriterAIHotkeyAgent"
                let service = SMAppService.loginItem(identifier: bundleID)
                try service.register()
                logger.info("Successfully registered login item with ID: \(bundleID)")
            } catch {
                logger.error("Failed to register login item: \(error.localizedDescription)")
                
                // Try fallback with the bundle ID from Info.plist
                do {
                    let fallbackID = "com.writer-ai.WriterAIHotkeyAgent"
                    let fallbackService = SMAppService.loginItem(identifier: fallbackID)
                    try fallbackService.register()
                    logger.info("Successfully registered login item with fallback ID: \(fallbackID)")
                } catch {
                    logger.error("Failed to register login item with fallback ID: \(error.localizedDescription)")
                    showErrorNotification(title: "Autostart Setup Failed", message: "Could not enable automatic startup: \(error.localizedDescription)")
                }
            }
        } else {
            // Fallback for macOS < 13
            let safePath = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to make login item at end with properties {path:\"\(safePath)\", hidden:true}"
            var error: NSDictionary?
            if NSAppleScript(source: script)?.executeAndReturnError(&error) == nil {
                logger.error("Failed to enable login item (AppleScript): \(error?.description ?? "Unknown error")")
                showErrorNotification(title: "Autostart Setup Failed", message: "Could not enable automatic startup using AppleScript.")
            } else {
                logger.info("Successfully enabled login item (AppleScript).")
            }
        }
    }
    
    private func disableLoginItem() {
        if #available(macOS 13.0, *) {
            // Try to unregister with all possible bundle IDs to ensure we catch the right one
            var success = false
            
            // First try the specific ID from the error message
            do {
                let specificID = "com.mk.ai.WriterAIHotkeyAgent"
                let service = SMAppService.loginItem(identifier: specificID)
                try service.unregister()
                logger.info("Successfully unregistered login item with ID: \(specificID)")
                success = true
            } catch {
                logger.debug("Failed to unregister with specific ID: \(error.localizedDescription)")
            }
            
            // Also try with the Info.plist bundle ID
            do {
                let infoID = "com.writer-ai.WriterAIHotkeyAgent"
                let service = SMAppService.loginItem(identifier: infoID)
                try service.unregister()
                logger.info("Successfully unregistered login item with Info.plist ID: \(infoID)")
                success = true
            } catch {
                logger.debug("Failed to unregister with Info.plist ID: \(error.localizedDescription)")
            }
            
            // If both failed, show error
            if !success {
                logger.error("Failed to unregister login item with any known bundle ID")
                showErrorNotification(title: "Autostart Removal Failed", message: "Could not disable automatic startup. Please check system settings.")
            }
        } else {
            // Fallback for macOS < 13
            // Important: Ensure Bundle.main.bundlePath doesn't contain characters that break AppleScript strings easily
            let safePath = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to delete (every login item whose path is \"\(safePath)\")"
            var error: NSDictionary?
            if NSAppleScript(source: script)?.executeAndReturnError(&error) == nil {
                logger.error("Failed to disable login item (AppleScript): \(error?.description ?? "Unknown error")")
                showErrorNotification(title: "Autostart Removal Failed", message: "Could not disable automatic startup using AppleScript.")
            } else {
                logger.info("Successfully disabled login item (AppleScript).")
            }
        }
    }
    
    private func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            // First check the specific bundle ID from the error message
            let specificID = "com.mk.ai.WriterAIHotkeyAgent"
            let loginItem = SMAppService.loginItem(identifier: specificID)
            
            // Enhanced logging to help diagnose issues
            logger.debug("APP PATH: \(Bundle.main.bundlePath)")
            logger.debug("BUNDLE ID FROM INFO.PLIST: \(Bundle.main.bundleIdentifier ?? "nil")")
            
            // Check status of the specific ID
            let status = loginItem.status
            let specificEnabled = status == .enabled
            logger.debug("Login item status for \(specificID): \(status.rawValue) -> Enabled: \(specificEnabled)")
            
            // Also check the Info.plist bundle ID
            let infoID = "com.writer-ai.WriterAIHotkeyAgent"
            let infoItem = SMAppService.loginItem(identifier: infoID)
            let infoStatus = infoItem.status
            let infoEnabled = infoStatus == .enabled
            logger.debug("Login item status for \(infoID): \(infoStatus.rawValue) -> Enabled: \(infoEnabled)")
            
            // Return true if either ID is enabled
            return specificEnabled || infoEnabled
        } else {
            // For older macOS versions, we can check via AppleScript
            let safePath = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "System Events"
                return exists login item whose path is "\(safePath)"
            end tell
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let enabled = result?.booleanValue ?? false
            
            logger.debug("Login item status (AppleScript): \(enabled)")
            if let error = error {
                logger.error("Error checking login item status (AppleScript): \(error)")
            }
            return enabled
        }
    }
    
    // MARK: - Status Menu
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.title = "W"
            button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            button.setAccessibilityLabel("WriterAI Agent") // More specific accessibility label
        }
        
        let menu = NSMenu()
        
        // 1. Hotkey Display (Non-clickable)
        let hotkeyConfig = readHotkeyConfiguration()
        let hotkeyInfoItem = NSMenuItem(title: "Hotkey: \(hotkeyConfig.displayName)", action: nil, keyEquivalent: "")
        hotkeyInfoItem.isEnabled = false // Make it non-interactive
        menu.addItem(hotkeyInfoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Restart Rust Service (Backend)
        let restartRustItem = NSMenuItem(title: "Restart Backend Service", action: #selector(restartRustService(_:)), keyEquivalent: "")
        restartRustItem.target = self
        // Add tooltip for clarity
        restartRustItem.toolTip = "Restarts the Rust process handling AI requests."
        menu.addItem(restartRustItem)
        
        // 3. Restart Swift Service (Agent)
        let restartSwiftItem = NSMenuItem(title: "Restart Hotkey Agent", action: #selector(restartApp(_:)), keyEquivalent: "")
        restartSwiftItem.target = self
        restartSwiftItem.toolTip = "Restarts this hotkey listener application. Useful after changing permissions."
        menu.addItem(restartSwiftItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Launch at Login Toggle
        let loginItemEnabled = isLoginItemEnabled()
        let loginItemToggle = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItemSetting(_:)), keyEquivalent: "l")
        loginItemToggle.target = self
        loginItemToggle.state = loginItemEnabled ? .on : .off
        menu.addItem(loginItemToggle)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit WriterAI Agent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        // Set the menu
        statusItem?.menu = menu
        logger.info("Status menu created with new simplified items.")
    }
    
    @objc private func restartRustService(_ sender: Any?) {
        logger.info("Attempting to restart Rust service (Label: \(self.rustServiceLabel))...")
        showNotification(title: "Backend Service", message: "Attempting to restart...")
        
        // Use unload/load commands which are more reliable for complete restarts
        let unloadCommand = "launchctl unload ~/Library/LaunchAgents/\(self.rustServiceLabel).plist"
        let loadCommand = "launchctl load -w ~/Library/LaunchAgents/\(self.rustServiceLabel).plist"
        
        // Run Unload Command
        runShellCommand(command: unloadCommand) { [weak self] unloadSuccess, unloadOutput in
            guard let self = self else { return }
            
            if unloadSuccess {
                self.logger.info("Rust service unloaded successfully.")
                // Wait a brief moment before loading
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Run Load Command
                    self.runShellCommand(command: loadCommand) { loadSuccess, loadOutput in
                        if loadSuccess {
                            self.logger.info("Rust service loaded successfully.")
                            self.showNotification(title: "Backend Service Restarted", message: "The backend service was restarted successfully.")
                        } else {
                            self.logger.error("Failed to load Rust service. Output: \(loadOutput)")
                            self.showErrorNotification(title: "Backend Restart Failed", message: "Could not start the backend service. Check logs.")
                        }
                    }
                }
            } else {
                // Log failure to unload, but still attempt to load
                self.logger.warning("Failed to unload Rust service (maybe not running?). Output: \(unloadOutput). Attempting to load anyway...")
                
                // Run Load Command directly
                self.runShellCommand(command: loadCommand) { loadSuccess, loadOutput in
                    if loadSuccess {
                        self.logger.info("Rust service loaded successfully (after failing to unload).")
                        self.showNotification(title: "Backend Service Started", message: "The backend service was started (it might not have been running).")
                    } else {
                        self.logger.error("Failed to load Rust service after failing to unload. Output: \(loadOutput)")
                        self.showErrorNotification(title: "Backend Restart Failed", message: "Could not start the backend service after trying to stop it. Check logs.")
                    }
                }
            }
        }
    }
    
    // Removed old menu functions that are no longer needed with the simplified menu
    
    // Removed testDirectTextProcessing() since it's now handled by the testRustConnection method
    
    // This function has been intentionally removed as part of the simplification process
    // The functionality is now handled directly by the sendToRustService function
    
    // Removed handleRequestResult since it's now handled directly in the appropriate methods
    
    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Error delivering notification: \(error.localizedDescription)")
            }
        }
    }
    
    // Removed updateAccessibilityStatus method - no longer needed with the simplified menu
    
    @objc private func restartApp(_ sender: Any?) {
        logger.info("Restarting Hotkey Agent...")
        
        guard let executablePath = Bundle.main.executablePath else {
            logger.error("Could not get executable path to restart.")
            showErrorNotification(title: "Restart Failed", message: "Could not determine application path.")
            return
        }
        
        // Set a flag to indicate this is a restart to avoid permission check loop
        UserDefaults.standard.set(true, forKey: "WasRecentlyRestarted")
        UserDefaults.standard.synchronize()
        
        // Launch a new instance
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        
        do {
            try process.run()
            // Create a small delay to allow the new instance to start before terminating this one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        } catch {
            logger.error("Failed to launch new instance during restart: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: "WasRecentlyRestarted") // Clear flag on failure
            showErrorNotification(title: "Restart Failed", message: "Could not launch new application instance.")
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
                
                // 2. Process text directly - timing is handled in processTextWithFallbacks
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
        
        // Shorter delay before triggering copy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else {
                print("ERROR: Failed to create CGEventSource for copy")
                self.fallbackToAppleScriptCopy(completion: completion)
                return
            }
            
            // Create and post all events for Cmd+C
            let cmdKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // Command key
            cmdKeyDown?.flags = .maskCommand
            
            let cKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'c' key
            cKeyDown?.flags = .maskCommand
            
            let cKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            let cmdKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            
            // Post the events in sequence
            cmdKeyDown?.post(tap: .cghidEventTap)
            cKeyDown?.post(tap: .cghidEventTap)
            cKeyUp?.post(tap: .cghidEventTap)
            cmdKeyUp?.post(tap: .cghidEventTap)
            
            // Check clipboard with slightly reduced delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                print("DEBUG: Clipboard content after copy: \(NSPasteboard.general.string(forType: .string) ?? "nil")")
                
                if NSPasteboard.general.string(forType: .string) != nil {
                    // Success - we got something on the clipboard
                    completion(true)
                } else {
                    self.handleCopyFailure(completion: completion)
                }
            }
        }
    }
    
    private func fallbackToAppleScriptCopy(completion: @escaping (Bool) -> Void) {
        print("DEBUG: Falling back to AppleScript copy.")
        let copyScript = "tell application \"System Events\" to keystroke \"c\" using command down"
        self.runAppleScript(script: copyScript) { success in
            print("DEBUG: Copy complete via AppleScript fallback - success: \(success)")
            
            if success {
                // Check if AppleScript actually got content into clipboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if NSPasteboard.general.string(forType: .string) != nil {
                        completion(true)
                    } else {
                        // Still no content - handle as failure
                        self.handleCopyFailure(completion: completion)
                    }
                }
            } else {
                // AppleScript failed - go to manual entry
                self.handleCopyFailure(completion: completion)
            }
        }
    }
    
    private func handleCopyFailure(completion: @escaping (Bool) -> Void) {
        // If in test mode, use fallback content
        if UserDefaults.standard.bool(forKey: "ProvideTestContentOnFailure") {
            print("Copy failed, but providing test content anyway due to defaults setting")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("Fallback test content for WriterAI", forType: .string)
            completion(true)
            return
        }
        
        // Show an alert about copy failure and prompt for manual entry
        print("Copy simulation failed - prompting for manual input")
        
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
        
        // Reduced delay before paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("DEBUG: Attempting paste via CGEvent first")
            
            // Try CGEvent approach first since it's faster than AppleScript
            let source = CGEventSource(stateID: .combinedSessionState)
            guard let source = source else {
                print("ERROR: Failed to create CGEventSource")
                self.fallbackToAppleScriptPaste(completion: completion)
                return
            }
            
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
            
            print("DEBUG: CGEvent paste sequence posted.")
            
            // Reduced delay after paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("DEBUG: Paste complete via CGEvent.")
                completion(true)
            }
        }
    }
    
    // Helper for fallback to AppleScript paste if CGEvent fails
    private func fallbackToAppleScriptPaste(completion: @escaping (Bool) -> Void) {
        print("DEBUG: Falling back to AppleScript paste.")
        let pasteScript = "tell application \"System Events\" to keystroke \"v\" using command down"
        self.runAppleScript(script: pasteScript) { success in
            print("DEBUG: Paste complete via AppleScript fallback - success: \(success)")
            
            // Even if AppleScript fails, we need to complete the operation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                completion(success)
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
            logger.debug("No original clipboard content to restore.")
            return 
        }
        
        NSPasteboard.general.clearContents()
        
        var restoredTypes: [String] = []
        // Restore each type and content
        for (index, type) in types.enumerated() {
            if NSPasteboard.general.setString(contents[index], forType: type) {
                restoredTypes.append(type.rawValue)
            }
        }
        
        if !restoredTypes.isEmpty {
            logger.debug("Original clipboard content restored for types: \(restoredTypes.joined(separator: ", "))")
        }
    }
    
    private func runAppleScript(script: String, completion: @escaping (Bool) -> Void) {
        logger.debug("Attempting to run AppleScript: \(script.prefix(100))...")
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            logger.error("Failed to initialize NSAppleScript.")
            completion(false)
            return
        }
        
        // Execute AppleScript off the main thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let result = appleScript.executeAndReturnError(&error)
            // Return result to main thread for safe completion handling
            DispatchQueue.main.async {
                if let err = error {
                    self.logger.error("AppleScript Error: \(err)")
                    // Log more detailed error information
                    if let errCode = err[NSAppleScript.errorNumber] as? NSNumber {
                        self.logger.error("AppleScript Error Code: \(errCode)")
                    }
                    if let errMsg = err[NSAppleScript.errorMessage] as? String {
                        self.logger.error("AppleScript Error Message: \(errMsg)")
                    }
                    
                    // Check if we got a permissions error
                    let errDesc = (err[NSAppleScript.errorMessage] as? String) ?? ""
                    if errDesc.contains("not authorized") || errDesc.contains("not allowed") || errDesc.contains("permission") {
                        self.logger.warning("AppleScript permission error - verify accessibility permissions")
                        
                        // Just show error notification instead of opening a settings window
                        self.showErrorNotification(title: "Permission Issue", 
                                                message: "WriterAI is having trouble controlling your keyboard. Please enable it in System Settings > Privacy & Security > Accessibility.")
                    }
                    
                    completion(false)
                } else {
                    self.logger.debug("AppleScript executed successfully: \(result.stringValue ?? "no return value")")
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
        
        logger.debug("Sending request to Rust service at \(self.rustServiceUrl)...")
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
        logger.debug("Reading config for bundle: com.writer-ai.WriterAIHotkeyAgent")
        
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
    
    // MARK: - Shell Command Execution
    
    private func runShellCommand(command: String, completion: @escaping (Bool, String) -> Void) {
        logger.debug("Running shell command: \(command)")
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/sh") // Use shell to interpret command
        process.arguments = ["-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run asynchronously to avoid blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            var outputString = ""
            var errorString = ""
            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            
            // Observers must be set *before* launching
            outputHandle.readabilityHandler = { handle in
                if let data = try? handle.readToEnd(), let str = String(data: data, encoding: .utf8) {
                    outputString += str
                }
            }
            errorHandle.readabilityHandler = { handle in
                if let data = try? handle.readToEnd(), let str = String(data: data, encoding: .utf8) {
                    errorString += str
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit() // Wait for the process to complete
                
                // Ensure handlers get remaining data
                try? outputHandle.close()
                try? errorHandle.close()
                
                
                let status = process.terminationStatus
                let combinedOutput = (outputString.isEmpty ? "" : "Output:\n\(outputString)") + (errorString.isEmpty ? "" : "\nError Output:\n\(errorString)")
                
                DispatchQueue.main.async {
                    if status == 0 {
                        self.logger.debug("Shell command finished successfully. \(combinedOutput)")
                        completion(true, combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        self.logger.error("Shell command failed with status \(status). \(combinedOutput)")
                        completion(false, combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            } catch {
                let errorMessage = "Failed to run shell command '\(command)': \(error.localizedDescription)"
                self.logger.error("\(errorMessage)")
                DispatchQueue.main.async {
                    completion(false, errorMessage)
                }
            }
        }
    }
}
