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
    
    var body: some Scene {
        Settings { EmptyView() } // No visible windows needed
    }
}
