import SwiftUI

struct IOSContentView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var isShowingRename = false
    @State private var renameTitle = ""
    @State private var pageBeingRenamed: UUID?

    var body: some View {
        Group {
            if controller.workspace == nil {
                ContentUnavailableView {
                    Label("iCloud Workspace Unavailable", systemImage: "icloud.slash")
                } description: {
                    Text("Sign in to iCloud and enable iCloud Drive, then try again.")
                } actions: {
                    Button("Try Again", action: controller.chooseWorkspace)
                }
            } else {
                workspaceView
            }
        }
        .task { controller.performInitialSetup() }
        .alert(
            "Workspace Error",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .alert("Rename Page", isPresented: $isShowingRename) {
            TextField("Page title", text: $renameTitle)
            Button("Cancel", role: .cancel) { pageBeingRenamed = nil }
            Button("Save") { saveRename() }
        }
    }

    private var workspaceView: some View {
        NavigationSplitView {
            List(selection: $controller.selectedFileID) {
                Section("Pages") {
                    ForEach(controller.activeFiles) { page in
                        Button {
                            controller.selectedFileID = page.id
                        } label: {
                            PageRow(page: page)
                        }
                        .tag(page.id)
                        .swipeActions {
                            Button(role: .destructive) {
                                archive(page)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                    .onDelete(perform: controller.archivePages)
                    .onMove(perform: controller.movePages)
                }

                if !controller.archivedFiles.isEmpty {
                    Section("Archive") {
                        ForEach(controller.archivedFiles) { page in
                            PageRow(page: page)
                                .foregroundStyle(.secondary)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        controller.restorePage(id: page.id)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        controller.softDeleteArchivedPage(id: page.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle(controller.workspaceTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createPage) {
                        Label("New Page", systemImage: "plus")
                    }
                }
            }
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        if let page = controller.selectedPage {
            Group {
                if controller.isLoadingSelectedContent || !controller.selectedPageIsLoaded {
                    ProgressView("Loading \(page.trimmedTitle)...")
                } else if controller.editorMode == .edit {
                    TextEditor(text: Binding(
                        get: { controller.loadedContent },
                        set: { controller.updateSelectedPageContent($0) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                } else {
                    IOSPreviewPane(
                        content: controller.loadedContent,
                        onUpdateContent: { controller.updateSelectedPageContent($0, registersUndo: true) }
                    )
                }
            }
            .navigationTitle(page.trimmedTitle)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $controller.editorMode) {
                        ForEach(EditorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 210)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startRename(page)
                    } label: {
                        Label("Rename Page", systemImage: "pencil")
                    }
                }
            }
        } else {
            ContentUnavailableView("Select a Page", systemImage: "sidebar.left")
        }
    }

    private func createPage() {
        guard let id = controller.createPage() else { return }
        pageBeingRenamed = id
        renameTitle = controller.pageTitle(for: id)
        isShowingRename = true
    }

    private func archive(_ page: WorkspacePage) {
        guard let index = controller.activeFiles.firstIndex(where: { $0.id == page.id }) else { return }
        controller.archivePages(offsets: IndexSet(integer: index))
    }

    private func startRename(_ page: WorkspacePage) {
        pageBeingRenamed = page.id
        renameTitle = page.title
        isShowingRename = true
    }

    private func saveRename() {
        if let pageBeingRenamed {
            controller.renamePage(id: pageBeingRenamed, to: renameTitle)
        }
        pageBeingRenamed = nil
    }
}

private struct PageRow: View {
    let page: WorkspacePage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.trimmedTitle)
                    .lineLimit(1)
                Text(page.updatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(page.taskCount, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct IOSPreviewPane: View {
    let content: String
    let onUpdateContent: (String) -> Void

    private var lines: [PreviewLine] { PreviewLineCodec.decode(content) }

    var body: some View {
        if lines.isEmpty {
            ContentUnavailableView {
                Label("Nothing to Preview", systemImage: "eye")
            } description: {
                Text("Add text in edit mode or create a todo item here.")
            } actions: {
                Button("Insert First Todo") {
                    onUpdateContent(PreviewLineCodec.insertTodo(in: content, after: nil))
                }
            }
        } else {
            List {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    IOSPreviewLineRow(
                        line: line,
                        onToggleTodo: {
                            onUpdateContent(PreviewLineCodec.toggleTodo(in: content, at: index))
                        },
                        onInsertBelow: {
                            onUpdateContent(PreviewLineCodec.insertTodo(in: content, after: index))
                        },
                        onArchive: {
                            onUpdateContent(PreviewLineCodec.archiveLine(in: content, at: index))
                        }
                    )
                }
                .onMove { source, destination in
                    onUpdateContent(PreviewLineCodec.moveLines(in: content, fromOffsets: source, toOffset: destination))
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct IOSPreviewLineRow: View {
    let line: PreviewLine
    let onToggleTodo: () -> Void
    let onInsertBelow: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch line.kind {
            case let .heading(level, text):
                Text(displayText(text, fallback: "Untitled Heading"))
                    .font(level == 1 ? .title2.bold() : level == 2 ? .headline : .subheadline.bold())
            case let .todo(isCompleted, text):
                Button(action: onToggleTodo) {
                    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                Text(displayText(text, fallback: "New Todo"))
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
            case let .paragraph(text):
                Text(displayText(text, fallback: " "))
                    .textSelection(.enabled)
            case .empty:
                Text(" ")
            }
            Spacer(minLength: 8)
            if !line.hidesPreviewActions {
                Menu {
                    Button("Insert Todo Below", action: onInsertBelow)
                    Button("Archive Line", action: onArchive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func displayText(_ rawText: String, fallback: String) -> String {
        let text = PreviewMentionParser.parse(rawText).displayText
        return text.isEmpty ? fallback : text
    }
}
