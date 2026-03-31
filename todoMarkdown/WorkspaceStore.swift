//
//  WorkspaceStore.swift
//  todoMarkdown
//
//  Created by Codex on 2026/3/16.
//

import AppKit
import Combine
import Foundation
import UserNotifications

enum WorkspaceError: LocalizedError {
    case invalidWorkspaceURL
    case pageNotFound

    var errorDescription: String? {
        switch self {
        case .invalidWorkspaceURL:
            return "The selected workspace folder is invalid."
        case .pageNotFound:
            return "The selected page could not be found."
        }
    }
}

protocol WorkspaceBookmarkPersisting {
    func restoreWorkspaceURL() throws -> URL?
    func saveWorkspaceURL(_ url: URL) throws
    func clearWorkspaceURL()
}

struct UserDefaultsWorkspaceBookmarkStore: WorkspaceBookmarkPersisting {
    private let defaults: UserDefaults
    private let bookmarkKey = "workspaceBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreWorkspaceURL() throws -> URL? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try saveWorkspaceURL(url)
        }

        return url
    }

    func saveWorkspaceURL(_ url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: bookmarkKey)
    }

    func clearWorkspaceURL() {
        defaults.removeObject(forKey: bookmarkKey)
    }
}

struct WorkspaceStore {
    static let manifestFileName = "workspace.json"

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func loadWorkspace(at rootURL: URL) throws -> WorkspaceSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError.invalidWorkspaceURL
        }

        let manifestURL = manifestURL(for: rootURL)
        let manifest: WorkspaceManifest

        if fileManager.fileExists(atPath: manifestURL.path) {
            manifest = try loadManifest(at: rootURL)
        } else {
            manifest = try bootstrapManifest(at: rootURL)
            try saveManifest(manifest, at: rootURL)
        }

        let pages = try manifest.files
            .sorted(using: KeyPathComparator(\.sortOrder))
            .map { metadata in
                if metadata.isDeleted {
                    return WorkspacePage(manifestFile: metadata, content: "")
                }
                let pageURL = rootURL.appending(path: metadata.fileName)
                if !fileManager.fileExists(atPath: pageURL.path) {
                    try savePageContent("", fileName: metadata.fileName, at: rootURL)
                }
                let content = try String(contentsOf: pageURL, encoding: .utf8)
                return WorkspacePage(manifestFile: metadata, content: content)
            }

        return WorkspaceSnapshot(rootURL: rootURL, manifest: manifest, pages: pages)
    }

    func saveManifest(_ manifest: WorkspaceManifest, at rootURL: URL) throws {
        let manifestURL = manifestURL(for: rootURL)
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    func savePageContent(_ content: String, fileName: String, at rootURL: URL) throws {
        let pageURL = rootURL.appending(path: fileName)
        try content.write(to: pageURL, atomically: true, encoding: .utf8)
    }

    func loadPageContent(fileName: String, at rootURL: URL) throws -> String {
        let pageURL = rootURL.appending(path: fileName)
        if !fileManager.fileExists(atPath: pageURL.path) {
            try savePageContent("", fileName: fileName, at: rootURL)
            return ""
        }
        return try String(contentsOf: pageURL, encoding: .utf8)
    }

    func createPage(_ page: WorkspacePage, at rootURL: URL) throws {
        try savePageContent(page.content, fileName: page.fileName, at: rootURL)
    }

    func deletePage(fileName: String, at rootURL: URL) throws {
        let pageURL = rootURL.appending(path: fileName)
        if fileManager.fileExists(atPath: pageURL.path) {
            try fileManager.removeItem(at: pageURL)
        }
    }

    private func loadManifest(at rootURL: URL) throws -> WorkspaceManifest {
        let data = try Data(contentsOf: manifestURL(for: rootURL))
        return try decoder.decode(WorkspaceManifest.self, from: data)
    }

    private func bootstrapManifest(at rootURL: URL) throws -> WorkspaceManifest {
        let markdownFiles = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let imported = markdownFiles.enumerated().map { index, url in
            WorkspaceManifestFile(
                id: UUID(),
                fileName: url.lastPathComponent,
                title: url.deletingPathExtension().lastPathComponent,
                sortOrder: index,
                isArchived: false,
                isDeleted: false,
                createdAt: .now,
                updatedAt: .now
            )
        }

        return WorkspaceManifest(files: imported)
    }

    private func manifestURL(for rootURL: URL) -> URL {
        rootURL.appending(path: Self.manifestFileName)
    }
}

