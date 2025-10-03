//
//  NoteFormView.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import SwiftUI

struct NoteFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var notesStore: NotesStore

    let note: NoteModel?

    @State private var title: String
    @State private var content: String
    @State private var color: Color
    @State private var isColorOn: Bool
    @State private var reminder: Date
    @State private var isReminderOn: Bool

    @State private var isContentErrorPresented = false

    init(note: NoteModel? = nil) {
        self.note = note

        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.content ?? "")
        _color = State(initialValue: note?.color ?? .primary)
        _isColorOn = State(initialValue: note?.color != nil)
        _reminder = State(initialValue: note?.reminder ?? Date())

        _isReminderOn = State(
            initialValue: note?.reminder == nil
                ? false
                : note?.reminder ?? Date() > Date()
        )
    }

    private func submit() {
        guard !content.isEmpty else {
            isContentErrorPresented = true
            return
        }

        Task {
            // Remove old notifications if updating
            await NotificationManager.instance.removeNotifications(
                identifiers: note?.notificationIdentifiers
            )

            var notificationIdentifiers: [String] = []

            if isReminderOn {
                let notificationIdentifier =
                    await NotificationManager.instance.scheduleNotification(
                        title: title.isEmpty ? String(localized: "note") : title,
                        subtitle: content,
                        date: reminder
                    )

                notificationIdentifiers.append(notificationIdentifier)
            }

            if let note = note {
                notesStore.update(
                    note: note,
                    title: title,
                    content: content,
                    color: color,
                    isColorOn: isColorOn,
                    reminder: reminder,
                    isReminderOn: isReminderOn,
                    notificationIdentifiers: notificationIdentifiers,
                    location: locationManager.isAuthorized
                        ? locationManager.lastLocation
                        : nil
                )
            } else {
                notesStore.add(
                    title: title,
                    content: content,
                    color: color,
                    isColorOn: isColorOn,
                    reminder: reminder,
                    isReminderOn: isReminderOn,
                    notificationIdentifiers: notificationIdentifiers,
                    location: locationManager.isAuthorized
                        ? locationManager.lastLocation
                        : nil
                )
            }

            dismiss()
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("title", text: $title)

                ZStack(alignment: .topLeading) {
                    if content.isEmpty {
                        Text("content")
                            .foregroundColor(Color(.placeholderText))
                            .offset(y: 8)
                    }

                    TextEditor(text: $content)
                        .frame(minHeight: 125)
                        .offset(x: -5)
                        .alert(
                            "contentError",
                            isPresented: $isContentErrorPresented
                        ) {}
                }

                Toggle("color", isOn: $isColorOn.animation())

                if isColorOn {
                    ColorPicker("", selection: $color)
                }

                Toggle("reminder", isOn: $isReminderOn.animation())
                    .onChange(of: isReminderOn) { oldValue, newValue in
                        if newValue {
                            // Default to 5 minutes from now
                            let defaultReminderInterval: TimeInterval = 5 * 60
                            reminder = Date().addingTimeInterval(defaultReminderInterval)

                            Task {
                                await NotificationManager.instance.requestAuthorization()
                            }
                        }
                    }

                if isReminderOn {
                    DatePicker("", selection: $reminder, in: Date()...)
                }

                Button("save") {
                    submit()
                }
                .disabled(content.isEmpty)
            }
        }
        .onAppear() {
            locationManager.requestLocation()
        }
        .onSubmit {
            submit()
        }
    }
}

#Preview {
    NoteFormView()
        .environmentObject(LocationManager())
        .environmentObject(NotesStore())
}
