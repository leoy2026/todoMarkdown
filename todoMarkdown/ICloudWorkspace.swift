//
//  ICloudWorkspace.swift
//  todoMarkdown
//

import Foundation

enum ICloudWorkspaceError: LocalizedError {
    case unavailable
    case destinationAlreadyContainsData

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "iCloud Drive is unavailable. Sign in to iCloud and enable iCloud Drive, then reopen todoMarkdown."
        case .destinationAlreadyContainsData:
            return "The iCloud workspace already contains data, so the existing workspace was not overwritten."
        }
    }
}

struct ICloudWorkspaceLocation {
    static let containerIdentifier = "iCloud.vip.ceee.todoMarkdown"
    static let workspaceDirectoryName = "todoMarkdown"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// The one canonical workspace shared by every build that uses this iCloud container.
    func workspaceURL() throws -> URL {
        guard let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: Self.containerIdentifier
        ) else {
            throw ICloudWorkspaceError.unavailable
        }

        let documentsURL = containerURL.appending(path: "Documents", directoryHint: .isDirectory)
        let workspaceURL = documentsURL.appending(path: Self.workspaceDirectoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }

    func isICloudWorkspace(_ url: URL) -> Bool {
        url.pathComponents.contains(Self.containerIdentifier)
            && url.lastPathComponent == Self.workspaceDirectoryName
    }
}

/// Receives iCloud Drive updates after another device changes the workspace.
final class WorkspaceFilePresenter: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue

    private let changeHandler: () -> Void

    init(url: URL, changeHandler: @escaping () -> Void) {
        self.presentedItemURL = url
        self.changeHandler = changeHandler
        let queue = OperationQueue()
        queue.name = "todoMarkdown.workspace-file-presenter"
        queue.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = queue
        super.init()
    }

    func presentedItemDidChange() {
        changeHandler()
    }
}
