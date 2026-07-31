//
//  todoMarkdownApp.swift
//  todoMarkdown
//
//  Created by Leo Y on 2026/3/16.
//

#if os(macOS)
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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    performUndo()
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    performRedo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(controller: controller)
        }
    }

    private func performUndo() {
        if !NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) {
            controller.undoSelectedPageChange()
        }
    }

    private func performRedo() {
        if !NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) {
            controller.redoSelectedPageChange()
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
#endif
