//
//  ContentView.swift
//  todoMarkdown
//
//  Created by Leo Y on 2026/3/16.
//

#if os(macOS)
import AppKit
import SwiftUI

private enum EditorPreviewTypography {
    static let fontSize: CGFloat = 14

    static let appKitFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    static let appKitEmphasisFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
    static let swiftUIFont = Font.system(size: fontSize, weight: .regular, design: .monospaced)
    static let swiftUIEmphasisFont = Font.system(size: fontSize, weight: .semibold, design: .monospaced)

    static func lineSpacing(for value: Double) -> CGFloat {
        CGFloat((value - 1.0) * 5)
    }

    static func paragraphSpacing(for value: Double) -> CGFloat {
        4 + CGFloat((value - 1.0) * 8)
    }

    static func rowVerticalPadding(for value: Double) -> CGFloat {
        paragraphSpacing(for: value) / 2
    }
}

struct ContentView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var renamingFileID: UUID?
    @State private var renamingTitle = ""
    @State private var isArchiveExpanded = false
    @FocusState private var focusedTitleFieldID: UUID?

    var body: some View {
        Group {
            if controller.workspace == nil {
                WelcomeWorkspaceView(openAction: controller.chooseWorkspace)
            } else {
                workspaceView
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if controller.workspace != nil {
                    Picker("Mode", selection: $controller.editorMode) {
                        ForEach(EditorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .disabled(controller.selectedPage == nil)
                }
            }
        }
        .task {
            controller.performInitialSetup()
        }
        .onChange(of: focusedTitleFieldID) { oldValue, newValue in
            if let oldValue, oldValue != newValue {
                finishRenaming(fileID: oldValue)
            }
        }
        .alert(
            "Workspace Error",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        controller.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                controller.errorMessage = nil
            }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    private var workspaceView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $controller.selectedFileID) {
                    ForEach(controller.activeFiles) { file in
                        activeSidebarRow(for: file)
                    }
                    .onDelete(perform: controller.archivePages)
                    .onMove(perform: controller.movePages)
                }
                .listStyle(.sidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                archiveDockedView
            }
            .navigationTitle(controller.workspaceTitle)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .searchable(text: $controller.searchText, placement: .sidebar, prompt: "Search all text")
            .toolbar {
                ToolbarItemGroup {
                    Button(action: createPage) {
                        Label("New Page", systemImage: "plus")
                    }

                    Button(action: renameSelectedPage) {
                        Label("Rename Page", systemImage: "pencil")
                    }
                    .disabled(controller.selectedPage == nil)
                }
            }
            .overlay {
                if controller.files.isEmpty {
                    ContentUnavailableView {
                        Label("No Pages", systemImage: "doc.text")
                    } description: {
                        Text("Create a page in this workspace to start writing.")
                    } actions: {
                        Button("Create First Page", action: createPage)
                    }
                }
            }
        } detail: {
            Group {
                if let selectedPage = controller.selectedPage {
                    if controller.isLoadingSelectedContent || !controller.selectedPageIsLoaded {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading \(selectedPage.trimmedTitle)...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                    } else {
                        switch controller.editorMode {
                        case .edit:
                            EditorPane(text: Binding(
                                get: { controller.loadedContent },
                                set: { controller.updateSelectedPageContent($0) }
                            ), lineSpacing: controller.lineSpacing, pageUndoManager: controller.undoManager(for: selectedPage.id))
                        case .preview:
                            PreviewPane(
                                content: controller.loadedContent,
                                lineSpacing: controller.lineSpacing,
                                onUpdateContent: { controller.updateSelectedPageContent($0, registersUndo: true) }
                            )
                        }
                    }
                } else if controller.files.isEmpty {
                    ContentUnavailableView {
                        Label("Empty Workspace", systemImage: "folder")
                    } description: {
                        Text("This workspace does not contain any todo pages yet.")
                    } actions: {
                        Button("Create Page", action: createPage)
                    }
                } else {
                    ContentUnavailableView("Select a Page", systemImage: "sidebar.left")
                }
            }
            .navigationTitle(windowTitle)
            .navigationSubtitle(windowSubtitle)
        }

    }

    private var windowTitle: String {
        controller.selectedPage?.trimmedTitle ?? controller.workspaceTitle
    }

    private var windowSubtitle: String {
        if controller.selectedPage != nil, controller.workspace != nil {
            return controller.workspaceTitle
        }
        return ""
    }

    private func createPage() {
        if let fileID = controller.createPage() {
            beginRenaming(fileID)
        }
    }

    private func renameSelectedPage() {
        guard let selectedFileID = controller.selectedFileID else { return }
        beginRenaming(selectedFileID)
    }

    private func beginRenaming(_ fileID: UUID) {
        renamingFileID = fileID
        renamingTitle = controller.pageTitle(for: fileID)

        DispatchQueue.main.async {
            focusedTitleFieldID = fileID
        }
    }

    private func finishRenaming(fileID: UUID) {
        guard renamingFileID == fileID else { return }
        controller.renamePage(id: fileID, to: renamingTitle)
        renamingFileID = nil
        if focusedTitleFieldID == fileID {
            focusedTitleFieldID = nil
        }
    }

    private func indexOfActivePage(withID fileID: UUID) -> Int {
        controller.activeFiles.firstIndex(where: { $0.id == fileID }) ?? 0
    }

    private var archiveDockedView: some View {
        VStack(spacing: 0) {
            if isArchiveExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if controller.archivedFiles.isEmpty {
                            Text("No archived pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(controller.archivedFiles) { file in
                                archivedSidebarRow(for: file)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
                .padding(.top, 8)

                Divider()
            }

            Button {
                isArchiveExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isArchiveExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.tertiary)
                    Label("Archive", systemImage: "archivebox")
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityLabel("Archive")
            .accessibilityValue(isArchiveExpanded ? "Expanded" : "Collapsed")
        }
    }

    private func activeSidebarRow(for file: WorkspacePage) -> AnyView {
        AnyView(
            SidebarFileRow(
                file: file,
                isRenaming: renamingFileID == file.id,
                renamingTitle: $renamingTitle,
                focusedTitleFieldID: $focusedTitleFieldID,
                onCommit: {
                    finishRenaming(fileID: file.id)
                }
            )
            .tag(file.id)
            .contextMenu {
                Button("Rename") {
                    beginRenaming(file.id)
                }
                Button("Archive") {
                    controller.archivePages(offsets: IndexSet(integer: indexOfActivePage(withID: file.id)))
                }
            }
            .onTapGesture {
                controller.selectedFileID = file.id
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                beginRenaming(file.id)
            })
        )
    }

    private func archivedSidebarRow(for file: WorkspacePage) -> AnyView {
        AnyView(
            SidebarFileRow(
                file: file,
                isRenaming: false,
                renamingTitle: $renamingTitle,
                focusedTitleFieldID: $focusedTitleFieldID,
                onCommit: {}
            )
            .tag(file.id)
            .contextMenu {
                Button("Restore") {
                    controller.restorePage(id: file.id)
                }
                Button("Delete", role: .destructive) {
                    controller.softDeleteArchivedPage(id: file.id)
                }
            }
            .onTapGesture {
                controller.selectedFileID = file.id
            }
        )
    }
}

