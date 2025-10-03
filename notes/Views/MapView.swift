//
//  MapView.swift
//  notes
//
//  Created by Robert Libšanský on 20.08.2022.
//

import MapKit
import SwiftUI

struct MapView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var notesStore: NotesStore

    @State private var selectedNote: NoteModel? = nil
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(notesStore.notes) { note in
                    Annotation(note.title, coordinate: note.coordinate) {
                        Button {
                            selectedNote = note
                        } label: {
                            Image(systemName: "note.text")
                                .frame(width: 40, height: 40)
                                .background(note.color ?? .gray.opacity(0.6))
                                .background(.white)
                                .foregroundColor(.white)
                                .font(.system(size: 20))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea(.all, edges: .top)
            .sheet(item: $selectedNote) { note in
                NoteDetailView(note: note, fromMap: true)
            }
            .onAppear {
                updateCameraPosition()
            }
            .onReceive(locationManager.$region) { newRegion in
                position = .region(newRegion)
            }

            Button {
                locationManager.requestLocation()
            } label: {
                Image(systemName: "location")
                    .frame(width: 50, height: 50)
                    .background(.background)
                    .font(.system(size: 20))
                    .clipShape(Circle())
                    .padding()
            }
        }
    }

    private func updateCameraPosition() {
        let region = locationManager.region
        position = .region(region)
    }
}

#Preview {
    MapView()
        .environmentObject(LocationManager())
        .environmentObject(NotesStore())
}
