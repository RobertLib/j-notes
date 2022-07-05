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
    @State private var mapRegion = MKCoordinateRegion()
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(
                coordinateRegion: $mapRegion,
                annotationItems: notesStore.notes,
                annotationContent: { note in
                    MapAnnotation(coordinate: note.coordinate) {
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
            )
            .edgesIgnoringSafeArea(.top)
            .sheet(item: $selectedNote) { note in
                NoteDetailView(note: note, fromMap: true)
            }
            .onAppear {
                self.mapRegion = locationManager.region
            }
            .onReceive(locationManager.$region) { newRegion in
                self.mapRegion = newRegion
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
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView()
            .environmentObject(LocationManager())
            .environmentObject(NotesStore())
    }
}
