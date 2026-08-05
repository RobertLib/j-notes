//
//  CalendarView.swift
//  notes
//
//  Created by Robert Libšanský on 17.07.2022.
//

import SwiftUI

struct CalendarView: View {
    @Environment(NotesStore.self) private var notesStore
    @State private var selectedDate = Date()

    private var notesForSelectedDate: [NoteModel] {
        let calendar = Calendar.current
        return notesStore.activeNotes.filter { note in
            guard let reminder = note.reminder else { return false }
            return calendar.isDate(reminder, inSameDayAs: selectedDate)
        }
        // Every note that got this far has a reminder, so the fallback is
        // unreachable — `.distantPast` rather than `Date()`, which would have
        // made the ordering depend on the moment the list was built.
        .sorted { ($0.reminder ?? .distantPast) < ($1.reminder ?? .distantPast) }
    }

    var body: some View {
        // Bound once rather than read three times over — for the empty state, for
        // the rows and for the header's count — each of which filtered and sorted
        // the whole library again. Same reason `NotesView` binds `noteSections`.
        let notes = notesForSelectedDate

        return NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()

                Divider()

                if notes.isEmpty {
                    VStack {
                        Spacer()
                        // Semantic rather than a fixed 20pt, so it follows
                        // Dynamic Type — see `NotesView`'s empty state.
                        Text("noNotesForDate")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            ForEach(notes) { note in
                                NavigationLink {
                                    // Lazily — see `LazyNoteDetail`.
                                    LazyNoteDetail(note: note)
                                } label: {
                                    HStack {
                                        Circle()
                                            .frame(width: 16, height: 16)
                                            .foregroundStyle(note.color ?? .gray.opacity(0.4))

                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                if let reminder = note.reminder {
                                                    Text(reminder.formatted(date: .omitted, time: .shortened))
                                                        .font(.subheadline)
                                                        .foregroundStyle(Color.accentColor)
                                                }

                                                Spacer()

                                                if note.type == .drawing {
                                                    Image(systemName: "pencil.tip.crop.circle")
                                                        .font(.system(size: 18))
                                                        .foregroundStyle(Color.accentColor.opacity(0.75))
                                                        // The body below renders
                                                        // "Drawing note" already.
                                                        .accessibilityHidden(true)
                                                }
                                            }

                                            if !note.title.isEmpty {
                                                Text(note.title)
                                                    .font(.headline)
                                            }

                                            if note.type == .text {
                                                Text(note.isProtected ? NoteModel.redactedBody : note.content)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Text("drawingNote")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .italic()
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    // One element rather than the four or five
                                    // pieces it is drawn from — the same treatment,
                                    // and for the same reason, as the list's own
                                    // rows. See `NoteRowView`.
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        } header: {
                            // Plural form comes from Localizable.stringsdict so
                            // each language applies its own rules.
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString("notesCount", comment: "Number of notes for the selected day"),
                                notes.count
                            ))
                        }
                    }
                }
            }
            .navigationTitle("calendar")
        }
    }
}

#Preview {
    CalendarView()
        .environment(NotesStore())
}
