import SwiftUI

@main
struct todoMarkdowniOSApp: App {
    @StateObject private var controller = WorkspaceController()

    var body: some Scene {
        WindowGroup {
            IOSContentView(controller: controller)
        }
    }
}
