//
//  todoMarkdownApp.swift
//  todoMarkdown
//
//  Created by Leo Y on 2026/3/16.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct todoMarkdownApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: todoMarkdownMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct todoMarkdownMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        todoMarkdownVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct todoMarkdownVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
