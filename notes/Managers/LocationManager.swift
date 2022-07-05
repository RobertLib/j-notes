//
//  LocationManager.swift
//  notes
//
//  Created by Robert Libšanský on 20.08.2022.
//

import MapKit
import SwiftUI

let lastLocationInit = "50.0495641,14.4362814"

class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    @AppStorage("lastLocation") var lastLocationStorage = lastLocationInit
    
    var lastLocation: [Double] {
        let location = lastLocationStorage.split(separator: ",")
        
        var out: [Double] = []
        
        if
            let latitude = Double(location[0]),
            let longitude = Double(location[1])
        {
            out = [latitude, longitude]
        }
        
        return out
    }

    @Published var region = MKCoordinateRegion()
    
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        
        _region = Published(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: lastLocation[0],
                longitude: lastLocation[1]
            ),
            span: MKCoordinateSpan(
                latitudeDelta: 0.2,
                longitudeDelta: 0.2
            )
        ))
        
        manager.delegate = self
    }
    
    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }
    
    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        
        if isAuthorized {
            manager.requestLocation()
        }
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        locations.last.map {
            lastLocationStorage =
                "\($0.coordinate.latitude),\($0.coordinate.longitude)"
            
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.2,
                    longitudeDelta: 0.2
                )
            )
        }
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print(error)
    }
}
