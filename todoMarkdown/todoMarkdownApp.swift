//
//  todoMarkdownApp.swift
//  todoMarkdown
//
//  Created by Leo Y on 2026/3/16.
//

import SwiftUI
import AppKit

@main
struct todoMarkdownApp: App {
    @StateObject private var controller = WorkspaceController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Workspace...", action: controller.chooseWorkspace)
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo") {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(controller: controller)
        }
    }
}
struct SettingsView: View {
    @ObservedObject var controller: WorkspaceController
    
    var body: some View {
        Form {
            Slider(
                value: Binding(
                    get: { controller.lineSpacing },
                    set: { controller.updateLineSpacing($0) }
                ),
                in: 1.0...2.2
            ) {
                Text("Line Spacing:")
            }
            .disabled(controller.workspace == nil)
        }
        .padding(20)
        .frame(width: 350, height: 100)
    }
}
