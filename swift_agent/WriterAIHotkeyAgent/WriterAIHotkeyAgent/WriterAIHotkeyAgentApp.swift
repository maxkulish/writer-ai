//
//  WriterAIHotkeyAgentApp.swift
//  WriterAIHotkeyAgent
//
//  Created by Max Kul on 31/03/2025.
//

import SwiftUI

@main
struct WriterAIHotkeyAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Don't try to set activation policy at init time
        // This will be handled in the AppDelegate instead
    }
    
    var body: some Scene {
        Settings { 
            EmptyView() 
        }
        .commands {
            // Remove standard menu items
            CommandGroup(replacing: .appInfo) {}
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
        }
    }
}