@MainActor
final class WorkspaceController: ObservableObject {
    @Published private(set) var workspace: WorkspaceSnapshot?
    @Published var selectedFileID: UUID? {
        didSet {
            guard selectedFileID != oldValue else { return }
            persistSelection()
            loadSelectedPageContentAsync()
        }
    }
    @Published var editorMode: EditorMode = .edit
    @Published var searchText: String = ""
    @Published var errorMessage: String?
    @Published private(set) var isLoadingSelectedContent = false
    @Published private(set) var loadedContent = ""
    @Published private(set) var loadedContentPageID: UUID?

    private let store: WorkspaceStore
    private let bookmarkStore: WorkspaceBookmarkPersisting
    private let reminderScheduler: ReminderScheduling
    private let ioQueue = DispatchQueue(label: "todoMarkdown.workspace.io", qos: .utility)
    private var accessedWorkspaceURL: URL?
    private var performedInitialSetup = false
    private var pendingSelectionPersistWorkItem: DispatchWorkItem?
    private var pendingAutosaveWorkItems: [UUID: DispatchWorkItem] = [:]
    private var selectedContentLoadSequence: Int = 0
    private var pageUndoManagers: [UUID: UndoManager] = [:]

    init(
        store: WorkspaceStore? = nil,
        bookmarkStore: WorkspaceBookmarkPersisting? = nil,
        reminderScheduler: ReminderScheduling? = nil
    ) {
        self.store = store ?? WorkspaceStore()
        self.bookmarkStore = bookmarkStore ?? UserDefaultsWorkspaceBookmarkStore()
        self.reminderScheduler = reminderScheduler ?? UserNotificationReminderScheduler()
    }

    var files: [WorkspacePage] {
        workspace?.orderedPages.filter { !$0.isDeleted } ?? []
    }

    var activeFiles: [WorkspacePage] {
        filteredFiles.filter { !$0.isArchived }
    }

    var archivedFiles: [WorkspacePage] {
        filteredFiles.filter(\.isArchived)
    }

    var lineSpacing: Double {
        workspace?.manifest.settings.lineSpacing ?? 1.35
    }

    var workspaceTitle: String {
        workspace?.rootURL.lastPathComponent ?? "Workspace"
    }

    var selectedPage: WorkspacePage? {
        guard let selectedFileID else { return nil }
        return files.first(where: { $0.id == selectedFileID })
    }

    var selectedPageIsLoaded: Bool {
        guard let selectedFileID else { return false }
        return loadedContentPageID == selectedFileID
    }

    func undoManager(for pageID: UUID) -> UndoManager {
        if let existing = pageUndoManagers[pageID] {
            return existing
        }
        let manager = UndoManager()
        manager.levelsOfUndo = 200
        manager.groupsByEvent = true
        pageUndoManagers[pageID] = manager
        return manager
    }

