//
//  NoteRowView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

struct NoteRowView: View {
    let note: NoteModel
    
    var body: some View {
        NavigationLink {
            NoteDetailView(note: note)
        } label: {
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
                        
                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.accentColor.opacity(0.75))
                        }
                    }
                    
                    if !note.title.isEmpty {
                        Text(note.title).font(.title2)
                    }
                    
                    Text(note.content).lineLimit(2).truncationMode(.tail)
                    
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
    }
}

struct NoteRowView_Previews: PreviewProvider {
    static var previews: some View {
        NoteRowView(
            note: NoteModel(
                title: "Title",
                content: "Lorem ipsum",
                pinned: true,
                reminder: Date()
            )
        )
    }
}
