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

        try "# Inbox".write(to: inboxURL, atomically: true, encoding: .utf8)
        try "- [ ] Ship".write(to: todayURL, atomically: true, encoding: .utf8)

        let store = WorkspaceStore()
        let snapshot = try store.loadWorkspace(at: rootURL)

        #expect(snapshot.pages.count == 2)
        #expect(snapshot.pages.map(\.fileName) == ["Inbox.md", "Today.md"])
        #expect(snapshot.pages.map(\.trimmedTitle) == ["Inbox", "Today"])
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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
