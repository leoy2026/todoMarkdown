//
//  WorkspaceModels.swift
//  todoMarkdown
//
//  Created by Codex on 2026/3/16.
//

import Foundation

struct WorkspaceManifest: Codable, Equatable {
    var version: Int
    var lastSelectedFileID: UUID?
    var files: [WorkspaceManifestFile]
    var settings: WorkspaceSettings

    init(
        version: Int = 3,
        lastSelectedFileID: UUID? = nil,
        files: [WorkspaceManifestFile] = [],
        settings: WorkspaceSettings = .init()
    ) {
        self.version = version
        self.lastSelectedFileID = lastSelectedFileID
        self.files = files
        self.settings = settings
    }
}

struct WorkspaceManifestFile: Codable, Equatable, Identifiable {
    var id: UUID
    var fileName: String
    var title: String
    var sortOrder: Int
    var isArchived: Bool
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date

    var trimmedTitle: String {
        let candidate = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? "Untitled" : candidate
    }
}

struct WorkspaceSettings: Codable, Equatable {
    var lineSpacing: Double

    init(lineSpacing: Double = 1.35) {
        self.lineSpacing = lineSpacing
    }

    private enum CodingKeys: String, CodingKey {
        case lineSpacing
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 1.35
    }
}

struct WorkspacePage: Equatable, Identifiable {
    var id: UUID
    var fileName: String
    var title: String
    var content: String
    var sortOrder: Int
    var isArchived: Bool
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        fileName: String? = nil,
        title: String,
        content: String = "",
        sortOrder: Int,
        isArchived: Bool = false,
        isDeleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.fileName = fileName ?? "\(id.uuidString).md"
        self.title = title
        self.content = content
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(manifestFile: WorkspaceManifestFile, content: String) {
        id = manifestFile.id
        fileName = manifestFile.fileName
        title = manifestFile.title
        sortOrder = manifestFile.sortOrder
        isArchived = manifestFile.isArchived
        isDeleted = manifestFile.isDeleted
        createdAt = manifestFile.createdAt
        updatedAt = manifestFile.updatedAt
        self.content = content
    }

    var manifestFile: WorkspaceManifestFile {
        WorkspaceManifestFile(
            id: id,
            fileName: fileName,
            title: title,
            sortOrder: sortOrder,
            isArchived: isArchived,
            isDeleted: isDeleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var trimmedTitle: String {
        manifestFile.trimmedTitle
    }
}

extension WorkspaceManifestFile {
    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case title
        case sortOrder
        case isArchived
        case isDeleted
        case createdAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        title = try container.decode(String.self, forKey: .title)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct WorkspaceSnapshot: Equatable {
    var rootURL: URL
    var manifest: WorkspaceManifest
    var pages: [WorkspacePage]

    var orderedPages: [WorkspacePage] {
        guard pages.count > 1 else { return pages }

        let isAlreadySorted = zip(pages, pages.dropFirst()).allSatisfy { lhs, rhs in
            lhs.sortOrder <= rhs.sortOrder
        }
        if isAlreadySorted {
            return pages
        }
        return pages.sorted(using: KeyPathComparator(\.sortOrder))
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit:
            return "Edit"
        case .preview:
            return "Preview"
        }
    }
}

enum WorkspaceSelectionResolver {
    static func restoredSelection(
        fileIDs: [UUID],
        lastSelectedFileID: UUID?
    ) -> UUID? {
        guard !fileIDs.isEmpty else { return nil }

        if let lastSelectedFileID, fileIDs.contains(lastSelectedFileID) {
            return lastSelectedFileID
        }

        return fileIDs.first
    }

    static func selectionAfterDeleting(
        fileIDs: [UUID],
        offsets: IndexSet
    ) -> UUID? {
        guard !fileIDs.isEmpty else { return nil }

        let remaining = fileIDs.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        guard !remaining.isEmpty else { return nil }

        let nextIndex = min(offsets.first ?? 0, remaining.count - 1)
        return remaining[nextIndex]
    }
}
