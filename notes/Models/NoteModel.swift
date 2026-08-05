//
//  NoteModel.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import CoreLocation
import SwiftUI

enum NoteType: String, Codable, Sendable {
    case text
    case drawing
}

/// How a note's colour is stored.
///
/// `Color` has no `Codable` conformance of its own. This app used to add one
/// through a `@retroactive` extension, which would break the day SwiftUI ships
/// its own — and would then silently change the on-disk format underneath
/// existing notes. Owning the type removes that risk. The JSON shape is
/// unchanged, so files written by earlier versions still decode.
struct CodableColor: Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// `nil` for a colour whose components cannot be read — a pattern colour,
    /// for instance. The note then simply carries no colour, rather than the
    /// encode failing and taking the whole save down with it.
    init?(_ color: Color) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        // Resolved against a fixed appearance rather than whatever happens to be
        // current. A dynamic colour otherwise encodes to different components
        // depending on whether the note was saved in light or dark mode, so the
        // same pick came back as a different colour — and `.primary` came back as
        // white, which is invisible as a map pin. The drawing renderer pins the
        // appearance for the same reason; see `DrawingPreview.render`.
        let resolved = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )

        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }

        red = r
        green = g
        blue = b
        alpha = a
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        red = try container.decode(Double.self, forKey: .red)
        green = try container.decode(Double.self, forKey: .green)
        blue = try container.decode(Double.self, forKey: .blue)
        // Notes written before the alpha channel existed have no such key.
        alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// A line of a note's body that is a checklist item, and how one is spelled.
///
/// The two box glyphs used to be written out as literals at four places — the
/// detail view's renderer and its toggle, the editor's tap handling and its
/// toolbar action. That is the arrangement `NoteModel.redactedBody` exists to warn
/// about: one spelling drifts and the same line reads as a checkbox in one view
/// and as ordinary text in the next.
struct ChecklistItem: Equatable {
    /// The two states a box can be in. The raw value is the glyph as stored.
    enum Box: String, CaseIterable {
        case unchecked = "▢"
        case checked = "▣"

        /// What a line carrying this box starts with: the glyph, and the space
        /// that separates it from the text.
        var marker: String { "\(rawValue) " }

        var toggled: Box { self == .checked ? .unchecked : .checked }
    }

    let box: Box

    /// The line's text with the marker taken off.
    let label: String

    var isChecked: Bool { box == .checked }

    /// The line as it is stored.
    var line: String { box.marker + label }

    /// The same item ticked the other way.
    var toggled: ChecklistItem { ChecklistItem(box: box.toggled, label: label) }

    init(box: Box, label: String) {
        self.box = box
        self.label = label
    }

    /// The checklist item `line` spells, or `nil` when it is ordinary text.
    init?(line: String) {
        if line.hasPrefix(Box.checked.marker) {
            box = .checked
            label = String(line.dropFirst(Box.checked.marker.count))
        } else if line.hasPrefix(Box.unchecked.marker) {
            box = .unchecked
            label = String(line.dropFirst(Box.unchecked.marker.count))
        } else {
            return nil
        }
    }
}

struct NoteModel: Identifiable, Sendable {
    // `id` and `createdAt` are the note's identity and never change. The rest is
    // mutable so callers can copy-and-tweak a note (`var updated = note`) instead
    // of re-listing every field through the initialiser — a pattern that used to
    // silently drop whichever field the caller forgot, such as `isDeleted`.
    let id: UUID
    let createdAt: Date
    var title: String
    var content: String
    var type: NoteType
    var drawingData: Data?
    var drawingCanvasSize: CGSize?
    var backgroundImageData: Data?
    var pinned: Bool
    var color: Color?
    var reminder: Date?
    var notificationIdentifiers: [String]?
    var location: [Double]?
    var isDeleted: Bool
    var deletedAt: Date?
    var tags: [String]
    var isProtected: Bool

    init(
        id: UUID? = nil,
        createdAt: Date? = nil,
        title: String,
        content: String,
        type: NoteType? = nil,
        drawingData: Data? = nil,
        drawingCanvasSize: CGSize? = nil,
        backgroundImageData: Data? = nil,
        pinned: Bool? = nil,
        color: Color? = nil,
        reminder: Date? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil,
        isDeleted: Bool? = nil,
        deletedAt: Date? = nil,
        tags: [String]? = nil,
        isProtected: Bool? = nil
    ) {
        self.id = id ?? UUID()
        self.createdAt = createdAt ?? .now
        self.title = title
        self.content = content
        self.type = type ?? .text
        self.drawingData = drawingData
        self.drawingCanvasSize = drawingCanvasSize
        self.backgroundImageData = backgroundImageData
        self.pinned = pinned ?? false
        self.color = color
        self.reminder = reminder
        self.notificationIdentifiers = notificationIdentifiers
        self.location = location
        self.isDeleted = isDeleted ?? false
        self.deletedAt = deletedAt
        self.tags = tags ?? []
        self.isProtected = isProtected ?? false
    }

    /// Where this note was created, or `nil` when it carries no usable position.
    ///
    /// Optional rather than falling back to (0, 0), which is a real place in the
    /// Gulf of Guinea: `location` is a bare array of doubles, so a hand-edited or
    /// truncated backup can carry one too short to describe a coordinate — and the
    /// map, which only checked that `location` was non-`nil`, put a pin there.
    ///
    /// Also what decides whether a note counts as having a location at all, so the
    /// row's "saved location" line and the map's pin cannot disagree.
    var coordinate: CLLocationCoordinate2D? {
        guard let location, location.count >= 2 else { return nil }

        return CLLocationCoordinate2D(latitude: location[0], longitude: location[1])
    }

