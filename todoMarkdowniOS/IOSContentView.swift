import SwiftUI

struct IOSContentView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var navigationPath = NavigationPath()
    @State private var isShowingRenameSheet = false
    @State private var renameTitle = ""
    @State private var pageBeingRenamed: UUID?
    @State private var opensPageAfterRenaming = false
    @State private var isArchiveExpanded = false

    var body: some View {
        Group {
            if controller.workspace == nil {
                ContentUnavailableView {
                    Label("iCloud 工作区不可用", systemImage: "icloud.slash")
                } description: {
                    Text("请登录 iCloud 并启用 iCloud Drive 后重试。")
                } actions: {
                    Button("重新连接", action: controller.chooseWorkspace)
                }
            } else {
                workspaceView
            }
        }
        .task { controller.performInitialSetup() }
        .alert(
            "工作区错误",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingRenameSheet, onDismiss: finishRenameIfNeeded) {
            RenamePageSheet(
                title: $renameTitle,
                isNewPage: opensPageAfterRenaming,
                onCancel: cancelRename,
                onSave: saveRename
            )
        }
    }

    private var workspaceView: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CompactSearchField(text: $controller.searchText)

                    if controller.activeFiles.isEmpty {
                        emptyState
                    } else {
                        pageSection
                    }

                    if !controller.archivedFiles.isEmpty {
                        archivedSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createPage) {
                        Label("新建页面", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { pageID in
                PageEditorScreen(controller: controller, pageID: pageID)
            }
        }
    }

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "页面", count: controller.activeFiles.count)

            VStack(spacing: 0) {
                ForEach(controller.activeFiles) { page in
                    NavigationLink(value: page.id) {
                        PageListRow(page: page, showsChevron: true)
                            .padding(.trailing, 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button("归档", systemImage: "archivebox", role: .destructive) {
                                controller.archivePage(id: page.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 44)
                        }
                    }

                    if page.id != controller.activeFiles.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isArchiveExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    SectionHeader(title: "归档", count: controller.archivedFiles.count)
                    Image(systemName: isArchiveExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isArchiveExpanded {
                VStack(spacing: 0) {
                    ForEach(controller.archivedFiles) { page in
                        HStack(spacing: 8) {
                            PageListRow(page: page, showsChevron: false)
                                .foregroundStyle(.secondary)

                            Menu {
                                Button("恢复", systemImage: "arrow.uturn.backward") {
                                    controller.restorePage(id: page.id)
                                }
                                Button("永久删除", systemImage: "trash", role: .destructive) {
                                    controller.softDeleteArchivedPage(id: page.id)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 44)
                            }
                        }

                        if page.id != controller.archivedFiles.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有页面", systemImage: "doc.badge.plus")
        } description: {
            Text("新建一个页面，开始记录你的待办。")
        } actions: {
            Button("新建页面", action: createPage)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private func createPage() {
        guard let id = controller.createPage() else { return }
        pageBeingRenamed = id
        renameTitle = controller.pageTitle(for: id)
        opensPageAfterRenaming = true
        isShowingRenameSheet = true
    }

    private func saveRename() {
        guard let pageBeingRenamed else { return }
        controller.renamePage(id: pageBeingRenamed, to: renameTitle)
        completeRename(opening: pageBeingRenamed)
    }

    private func cancelRename() {
        let pageID = opensPageAfterRenaming ? pageBeingRenamed : nil
        completeRename(opening: pageID)
    }

    private func finishRenameIfNeeded() {
        guard pageBeingRenamed != nil else { return }
        cancelRename()
    }

    private func completeRename(opening pageID: UUID?) {
        isShowingRenameSheet = false
        pageBeingRenamed = nil
        renameTitle = ""
        opensPageAfterRenaming = false
        if let pageID {
            navigationPath.append(pageID)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number)
        }
    }
}

private struct CompactSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索标题和内容", text: $text)
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PageListRow: View {
    let page: WorkspacePage
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(page.trimmedTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(page.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if page.taskCount > 0 {
                Text("\(page.taskCount) 项")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct PageEditorScreen: View {
    @ObservedObject var controller: WorkspaceController
    let pageID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRenameSheet = false
    @State private var renameTitle = ""

    private var page: WorkspacePage? {
        controller.files.first(where: { $0.id == pageID })
    }

    var body: some View {
        Group {
            if let page {
                editorContent(for: page)
            } else {
                ContentUnavailableView("页面已不存在", systemImage: "doc.badge.minus")
            }
        }
        .task(id: pageID) {
            controller.selectedFileID = pageID
        }
        .navigationTitle(page?.trimmedTitle ?? "页面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if controller.editorMode == .preview {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                pageActions
            }
        }
        .sheet(isPresented: $isShowingRenameSheet) {
            RenamePageSheet(
                title: $renameTitle,
                isNewPage: false,
                onCancel: { isShowingRenameSheet = false },
                onSave: renameCurrentPage
            )
        }
    }

    @ViewBuilder
    private func editorContent(for page: WorkspacePage) -> some View {
        if controller.selectedFileID != pageID || controller.isLoadingSelectedContent || !controller.selectedPageIsLoaded {
            ProgressView("正在打开…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.editorMode == .edit {
            TextEditor(text: Binding(
                get: { controller.loadedContent },
                set: { controller.updateSelectedPageContent($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorModeControl(selection: $controller.editorMode)
            }
        } else {
            IOSPreviewPane(
                content: controller.loadedContent,
                onUpdateContent: { controller.updateSelectedPageContent($0, registersUndo: true) }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorModeControl(selection: $controller.editorMode)
            }
        }
    }

    private var pageActions: some View {
        Menu {
            if let page, page.isArchived {
                Button("恢复页面", systemImage: "arrow.uturn.backward") {
                    controller.restorePage(id: pageID)
                }
                Button("永久删除", systemImage: "trash", role: .destructive) {
                    controller.softDeleteArchivedPage(id: pageID)
                    dismiss()
                }
            } else {
                Button("重命名", systemImage: "pencil") {
                    renameTitle = page?.title ?? ""
                    isShowingRenameSheet = true
                }
                Button("归档", systemImage: "archivebox", role: .destructive) {
                    controller.archivePage(id: pageID)
                    dismiss()
                }
            }
        } label: {
            Label("更多操作", systemImage: "ellipsis.circle")
        }
    }

    private func renameCurrentPage() {
        controller.renamePage(id: pageID, to: renameTitle)
        isShowingRenameSheet = false
    }
}

private struct EditorModeControl: View {
    @Binding var selection: EditorMode

    var body: some View {
        Picker("模式", selection: $selection) {
            Label("编辑", systemImage: "pencil.line")
                .tag(EditorMode.edit)
            Label("预览", systemImage: "eye")
                .tag(EditorMode.preview)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct RenamePageSheet: View {
    @Binding var title: String
    let isNewPage: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(isNewPage ? "给新页面起个名字" : "页面名称") {
                    TextField("未命名页面", text: $title)
                        .focused($isTitleFocused)
                }
            }
            .navigationTitle(isNewPage ? "新建页面" : "重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onSave)
                }
            }
            .onAppear { isTitleFocused = true }
        }
        .presentationDetents([.height(220)])
    }
}

private struct IOSPreviewPane: View {
    let content: String
    let onUpdateContent: (String) -> Void

    private var lines: [PreviewLine] { PreviewLineCodec.decode(content) }

    var body: some View {
        if lines.isEmpty {
            ContentUnavailableView {
                Label("还没有内容", systemImage: "text.cursor")
            } description: {
                Text("切换到编辑模式开始记录，或直接插入一个待办。")
            } actions: {
                Button("插入待办") {
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            switch line.kind {
            case let .heading(level, text):
                Text(displayText(text, fallback: "未命名标题"))
                    .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
            case let .todo(isCompleted, text):
                Button(action: onToggleTodo) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                Text(displayText(text, fallback: "新待办"))
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
                    Button("在下方插入待办", action: onInsertBelow)
                    Button("移入归档", action: onArchive)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func displayText(_ rawText: String, fallback: String) -> String {
        let text = PreviewMentionParser.parse(rawText).displayText
        return text.isEmpty ? fallback : text
    }
}
