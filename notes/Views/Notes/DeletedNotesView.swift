//
//  DeletedNotesView.swift
//  notes
//
//  Created by Robert Libšanský on 13.10.2025.
//

import SwiftUI

struct DeletedNotesView: View {
    @Environment(NotesStore.self) private var notesStore
    @State private var isDeleteNoteConfirmPresented = false
    @State private var isEmptyTrashConfirmPresented = false
    @State private var noteToDelete: NoteModel?

    var body: some View {
        // Bound once rather than read twice over — for the empty state and again
        // for the rows — each read filtering the whole library and sorting the
        // result by deletion date. Same reason `NotesView` binds `noteSections`
        // and `NotesStore` grew `hasDeletedNotes`.
        let deleted = notesStore.deletedNotes

        return List {
            if deleted.isEmpty {
                // Reachable now that the screen outlives the button that opened
                // it — see `NotesRoute`. Semantic font for the same reason
                // as `NotesView`'s empty state: it follows Dynamic Type.
                Text("noDeletedNotes")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(deleted) { note in
                    // Openable, which it was not. The row showed a hundred
                    // characters and no way to see the rest, so deciding whether a
                    // note was worth restoring meant restoring it to find out —
                    // and a drawing gave nothing away at all. The detail view
                    // recognises a trashed note and offers Restore and Delete
                    // permanently in place of Edit and Trash; a protected one still
                    // asks for Face ID first, exactly as it does from the list.
                    // Lazily, for the reason `LazyNoteDetail` exists.
                    NavigationLink {
                        LazyNoteDetail(note: note)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if !note.title.isEmpty {
                                Text(note.title)
                                    .font(.headline)
                            }

                            if note.type == .text {
                                Text(note.isProtected ? NoteModel.redactedBody : String(note.content.prefix(100)))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text("drawingNote")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }

                            if let deletedAt = note.deletedAt {
                                // `verbatim` on the second half: an interpolated
                                // literal is a LocalizedStringKey, so this went
                                // looking for a translation of ": %@" on every row.
                                (Text("deletedAt") + Text(verbatim: ": \(deletedAt.formatted(date: .abbreviated, time: .shortened))"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // One element rather than the three `Text`s it is drawn
                        // from — the same treatment as the list's own rows. See
                        // `NoteRowView`.
                        .accessibilityElement(children: .combine)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            withAnimation {
                                notesStore.restoreFromTrash(note: note)
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                        .accessibilityLabel("restore")
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            noteToDelete = note
                            isDeleteNoteConfirmPresented = true
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .tint(.red)
                        .accessibilityLabel("permanentDelete")
                    }
                }
            }
        }
        .navigationTitle("deletedNotes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            emptyTrashToolbar(hasDeletedNotes: !deleted.isEmpty)
        }
        .confirmationDialog(
            "permanentDeleteConfirm",
            isPresented: $isDeleteNoteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("permanentDelete", role: .destructive) {
                if let note = noteToDelete {
                    // Cancelling the note's notifications is the store's job — see
                    // `NotesStore.remove`, which does it for the same reason
                    // `moveToTrash` does.
                    notesStore.remove(note: note)
                    noteToDelete = nil
                }
            }

            Button("cancel", role: .cancel) {
                noteToDelete = nil
            }
        }
    }

    /// The button that drops the whole trash at once.
    ///
    /// Emptying it one swipe at a time was the only way there was, and the trash is
    /// where a month of deletions collects — a note waits thirty days before
    /// `purgeExpiredTrash` takes it. This is that same purge, asked for rather than
    /// waited for.
    ///
    /// Split out of the toolbar rather than written inline, so the confirmation can
    /// hang off the button. Two `confirmationDialog`s on one view compete for the
    /// same presentation and one of them silently never appears — and inline, the
    /// whole chain was one expression the type checker gave up on.
    @ToolbarContentBuilder
    private func emptyTrashToolbar(hasDeletedNotes: Bool) -> some ToolbarContent {
        if hasDeletedNotes {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isEmptyTrashConfirmPresented = true
                } label: {
                    Text("emptyTrash")
                }
                .confirmationDialog(
                    "emptyTrashConfirm",
                    isPresented: $isEmptyTrashConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("emptyTrash", role: .destructive) {
                        // `withAnimation` hands back whatever its body returns, and
                        // the button's action gives back nothing — so the store's
                        // "did anything change" answer is dropped explicitly here.
                        withAnimation {
                            _ = notesStore.emptyTrash()
                        }
                    }

                    Button("cancel", role: .cancel) {}
                } message: {
                    Text("emptyTrashMessage")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeletedNotesView()
    }
    .environment(NotesStore())
}
