//
//  NoteRowView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

/// One note as it appears in the list.
///
/// The row draws itself and nothing more. It used to own the `NavigationLink` to
/// the note as well, which fixed how the list navigates — a link that carries its
/// own destination can only push, and the split view `NotesView` puts the same list
/// in has a detail column to fill instead. `NoteListView` wraps the row in a
/// value-based link that both containers understand; see `NotesRoute`.
///
/// That also retires the reason `LazyNoteDetail` was needed here. A destination
/// written inline is an ordinary `@ViewBuilder` argument, so `NoteDetailView.init`
/// — and the cross-process `LocalAuthentication` query in it — ran for every
/// visible row on every redraw. A value-based link builds nothing until it is
/// followed.
///
/// # Accessibility
///
/// Each of the three styles is one element rather than the five to eight pieces it
/// is drawn from. Left to itself VoiceOver made a separate stop of every one of
/// them, so reaching the next note in the list meant swiping past a timestamp, a
/// title, two lines of body, a date and then each tag in turn — and the list is the
/// app's main surface, the one screen this had to work on.
///
/// Combined rather than relabelled, so the spoken row is assembled from the very
/// `Text`s that are on screen and cannot drift from them — the same reason
/// `NoteModel.redactedBody` and `ChecklistItem.Box` are constants. What that needs
/// from the status glyphs is a label each, since a bare `Image(systemName:)`
/// contributes the symbol's own generic description: the pin, the lock and the
/// reminder bell said nothing about being pinned, locked or due. Where the row
/// already spells one out in text the glyph is hidden instead, or it would be said
/// twice.
struct NoteRowView: View {
    let note: NoteModel
    let displayStyle: NoteDisplayStyle

    var body: some View {
        switch displayStyle {
        case .compact:
            compactView
        case .standard:
            standardView
        case .detailed:
            detailedView
        }
    }

    private var compactView: some View {
        HStack {
            Circle()
                .frame(width: 12, height: 12)
                .foregroundStyle(note.color ?? .gray.opacity(0.4))

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
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(note.isProtected ? NoteModel.redactedBody : note.content)
                            .font(.body)
                            .lineLimit(1)
                    }

                    Spacer()

                    if note.type == .drawing {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                            // This is the one style where the glyph can be the only
                            // sign of a drawing: an untitled one renders "Drawing
                            // note" as its headline, a titled one shows the title
                            // and leaves the rest to the icon.
                            .accessibilityLabel("drawingNote")
                            .accessibilityHidden(note.title.isEmpty)
                    }

                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                            .accessibilityLabel("pinned")
                    }

                    if note.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("lockedNote")
                    }
                }

                Text(note.createdAt.timeAgoDisplay())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var standardView: some View {
        HStack {
            Circle()
                .frame(width: 16, height: 16)
                .foregroundStyle(note.color ?? .gray.opacity(0.4))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(note.createdAt.timeAgoDisplay())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Drawing indicator
                    if note.type == .drawing {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                            // The body below always renders "Drawing note" in this
                            // style, so the glyph has nothing left to add.
                            .accessibilityHidden(true)
                    }

                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                            .accessibilityLabel("pinned")
                    }

                    if note.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("lockedNote")
                    }
                }

                if !note.title.isEmpty {
                    Text(note.title).font(.title2)
                }

                if note.type == .text {
                    Text(note.isProtected ? NoteModel.redactedBody : note.content).lineLimit(2).truncationMode(.tail)
                } else {
                    Text("drawingNote")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if let reminder = note.reminder {
                    if reminder > Date() {
                        HStack {
                            Image(systemName: "bell")
                                .foregroundStyle(Color.accentColor)
                                // A bare date says nothing about being a reminder,
                                // and the bell beside it is what carries that here —
                                // the detailed style spells it out in text instead.
                                .accessibilityLabel("reminder")

                            Text(reminder.formatted())
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                    }
                }

                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(note.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailedView: some View {
        HStack(alignment: .top) {
            Circle()
                .frame(width: 20, height: 20)
                .foregroundStyle(note.color ?? .gray.opacity(0.4))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.createdAt.timeAgoDisplay())
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(note.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.8))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if note.type == .drawing {
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                                // As in the standard style: the body below always
                                // renders "Drawing note" here.
                                .accessibilityHidden(true)
                        }

                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                                .accessibilityLabel("pinned")
                        }

                        if note.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("lockedNote")
                        }
                    }
                }

                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                if note.type == .text {
                    Text(note.isProtected ? NoteModel.redactedBody : note.content)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .font(.body)
                } else {
                    Text("drawingNote")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if let reminder = note.reminder {
                    if reminder > Date() {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Color.accentColor)
                                // "Reminder" is right there in text beside it.
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("reminder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(reminder.formatted())
                                    .font(.subheadline)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // The same rule the map pins on, so a note cannot claim a saved
                // location the map has nowhere to put — see `NoteModel.coordinate`.
                if note.coordinate != nil {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Color.accentColor)
                            // As with the bell above: the text says it.
                            .accessibilityHidden(true)

                        Text("savedLocation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(note.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NoteRowView(
        note: NoteModel(
            title: "Title",
            content: "Lorem ipsum",
            pinned: true,
            reminder: Date(),
            tags: ["práce", "osobní"]
        ),
        displayStyle: .standard
    )
}
