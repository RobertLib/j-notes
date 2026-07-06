//
//  LocationManager.swift
//  notes
//
//  Created by Robert Libšanský on 20.08.2022.
//

import MapKit
import SwiftUI

let lastLocationInit = "50.0495641,14.4362814"

// Equatable conformance so views can observe region changes via .onChange
extension MKCoordinateRegion: @retroactive Equatable {
    public static func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        lhs.center.latitude == rhs.center.latitude &&
        lhs.center.longitude == rhs.center.longitude &&
        lhs.span.latitudeDelta == rhs.span.latitudeDelta &&
        lhs.span.longitudeDelta == rhs.span.longitudeDelta
    }
}

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored
    var lastLocationStorage: String {
        get { UserDefaults.standard.string(forKey: "lastLocation") ?? lastLocationInit }
        set { UserDefaults.standard.set(newValue, forKey: "lastLocation") }
    }

    var lastLocation: [Double] {
        let location = lastLocationStorage.split(separator: ",")

        var out: [Double] = []

        if location.count >= 2,
            let latitude = Double(location[0]),
            let longitude = Double(location[1])
        {
            out = [latitude, longitude]
        }

        return out
    }

    var region = MKCoordinateRegion()
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored
    private let manager = CLLocationManager()

    override init() {
        super.init()

        let initialLocation = lastLocation.count >= 2 ? lastLocation : [50.0495641, 14.4362814]

        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: initialLocation[0],
                longitude: initialLocation[1]
            ),
            span: MKCoordinateSpan(
                latitudeDelta: 0.2,
                longitudeDelta: 0.2
            )
        )

        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let shouldRequestLocation = status == .authorizedAlways || status == .authorizedWhenInUse

        Task { @MainActor in
            authorizationStatus = status
            if shouldRequestLocation {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            lastLocationStorage =
                "\(location.coordinate.latitude),\(location.coordinate.longitude)"

            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.2,
                    longitudeDelta: 0.2
                )
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            print("❌ Location manager error: \(error.localizedDescription)")

            // Handle specific error cases
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    print("⚠️ Location access denied by user")
                case .locationUnknown:
                    print("⚠️ Location temporarily unavailable")
                case .network:
                    print("⚠️ Network error while getting location")
                default:
                    break
                }
            }
        }
    }
}
