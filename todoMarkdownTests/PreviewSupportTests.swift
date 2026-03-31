//
//  PreviewSupportTests.swift
//  todoMarkdownTests
//
//  Created by Codex on 2026/3/16.
//

import Foundation
import Testing
@testable import todoMarkdown

struct PreviewSupportTests {

    @Test
    func decodeAndEncodeRoundTripsSupportedContent() {
        let source = """
        # Inbox
        - [ ] Ship v1
        - [x] Review notes

        Plain paragraph
        """

        let decoded = PreviewLineCodec.decode(source)

        #expect(decoded.count == 5)
        #expect(PreviewLineCodec.encode(decoded) == source)
    }

    @Test
    func mentionParsingSeparatesAssigneesFromDisplayText() {
        let content = PreviewMentionParser.parse("Ship launch plan @alice @bob")

        #expect(content.assignees == ["alice", "bob"])
        #expect(content.displayText == "Ship launch plan")
    }

    @Test
    func decodedTodoLineKeepsRawTextButExposesSeparatedAssignees() {
        let source = "- [ ] Follow up with design @chen"
        let decoded = PreviewLineCodec.decode(source)

        #expect(decoded.count == 1)
        #expect(decoded.first?.mentionContent.assignees == ["chen"])
        #expect(decoded.first?.mentionContent.displayText == "Follow up with design")
        #expect(PreviewLineCodec.encode(decoded) == source)
    }

    @Test
    func dateTagParsingFindsInlineDateTokens() {
        let segments = PreviewDateTagParser.segments(in: "Ship launch #2026-03-20 with QA")

        #expect(segments.count == 3)
        #expect(segments[1].kind == .dateTag)
        #expect(segments[1].text == "#2026-03-20")
    }

    @Test
    func dateTagParsingDoesNotTreatMarkdownHeadingMarkerAsDate() {
        let segments = PreviewDateTagParser.segments(in: "# Inbox")

        #expect(segments.count == 1)
        #expect(segments[0].kind == .plain)
        #expect(segments[0].text == "# Inbox")
    }

    @Test
    func toggleTodoFlipsCompletionMarker() {
        let source = """
        - [ ] Ship v1
        Plain paragraph
        """

        let updated = PreviewLineCodec.toggleTodo(in: source, at: 0)

        #expect(updated == """
        - [x] Ship v1
        Plain paragraph
        """)
    }

    @Test
    func insertingDeletingAndMovingPreviewLinesUpdatesText() {
        let source = """
        # Inbox
        - [ ] First
        - [ ] Second
        """

        let inserted = PreviewLineCodec.insertTodo(in: source, after: 1)
        #expect(inserted == """
        # Inbox
        - [ ] First
        - [ ]
        - [ ] Second
        """)

        let deleted = PreviewLineCodec.deleteLine(in: inserted, at: 1)
        #expect(deleted == """
        # Inbox
        - [ ]
        - [ ] Second
        """)

        let moved = PreviewLineCodec.moveLines(
            in: deleted,
            fromOffsets: IndexSet(integer: 2),
            toOffset: 1
        )
        #expect(moved == """
        # Inbox
        - [ ] Second
        - [ ]
        """)
    }

    @Test
    func archivingLineMovesItToArchiveSectionAtBottom() {
        let source = """
        # Inbox
        - [ ] First
        - [ ] Second
        """

        let archived = PreviewLineCodec.archiveLine(in: source, at: 1)

        #expect(archived == """
        # Inbox
        - [ ] Second

        ## Archive
        - [ ] First
        """)
    }

    @Test
    func restoredSelectionPrefersPersistedFileWhenAvailable() {
        let first = UUID()
        let second = UUID()

        #expect(
            WorkspaceSelectionResolver.restoredSelection(
                fileIDs: [first, second],
                lastSelectedFileID: second
            ) == second
        )

        #expect(
            WorkspaceSelectionResolver.restoredSelection(
                fileIDs: [first, second],
                lastSelectedFileID: UUID()
            ) == first
        )
    }

    @Test
    func deletionSelectionFallsBackToNearestRemainingFile() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        #expect(
            WorkspaceSelectionResolver.selectionAfterDeleting(
                fileIDs: [first, second, third],
                offsets: IndexSet(integer: 1)
            ) == third
        )

        #expect(
            WorkspaceSelectionResolver.selectionAfterDeleting(
                fileIDs: [first, second, third],
                offsets: IndexSet(integer: 2)
            ) == second
        )

        #expect(
            WorkspaceSelectionResolver.selectionAfterDeleting(
                fileIDs: [first],
                offsets: IndexSet(integer: 0)
            ) == nil
        )
    }
}
