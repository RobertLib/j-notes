//
//  NoteRowView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

struct NoteRowView: View {
    let note: NoteModel
    let displayStyle: NoteDisplayStyle

    var body: some View {
        NavigationLink {
            NoteDetailView(note: note)
        } label: {
            switch displayStyle {
            case .compact:
                compactView
            case .standard:
                standardView
            case .detailed:
                detailedView
            }
        }
    }

    private var compactView: some View {
        HStack {
            Circle()
                .frame(width: 12, height: 12)
                .foregroundColor(note.color ?? .gray.opacity(0.4))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    } else if note.type == .drawing {
                        Text(LocalizedStringKey("drawingNote"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(note.content)
                            .font(.body)
                            .lineLimit(1)
                    }

                    Spacer()

                    if note.type == .drawing {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor.opacity(0.75))
                    }

                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor.opacity(0.75))
                    }
                }

                Text(note.createdAt.timeAgoDisplay())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var standardView: some View {
        HStack {
            Circle()
                .frame(width: 16, height: 16)
                .foregroundColor(note.color ?? .gray.opacity(0.4))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(note.createdAt.timeAgoDisplay())
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Drawing indicator
                    if note.type == .drawing {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor.opacity(0.75))
                    }

                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor.opacity(0.75))
                    }
                }

                if !note.title.isEmpty {
                    Text(note.title).font(.title2)
                }

                if note.type == .text {
                    Text(note.content).lineLimit(2).truncationMode(.tail)
                } else {
                    Text("drawingNote")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }

                if let reminder = note.reminder {
                    if reminder > Date() {
                        HStack {
                            Image(systemName: "bell")
                                .foregroundColor(.accentColor)

                            Text(reminder.formatted())
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailedView: some View {
        HStack(alignment: .top) {
            Circle()
                .frame(width: 20, height: 20)
                .foregroundColor(note.color ?? .gray.opacity(0.4))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.createdAt.timeAgoDisplay())
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(note.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if note.type == .drawing {
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor.opacity(0.75))
                        }

                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor.opacity(0.75))
                        }
                    }
                }

                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                if note.type == .text {
                    Text(note.content)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .font(.body)
                } else {
                    Text("drawingNote")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }

                if let reminder = note.reminder {
                    if reminder > Date() {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("reminder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(reminder.formatted())
                                    .font(.subheadline)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                if note.location != nil {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.accentColor)

                        Text("Uložená poloha")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NoteRowView(
        note: NoteModel(
            title: "Title",
            content: "Lorem ipsum",
            pinned: true,
            reminder: Date()
        ),
        displayStyle: .standard
    )
}
