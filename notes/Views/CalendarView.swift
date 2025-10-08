//
//  CalendarView.swift
//  notes
//
//  Created by Robert Libšanský on 17.07.2022.
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var notesStore: NotesStore
    @State private var selectedDate = Date()

    private var notesForSelectedDate: [NoteModel] {
        let calendar = Calendar.current
        return notesStore.notes.filter { note in
            guard let reminder = note.reminder else { return false }
            return calendar.isDate(reminder, inSameDayAs: selectedDate)
        }.sorted { $0.reminder ?? Date() < $1.reminder ?? Date() }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()

                Divider()

                if notesForSelectedDate.isEmpty {
                    VStack {
                        Spacer()
                        Text("noNotesForDate")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            ForEach(notesForSelectedDate) { note in
                                NavigationLink {
                                    NoteDetailView(note: note)
                                } label: {
                                    HStack {
                                        Circle()
                                            .frame(width: 16, height: 16)
                                            .foregroundColor(note.color ?? .gray.opacity(0.4))

                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                if let reminder = note.reminder {
                                                    Text(reminder.formatted(date: .omitted, time: .shortened))
                                                        .font(.subheadline)
                                                        .foregroundColor(.accentColor)
                                                }

                                                Spacer()

                                                if note.type == .drawing {
                                                    Image(systemName: "pencil.tip.crop.circle")
                                                        .font(.system(size: 18))
                                                        .foregroundColor(.accentColor.opacity(0.75))
                                                }
                                            }

                                            if !note.title.isEmpty {
                                                Text(note.title)
                                                    .font(.headline)
                                            }

                                            if note.type == .text {
                                                Text(note.content)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text("drawingNote")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            let count = notesForSelectedDate.count
                            if count == 1 {
                                Text(String(format: NSLocalizedString("notesCountSingular", comment: ""), count))
                            } else if count >= 2 && count <= 4 {
                                Text(String(format: NSLocalizedString("notesCountPaucal", comment: ""), count))
                            } else {
                                Text(String(format: NSLocalizedString("notesCountPlural", comment: ""), count))
                            }
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
        .environmentObject(NotesStore())
}
