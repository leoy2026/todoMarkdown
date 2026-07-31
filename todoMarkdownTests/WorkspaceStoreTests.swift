//
//  WorkspaceStoreTests.swift
//  todoMarkdownTests
//
//  Created by Codex on 2026/3/16.
//

import Foundation
import Testing
@testable import todoMarkdown

@MainActor
struct WorkspaceStoreTests {
    @Test
    func loadingEmptyWorkspaceCreatesManifest() throws {
        let rootURL = try temporaryDirectory()
        let store = WorkspaceStore()

        let snapshot = try store.loadWorkspace(at: rootURL)

        #expect(snapshot.pages.isEmpty)
        #expect(snapshot.manifest.files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: rootURL.appending(path: "workspace.json").path))
    }

    @Test
    func loadingWorkspaceImportsExistingMarkdownFilesWhenManifestIsMissing() throws {
        let rootURL = try temporaryDirectory()
        let inboxURL = rootURL.appending(path: "Inbox.md")
        let todayURL = rootURL.appending(path: "Today.md")

        try "# Inbox\n\n- [ ] Ship".write(to: inboxURL, atomically: true, encoding: .utf8)
        try "- [ ] Ship\n   \nPlain note".write(to: todayURL, atomically: true, encoding: .utf8)

        let store = WorkspaceStore()
        let snapshot = try store.loadWorkspace(at: rootURL)

        #expect(snapshot.pages.count == 2)
        #expect(snapshot.pages.map(\.fileName) == ["Inbox.md", "Today.md"])
        #expect(snapshot.pages.map(\.trimmedTitle) == ["Inbox", "Today"])
        #expect(snapshot.pages.map(\.taskCount) == [2, 2])
        #expect(snapshot.manifest.files.map(\.taskCount) == [2, 2])
    }

    @Test
    func savingManifestAndPageContentRoundTrips() throws {
        let rootURL = try temporaryDirectory()
        let store = WorkspaceStore()
        let page = WorkspacePage(
            title: "Inbox",
            content: "# Inbox\n- [ ] Ship v1",
            sortOrder: 0
        )

        try store.createPage(page, at: rootURL)
        try store.saveManifest(
            WorkspaceManifest(
                lastSelectedFileID: page.id,
                files: [page.manifestFile]
            ),
            at: rootURL
        )

        let snapshot = try store.loadWorkspace(at: rootURL)

        #expect(snapshot.manifest.lastSelectedFileID == page.id)
        #expect(snapshot.pages.count == 1)
        #expect(snapshot.pages.first?.id == page.id)
        #expect(snapshot.pages.first?.fileName == page.fileName)
        #expect(snapshot.pages.first?.title == page.title)
        #expect(snapshot.pages.first?.content == page.content)
        #expect(snapshot.pages.first?.taskCount == 2)
        #expect(snapshot.manifest.files.first?.taskCount == 2)
    }

    @Test
    func taskCountIgnoresEmptyAndWhitespaceOnlyLines() {
        let content = """
        # Inbox

           \t
        - [ ] Ship
        Plain note
        """

        #expect(WorkspaceContentMetrics.taskCount(in: content) == 3)
    }

    @Test
    func deletingPageRemovesMarkdownFile() throws {
        let rootURL = try temporaryDirectory()
        let store = WorkspaceStore()
        let page = WorkspacePage(title: "Inbox", sortOrder: 0)

        try store.createPage(page, at: rootURL)
        #expect(FileManager.default.fileExists(atPath: rootURL.appending(path: page.fileName).path))

        try store.deletePage(fileName: page.fileName, at: rootURL)

        #expect(!FileManager.default.fileExists(atPath: rootURL.appending(path: page.fileName).path))
    }

    @Test
    func migratingWorkspaceCopiesDataIntoAnEmptyDestination() throws {
        let sourceURL = try temporaryDirectory()
        let destinationURL = try temporaryDirectory()
        let store = WorkspaceStore()
        let page = WorkspacePage(title: "Inbox", content: "- [ ] Sync", sortOrder: 0)

        try store.createPage(page, at: sourceURL)
        try store.saveManifest(WorkspaceManifest(files: [page.manifestFile]), at: sourceURL)

        try store.migrateWorkspace(from: sourceURL, to: destinationURL)
        let migrated = try store.loadWorkspace(at: destinationURL)

        #expect(migrated.pages.map(\.content) == ["- [ ] Sync"])
        #expect(migrated.manifest.files.map(\.id) == [page.id])
    }

    @Test
    func migratingWorkspaceDoesNotOverwriteExistingCloudData() throws {
        let sourceURL = try temporaryDirectory()
        let destinationURL = try temporaryDirectory()
        let store = WorkspaceStore()

        try "Source".write(to: sourceURL.appending(path: "Source.md"), atomically: true, encoding: .utf8)
        try "Cloud".write(to: destinationURL.appending(path: "Cloud.md"), atomically: true, encoding: .utf8)

        #expect(throws: ICloudWorkspaceError.destinationAlreadyContainsData) {
            try store.migrateWorkspace(from: sourceURL, to: destinationURL)
        }
        #expect(FileManager.default.fileExists(atPath: destinationURL.appending(path: "Cloud.md").path))
    }

    @Test
    func registeredContentUpdatesCanUndoAndRedo() throws {
        let rootURL = try temporaryDirectory()
        let controller = WorkspaceController(
            store: WorkspaceStore(),
            bookmarkStore: StaticWorkspaceBookmarkStore(url: rootURL),
            reminderScheduler: NoopReminderScheduler()
        )

        controller.performInitialSetup()
        let pageID = try #require(controller.createPage())
        #expect(controller.selectedFileID == pageID)

        controller.updateSelectedPageContent("First", registersUndo: true)
        #expect(controller.loadedContent == "First")
        #expect(controller.selectedPageUndoManager?.canUndo == true)

        controller.undoSelectedPageChange()
        #expect(controller.loadedContent == "")
        #expect(controller.selectedPage?.content == "")
        #expect(controller.selectedPageUndoManager?.canRedo == true)

        controller.redoSelectedPageChange()
        #expect(controller.loadedContent == "First")
        #expect(controller.selectedPage?.content == "First")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct StaticWorkspaceBookmarkStore: WorkspaceBookmarkPersisting {
        let url: URL?

        func restoreWorkspaceURL() throws -> URL? {
            url
        }

        func saveWorkspaceURL(_ url: URL) throws {}

        func clearWorkspaceURL() {}
    }

    private struct NoopReminderScheduler: ReminderScheduling {
        func scheduleAfternoonRemindersIfNeeded(from content: String, pageID: UUID, pageTitle: String) {}
    }
}