    func performInitialSetup() {
        guard !performedInitialSetup else { return }
        performedInitialSetup = true

        if isRunningUnderTests {
            _ = restoreWorkspaceIfPossible()
            return
        }

        if !restoreWorkspaceIfPossible() {
            chooseWorkspace()
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        panel.message = "Choose a folder to use as your todo workspace."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(at: url, persistBookmark: true)
    }

    func createPage() -> UUID? {
        guard var workspace else { return nil }

        let page = WorkspacePage(
            title: suggestedTitle(in: workspace.pages),
            sortOrder: workspace.pages.count
        )
        workspace.pages.append(page)
        workspace.manifest.files.append(page.manifestFile)

        do {
            try store.createPage(page, at: workspace.rootURL)
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
            selectedFileID = page.id
            return page.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renamePage(id: UUID, to newTitle: String) {
        mutatePage(id: id) { page in
            page.title = sanitizeTitle(newTitle)
            page.updatedAt = .now
        }
    }

    func deleteSelectedPage() {
        guard let selectedFileID else { return }
        archivePages(offsets: IndexSet(integer: indexOfActivePage(withID: selectedFileID)))
    }

    func archivePages(offsets: IndexSet) {
        guard var workspace, !offsets.isEmpty else { return }
        let activePages = workspace.orderedPages.filter { !$0.isArchived && !$0.isDeleted }
        let pagesToArchive = offsets.compactMap { activePages.indices.contains($0) ? activePages[$0] : nil }
        guard !pagesToArchive.isEmpty else { return }

        let nextSelection = WorkspaceSelectionResolver.selectionAfterDeleting(
            fileIDs: activePages.map(\.id),
            offsets: offsets
        )

        let archivedSortBase = workspace.pages.filter(\.isArchived).map(\.sortOrder).max() ?? (workspace.pages.count - 1)
        var archivedSortOrder = archivedSortBase + 1
        for id in pagesToArchive.map(\.id) {
            guard let index = workspace.pages.firstIndex(where: { $0.id == id }) else { continue }
            workspace.pages[index].isArchived = true
            workspace.pages[index].sortOrder = archivedSortOrder
            workspace.pages[index].updatedAt = .now
            archivedSortOrder += 1
        }
        workspace.manifest.files = workspace.pages.map(\.manifestFile)
        workspace.manifest.lastSelectedFileID = nextSelection

        do {
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
            selectedFileID = nextSelection
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreArchivedPages(offsets: IndexSet) {
        guard var workspace, !offsets.isEmpty else { return }
        let archivedPages = workspace.orderedPages.filter { $0.isArchived && !$0.isDeleted }
        let pagesToRestore = offsets.compactMap { archivedPages.indices.contains($0) ? archivedPages[$0] : nil }
        guard !pagesToRestore.isEmpty else { return }

        let activeSortBase = workspace.pages.filter { !$0.isArchived }.map(\.sortOrder).max() ?? -1
        var activeSortOrder = activeSortBase + 1
        for id in pagesToRestore.map(\.id) {
            guard let index = workspace.pages.firstIndex(where: { $0.id == id }) else { continue }
            workspace.pages[index].isArchived = false
            workspace.pages[index].sortOrder = activeSortOrder
            workspace.pages[index].updatedAt = .now
            activeSortOrder += 1
        }

        workspace.manifest.files = workspace.pages.map(\.manifestFile)
        do {
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePage(id: UUID) {
        guard let index = archivedFiles.firstIndex(where: { $0.id == id }) else { return }
        restoreArchivedPages(offsets: IndexSet(integer: index))
    }

    func softDeleteArchivedPages(offsets: IndexSet) {
        guard var workspace, !offsets.isEmpty else { return }
        let archivedPages = workspace.orderedPages.filter { $0.isArchived && !$0.isDeleted }
        let pagesToDelete = offsets.compactMap { archivedPages.indices.contains($0) ? archivedPages[$0] : nil }
        guard !pagesToDelete.isEmpty else { return }

        let deletingIDs = Set(pagesToDelete.map(\.id))
        for id in deletingIDs {
            guard let index = workspace.pages.firstIndex(where: { $0.id == id }) else { continue }
            workspace.pages[index].isDeleted = true
            workspace.pages[index].updatedAt = .now
        }

        let remainingVisibleIDs = workspace.orderedPages
            .filter { !$0.isDeleted }
            .map(\.id)
        let nextSelection: UUID?
        if let selectedFileID, remainingVisibleIDs.contains(selectedFileID) {
            nextSelection = selectedFileID
        } else {
            nextSelection = remainingVisibleIDs.first
        }

        workspace.manifest.files = workspace.pages.map(\.manifestFile)
        workspace.manifest.lastSelectedFileID = nextSelection
        do {
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
            selectedFileID = nextSelection
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func softDeleteArchivedPage(id: UUID) {
        guard let index = archivedFiles.firstIndex(where: { $0.id == id }) else { return }
        softDeleteArchivedPages(offsets: IndexSet(integer: index))
    }

    func movePages(from source: IndexSet, to destination: Int) {
        guard var workspace else { return }
        var pages = workspace.orderedPages.filter { !$0.isArchived && !$0.isDeleted }
        move(&pages, fromOffsets: source, toOffset: destination)
        let archivedPages = workspace.orderedPages.filter { $0.isArchived && !$0.isDeleted }
        let deletedPages = workspace.orderedPages.filter(\.isDeleted)
        resequence(&pages)
        let archivedStart = pages.count
        var resequencedArchived = archivedPages
        for index in resequencedArchived.indices {
            resequencedArchived[index].sortOrder = archivedStart + index
        }
        workspace.pages = pages + resequencedArchived + deletedPages
        workspace.manifest.files = workspace.pages.map(\.manifestFile)

        do {
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedPageContent(_ content: String) {
        guard let selectedFileID, var workspace else { return }
        guard let index = workspace.pages.firstIndex(where: { $0.id == selectedFileID }) else { return }

        workspace.pages[index].content = content
        workspace.pages[index].updatedAt = .now
        workspace.manifest.files = workspace.pages.map(\.manifestFile)
        let updatedPage = workspace.pages[index]
        self.workspace = workspace
        loadedContent = content
        loadedContentPageID = selectedFileID

        scheduleAutosave(page: updatedPage, in: workspace)
        reminderScheduler.scheduleAfternoonRemindersIfNeeded(
            from: updatedPage.content,
            pageID: updatedPage.id,
            pageTitle: updatedPage.trimmedTitle
        )
    }

    func updateLineSpacing(_ value: Double) {
        guard var workspace else { return }
        workspace.manifest.settings.lineSpacing = min(max(value, 1.0), 2.2)
        do {
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pageTitle(for id: UUID) -> String {
        files.first(where: { $0.id == id })?.title ?? "Untitled"
    }

    private func restoreWorkspaceIfPossible() -> Bool {
        do {
            guard let url = try bookmarkStore.restoreWorkspaceURL() else { return false }
            openWorkspace(at: url, persistBookmark: true)
            return workspace != nil
        } catch {
            bookmarkStore.clearWorkspaceURL()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func openWorkspace(at url: URL, persistBookmark: Bool) {
        let alreadyAccessing = accessedWorkspaceURL?.standardizedFileURL == url.standardizedFileURL
        let startedAccessing = alreadyAccessing ? false : url.startAccessingSecurityScopedResource()

        do {
            let snapshot = try store.loadWorkspace(at: url)
            if let currentURL = accessedWorkspaceURL, !alreadyAccessing {
                currentURL.stopAccessingSecurityScopedResource()
            }

            accessedWorkspaceURL = url
            workspace = snapshot
            pageUndoManagers.removeAll()
            editorMode = .edit
            selectedFileID = WorkspaceSelectionResolver.restoredSelection(
                fileIDs: snapshot.orderedPages.filter { !$0.isDeleted }.map(\.id),
                lastSelectedFileID: snapshot.manifest.lastSelectedFileID
            )

            if persistBookmark {
                try bookmarkStore.saveWorkspaceURL(url)
            }
            loadSelectedPageContentAsync()
        } catch {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = error.localizedDescription
        }
    }

    private func persistSelection() {
        guard let workspace else { return }
        var manifest = workspace.manifest
        manifest.lastSelectedFileID = selectedFileID
        let rootURL = workspace.rootURL
        pendingSelectionPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [store] in
            do {
                try store.saveManifest(manifest, at: rootURL)
            } catch {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        pendingSelectionPersistWorkItem = workItem
        ioQueue.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func scheduleAutosave(page: WorkspacePage, in workspace: WorkspaceSnapshot) {
        pendingAutosaveWorkItems[page.id]?.cancel()
        let manifest = workspace.manifest
        let rootURL = workspace.rootURL

        let workItem = DispatchWorkItem { [store] in
            do {
                try store.savePageContent(page.content, fileName: page.fileName, at: rootURL)
                try store.saveManifest(manifest, at: rootURL)
            } catch {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        pendingAutosaveWorkItems[page.id] = workItem
        ioQueue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func loadSelectedPageContentAsync() {
        guard let selectedFileID, let workspace else {
            isLoadingSelectedContent = false
            loadedContent = ""
            loadedContentPageID = nil
            return
        }
        guard let page = workspace.pages.first(where: { $0.id == selectedFileID }) else {
            isLoadingSelectedContent = false
            loadedContent = ""
            loadedContentPageID = nil
            return
        }

        selectedContentLoadSequence += 1
        let sequence = selectedContentLoadSequence
        let rootURL = workspace.rootURL
        let fileName = page.fileName

        isLoadingSelectedContent = true
        loadedContentPageID = nil

        ioQueue.async { [store] in
            let content: String
            do {
                content = try store.loadPageContent(fileName: fileName, at: rootURL)
            } catch {
                Task { @MainActor in
                    if self.selectedContentLoadSequence == sequence {
                        self.isLoadingSelectedContent = false
                        self.errorMessage = error.localizedDescription
                    }
                }
                return
            }

            Task { @MainActor in
                guard self.selectedContentLoadSequence == sequence else { return }
                guard self.selectedFileID == selectedFileID else { return }
                self.loadedContent = content
                self.loadedContentPageID = selectedFileID
                self.isLoadingSelectedContent = false
            }
        }
    }

    private func mutatePage(id: UUID, mutation: (inout WorkspacePage) -> Void) {
        guard var workspace, let index = workspace.pages.firstIndex(where: { $0.id == id }) else { return }

        mutation(&workspace.pages[index])
        workspace.manifest.files = workspace.pages.map(\.manifestFile)
        let page = workspace.pages[index]

        do {
            try store.savePageContent(page.content, fileName: page.fileName, at: workspace.rootURL)
            try store.saveManifest(workspace.manifest, at: workspace.rootURL)
            self.workspace = workspace
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var filteredFiles: [WorkspacePage] {
        let ordered = files
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return ordered }
        return ordered.filter { page in
            page.title.localizedCaseInsensitiveContains(keyword) || page.content.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func indexOfActivePage(withID id: UUID) -> Int {
        activeFiles.firstIndex(where: { $0.id == id }) ?? 0
    }

    private func suggestedTitle(in pages: [WorkspacePage]) -> String {
        let existingTitles = Set(pages.map(\.trimmedTitle))
        let base = "Untitled"
        guard existingTitles.contains(base) else { return base }

        var index = 2
        while existingTitles.contains("\(base) \(index)") {
            index += 1
        }

        return "\(base) \(index)"
    }

    private func sanitizeTitle(_ value: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? "Untitled" : candidate
    }

    private func resequence(_ pages: inout [WorkspacePage]) {
        for index in pages.indices {
            pages[index].sortOrder = index
            pages[index].updatedAt = .now
        }
    }

    private func move(
        _ pages: inout [WorkspacePage],
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        let movingPages = fromOffsets.map { pages[$0] }
        pages.removeAll { page in
            movingPages.contains(where: { $0.id == page.id })
        }

        let destination = max(0, min(toOffset, pages.count))
        pages.insert(contentsOf: movingPages, at: destination)
    }

    private var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
