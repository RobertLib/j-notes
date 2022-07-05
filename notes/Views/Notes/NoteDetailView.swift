//
//  NoteDetailView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notesStore: NotesStore
    
    let note: NoteModel
    let fromMap: Bool
    
    init(note: NoteModel) {
        self.note = note
        self.fromMap = false
    }
    
    init(note: NoteModel, fromMap: Bool) {
        self.note = note
        self.fromMap = fromMap
    }
    
    @State private var isDeleteNoteConfirmPresented = false
    
    private func share() {
        let activityVC = UIActivityViewController(
            activityItems: ["\(note.title): \(note.content)"],
            applicationActivities: nil
        )
        
        activityVC.setValue(note.title, forKey: "Subject")
        
        UIApplication
            .shared
            .connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .first { $0.isKeyWindow }?
            .rootViewController?
            .present(activityVC, animated: true)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if fromMap {
                    Text(note.createdAt.timeAgoDisplay())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 25)
                    
                    if !note.title.isEmpty {
                        Text(note.title).font(.title2)
                    }
                }
                
                Text("\(note.content)")
                
                if fromMap {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(note.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    share()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    NoteFormView(note: note).navigationTitle("editNote")
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    isDeleteNoteConfirmPresented = true
                } label: {
                    Image(systemName: "trash")
                }
                .confirmationDialog(
                    "deleteNoteConfirm",
                    isPresented: $isDeleteNoteConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("delete", role: .destructive) {
                        NotificationManager.instance.removeNotifications(
                            identifiers: note.notificationIdentifiers
                        )
                        
                        notesStore.remove(note: note)
                        
                        dismiss()
                    }
                    
                    Button("cancel", role: .cancel) {
                        isDeleteNoteConfirmPresented = false
                    }
                }
            }
        }
    }
}

struct NoteDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NoteDetailView(
                note: NoteModel(title: "Title", content: "Lorem ipsum")
            )
        }.environmentObject(NotesStore())
    }
}