private struct WelcomeWorkspaceView: View {
    let openAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Choose a Workspace", systemImage: "folder.badge.plus")
        } description: {
            Text("Select a folder to store todo pages as Markdown files with workspace metadata in JSON.")
        } actions: {
            Button("Open Workspace...", action: openAction)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct SidebarFileRow: View {
    let file: WorkspacePage
    let isRenaming: Bool
    @Binding var renamingTitle: String
    let focusedTitleFieldID: FocusState<UUID?>.Binding
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            if isRenaming {
                TextField("Untitled", text: $renamingTitle)
                    .textFieldStyle(.plain)
                    .focused(focusedTitleFieldID, equals: file.id)
                    .onSubmit(onCommit)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.trimmedTitle)
                        .lineLimit(1)

                    Text(file.updatedAt, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(file.taskCount, format: .number)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    )
                    .accessibilityLabel("\(file.taskCount) tasks")
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct EditorPane: View {
    @Binding var text: String
    var lineSpacing: Double
    let pageUndoManager: UndoManager

    var body: some View {
        MentionEditorTextView(text: $text, lineSpacing: lineSpacing, pageUndoManager: pageUndoManager)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PreviewPane: View {
    let content: String
    let lineSpacing: Double
    let onUpdateContent: (String) -> Void

    private var lines: [PreviewLine] {
        PreviewLineCodec.decode(content)
    }

    var body: some View {
        Group {
            if lines.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Preview", systemImage: "eye")
                } description: {
                    Text("Add text in edit mode or create a todo item directly here.")
                } actions: {
                    Button("Insert First Todo") {
                        onUpdateContent(PreviewLineCodec.insertTodo(in: content, after: nil))
                    }
                }
            } else {
                List {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        PreviewLineRow(
                            line: line,
                            onToggleTodo: {
                                onUpdateContent(PreviewLineCodec.toggleTodo(in: content, at: index))
                            },
                            onInsertBelow: {
                                onUpdateContent(PreviewLineCodec.insertTodo(in: content, after: index))
                            },
                            lineSpacing: lineSpacing,
                            onArchive: { onUpdateContent(PreviewLineCodec.archiveLine(in: content, at: index)) }
                        )
                    }
                    .onMove { source, destination in
                        onUpdateContent(
                            PreviewLineCodec.moveLines(
                                in: content,
                                fromOffsets: source,
                                toOffset: destination
                            )
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PreviewLineRow: View {
    let line: PreviewLine
    let onToggleTodo: () -> Void
    let onInsertBelow: () -> Void
    let lineSpacing: Double
    let onArchive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content
            AssigneeColumn(assignees: line.mentionContent.assignees)

            Spacer(minLength: 12)

            if !line.hidesPreviewActions {
                HStack(spacing: 8) {
                    Button(action: onInsertBelow) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(.borderless)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, previewVerticalPadding)
        .listRowSeparator(hidesBottomSeparator ? .hidden : .visible, edges: .bottom)
    }

    private var previewLineSpacing: CGFloat {
        EditorPreviewTypography.lineSpacing(for: lineSpacing)
    }

    private var previewVerticalPadding: CGFloat {
        EditorPreviewTypography.rowVerticalPadding(for: lineSpacing)
    }

    private var hidesBottomSeparator: Bool {
        line.mentionContent.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var content: some View {
        switch line.kind {
        case let .heading(_, text):
            styledText(for: text, fallback: "Untitled Heading")
                .lineSpacing(previewLineSpacing)
        case let .todo(isCompleted, text):
            HStack(alignment: .top, spacing: 10) {
                Button(action: onToggleTodo) {
                    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)

                styledText(
                    for: text,
                    fallback: "New Todo",
                    plainColor: isCompleted ? Color.secondary : Color.primary
                )
                    .strikethrough(isCompleted)
                    .lineSpacing(previewLineSpacing)
            }
        case let .paragraph(text):
            styledText(for: text, fallback: " ")
                .lineSpacing(previewLineSpacing)
                .textSelection(.enabled)
        case .empty:
            Text(" ")
                .font(EditorPreviewTypography.swiftUIFont)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayText(for rawText: String, fallback: String) -> String {
        let text = PreviewMentionParser.parse(rawText).displayText
        return text.isEmpty ? fallback : text
    }

    private func styledText(
        for rawText: String,
        fallback: String,
        plainColor: Color? = nil
    ) -> Text {
        let displayText = displayText(for: rawText, fallback: fallback)
        let segments = PreviewInlineParser.segments(in: displayText)

        guard !segments.isEmpty else {
            return styledSegmentText(
                PreviewInlineSegment(text: displayText, kind: .plain),
                plainColor: plainColor
            )
        }

        return segments.reduce(Text("")) { partial, segment in
            partial + styledSegmentText(segment, plainColor: plainColor)
        }
    }

    private func styledSegmentText(
        _ segment: PreviewInlineSegment,
        plainColor: Color?
    ) -> Text {
        switch segment.kind {
        case .plain:
            if let plainColor {
                return Text(segment.text)
                    .font(EditorPreviewTypography.swiftUIFont)
                    .foregroundColor(plainColor)
            }
            return Text(segment.text)
                .font(EditorPreviewTypography.swiftUIFont)
        case .dateTag:
            return Text(segment.text)
                .font(EditorPreviewTypography.swiftUIEmphasisFont)
                .foregroundColor(Color(nsColor: .systemOrange))
        case .remarkTag:
            return Text(segment.text)
                .font(EditorPreviewTypography.swiftUIFont)
                .foregroundColor(Color(nsColor: .systemGray))
        }
    }
}

private struct AssigneeColumn: View {
    let assignees: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if assignees.isEmpty {
                Text(" ")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(assignees, id: \.self) { assignee in
                    Text("@\(assignee)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .systemPink))
                        )
                }
            }
        }
        .frame(width: 170, alignment: .leading)
    }
}

private struct MentionEditorTextView: NSViewRepresentable {
    @Binding var text: String
    var lineSpacing: Double
    let pageUndoManager: UndoManager

    private var renderedLineSpacing: CGFloat {
        EditorPreviewTypography.lineSpacing(for: lineSpacing)
    }

    private var renderedParagraphSpacing: CGFloat {
        EditorPreviewTypography.paragraphSpacing(for: lineSpacing)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = PageScopedTextView(frame: .zero, textContainer: textContainer)
        textView.pageUndoManager = pageUndoManager
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.font = Self.baseFont
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.systemPink
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        context.coordinator.applyHighlight(to: textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        (textView as? PageScopedTextView)?.pageUndoManager = pageUndoManager
        context.coordinator.parent = self

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            context.coordinator.isUpdatingView = true
            textView.undoManager?.disableUndoRegistration()
            textView.string = text
            textView.undoManager?.enableUndoRegistration()
            context.coordinator.applyHighlight(to: textView)
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingView = false
            return
        }

        context.coordinator.applyHighlightIfNeeded(to: textView)
    }

    private static let baseFont = EditorPreviewTypography.appKitFont
    private static let mentionFont = EditorPreviewTypography.appKitEmphasisFont

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MentionEditorTextView
        var isUpdatingView = false
        private var lastAppliedLineSpacing: Double?
        private var pendingHighlightWorkItem: DispatchWorkItem?

        init(_ parent: MentionEditorTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingView,
                  let textView = notification.object as? NSTextView else { return }

            parent.text = textView.string
            scheduleHighlight(to: textView)
        }

        func applyHighlightIfNeeded(to textView: NSTextView) {
            guard lastAppliedLineSpacing != parent.lineSpacing else { return }
            applyHighlight(to: textView)
        }

        private func scheduleHighlight(to textView: NSTextView) {
            pendingHighlightWorkItem?.cancel()

            let expectedString = textView.string
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self,
                      !self.isUpdatingView,
                      let textView,
                      textView.string == expectedString else { return }

                self.applyHighlight(to: textView)
            }

            pendingHighlightWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func applyHighlight(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            pendingHighlightWorkItem?.cancel()

            let fullRange = NSRange(location: 0, length: textStorage.length)
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: MentionEditorTextView.baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineSpacing = parent.renderedLineSpacing
                    paragraph.paragraphSpacing = parent.renderedParagraphSpacing
                    return paragraph
                }()
            ]
            let selectedRanges = clampedRanges(textView.selectedRanges, upperBound: textStorage.length)

            textStorage.beginEditing()
            if fullRange.length > 0 {
                textStorage.setAttributes(baseAttributes, range: fullRange)
            }

            if textView.string.utf16.count <= 12_000 {
                for range in PreviewMentionParser.mentionRanges(in: textView.string) {
                    textStorage.addAttributes(
                        [
                            .font: MentionEditorTextView.mentionFont,
                            .foregroundColor: NSColor.systemPink,
                            .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.18)
                        ],
                        range: range
                    )
                }

                for range in PreviewInlineParser.dateTagRanges(in: textView.string) {
                    textStorage.addAttributes(
                        [
                            .font: MentionEditorTextView.mentionFont,
                            .foregroundColor: NSColor.systemGreen,
                            .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.12)
                        ],
                        range: range
                    )
                }
                
                for range in PreviewInlineParser.remarkRanges(in: textView.string) {
                    textStorage.addAttributes(
                        [
                            .font: MentionEditorTextView.mentionFont,
                            .foregroundColor: NSColor.systemGray,
                            .backgroundColor: NSColor.systemGray.withAlphaComponent(0.12)
                        ],
                        range: range
                    )
                }
            }

            textStorage.endEditing()
            textView.typingAttributes = baseAttributes
            textView.selectedRanges = selectedRanges
            textView.layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            textView.layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
            textView.needsDisplay = true
            lastAppliedLineSpacing = parent.lineSpacing
        }

        private func clampedRanges(_ ranges: [NSValue], upperBound: Int) -> [NSValue] {
            let clamped = ranges.map { value in
                let range = value.rangeValue
                let location = min(max(0, range.location), upperBound)
                let maxLength = upperBound - location
                return NSValue(range: NSRange(location: location, length: min(range.length, maxLength)))
            }

            return clamped.isEmpty ? [NSValue(range: NSRange(location: upperBound, length: 0))] : clamped
        }
    }
}

private final class PageScopedTextView: NSTextView {
    var pageUndoManager: UndoManager?

    override var undoManager: UndoManager? {
        pageUndoManager ?? super.undoManager
    }
}
#endif