    /// What stands in for a protected note's body in any list that shows one.
    ///
    /// A constant rather than a literal per call site. It was spelled out at five
    /// of them, and one had drifted to seven bullets against the others' eleven —
    /// so the same locked note was redacted to a different width depending on
    /// which display style the list happened to be in.
    static let redactedBody = "•••••••••••"

    /// What two spellings of a tag have to share in order to be the same tag.
    ///
    /// Case-folded, so "Práce" and "práce" are one tag rather than two. They used
    /// to be two everywhere it mattered: two chips in the filter row, two entries
    /// in `allTags`, and a filter that matched only whichever spelling was tapped
    /// — while the search field, which goes through
    /// `localizedCaseInsensitiveContains`, had always treated them as one. Typing
    /// a tag is not a spelling exercise, and the shift key is easy to catch on the
    /// first letter of a word.
    ///
    /// `lowercased()` rather than `localizedLowercase`, because this decides what
    /// a backup round-trips to: a rule that followed the device's language would
    /// merge a user's tags differently depending on where they were standing.
    /// Diacritics stay significant on purpose — "prace" is not "práce", and
    /// folding those would collapse tags the user can see are different.
    ///
    /// One spelling of the rule for the whole app, the same reason
    /// `ChecklistItem.Box` owns the two glyphs: it is applied at decode, in the
    /// store's `allTags`, in the form's `addTag` and in the list's filter, and a
    /// tag counted as distinct in one of those and identical in another is how a
    /// chip comes to filter for nothing.
    static func tagKey(_ tag: String) -> String {
        tag.lowercased()
    }

    /// Whether two tags name the same tag — see `tagKey`.
    static func tagsMatch(_ lhs: String, _ rhs: String) -> Bool {
        tagKey(lhs) == tagKey(rhs)
    }

    /// `tags` with repeats dropped, keeping the first of each and the order they
    /// arrived in.
    ///
    /// Applied where a note is decoded, because that is where tags reach the app
    /// from outside it: the form deduplicates as they are typed, but a backup is
    /// whatever the user hands over — hand-edited, or written by another build —
    /// and every list in the app renders tags through `ForEach(id: \.self)`. Two
    /// entries sharing an id leaves SwiftUI's layout ill-defined, which is the same
    /// reason `NotesStore.importNotes` deduplicates the notes themselves by `id`.
    ///
    /// Repeats are counted through `tagKey`, so a note carrying both "Práce" and
    /// "práce" keeps the first spelling rather than rendering the tag twice.
    static func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert(tagKey($0)).inserted }
    }

    /// Title for places that need a non-empty label — navigation bars, map
    /// annotations, notification titles. Untitled notes get a generic word
    /// rather than rendering as blank.
    var displayTitle: String {
        title.isEmpty ? String(localized: "note") : title
    }

    /// Title for this note's reminder notification. A protected note's title is
    /// user text just as its body is, and a notification renders on the lock
    /// screen — so it gives way to a neutral label. The same redaction the widget
    /// payload applies for the same reason; see `WidgetNoteEntry`.
    var notificationTitle: String {
        isProtected ? String(localized: "reminder") : displayTitle
    }

    /// Subtitle for this note's reminder notification. A drawing has no text to
    /// show and a protected note must not spill its content onto the lock
    /// screen, so both fall back to a label.
    var notificationSubtitle: String {
        if type == .drawing { return String(localized: "drawingNote") }
        return isProtected ? String(localized: "lockedNote") : content
    }

    /// Whether this note should appear in the results for `query`.
    ///
    /// A locked note's body is deliberately not searched. Its title and tags are,
    /// because the row shows both either way — but the body is exactly what the
    /// lock withholds, and matching on it put the note in the results, which
    /// confirms the term is in there about as well as printing it would.
    ///
    /// Split out of the list view so the rule can be exercised directly, the same
    /// reason `ReminderFormState` lives on its own: a view's filtering is not
    /// reachable from a test.
    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return true }

        if title.localizedCaseInsensitiveContains(trimmed) { return true }
        if tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) {
            return true
        }

        return !isProtected && content.localizedCaseInsensitiveContains(trimmed)
    }
}

// MARK: - Codable conformance with backward compatibility
extension NoteModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id, createdAt, title, content, type
        case drawingData, drawingCanvasSize, backgroundImageData
        case pinned, color, reminder, notificationIdentifiers, location
        case isDeleted, deletedAt, tags, isProtected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(NoteType.self, forKey: .type)
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        drawingCanvasSize = try container.decodeIfPresent(CGSize.self, forKey: .drawingCanvasSize)
        backgroundImageData = try container.decodeIfPresent(Data.self, forKey: .backgroundImageData)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        color = try container.decodeIfPresent(CodableColor.self, forKey: .color)?.color
        reminder = try container.decodeIfPresent(Date.self, forKey: .reminder)
        notificationIdentifiers = try container.decodeIfPresent([String].self, forKey: .notificationIdentifiers)
        location = try container.decodeIfPresent([Double].self, forKey: .location)

        // New properties with default values for backward compatibility
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        // Deduplicated on the way in — see `NoteModel.uniqueTags`.
        tags = NoteModel.uniqueTags(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        try container.encodeIfPresent(drawingCanvasSize, forKey: .drawingCanvasSize)
        try container.encodeIfPresent(backgroundImageData, forKey: .backgroundImageData)
        try container.encode(pinned, forKey: .pinned)
        try container.encodeIfPresent(color.flatMap { CodableColor($0) }, forKey: .color)
        try container.encodeIfPresent(reminder, forKey: .reminder)
        try container.encodeIfPresent(notificationIdentifiers, forKey: .notificationIdentifiers)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(tags, forKey: .tags)
        try container.encode(isProtected, forKey: .isProtected)
    }
}
