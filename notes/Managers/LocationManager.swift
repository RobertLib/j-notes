//
//  LocationManager.swift
//  notes
//
//  Created by Robert Libšanský on 20.08.2022.
//

import MapKit
import OSLog
import SwiftUI

/// Where the map camera starts before any fix is available (Prague city centre).
/// Only ever used to frame the map — never stored on a note.
let defaultMapCenter = CLLocationCoordinate2D(latitude: 50.0495641, longitude: 14.4362814)

/// A delivered location fix, in a type this app owns.
///
/// The map used to observe `MKCoordinateRegion` through `.onChange`, which meant
/// conforming it to `Equatable` retroactively — the same trap the note's colour
/// was pulled out of: the day MapKit ships its own conformance, that stops
/// compiling. Views watch this instead.
struct LocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    /// Which delivery this is, counted from the start of the process.
    ///
    /// Part of the value because the coordinates alone do not make a delivery
    /// distinct. `requestLocation()` hands back a cached reading when one is recent
    /// enough, so asking again while standing still delivers the very same numbers
    /// — and views watch this through `onChange`, which compares. A repeat fix
    /// therefore read as "nothing happened", which is exactly the case the map's
    /// locate button consists of: it asks for a fix and moves the camera when one
    /// lands, so standing still made the button do nothing at all.
    let sequence: Int
}

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    /// A fix older than this is no longer trusted to describe where the user is
    /// standing right now. Framing the map with a stale coordinate is harmless,
    /// stamping it onto a new note is not.
    static let maxFixAge: TimeInterval = 5 * 60

    @ObservationIgnored
    var lastLocationStorage: String? {
        get { UserDefaults.standard.string(forKey: "lastLocation") }
        set { UserDefaults.standard.set(newValue, forKey: "lastLocation") }
    }

    @ObservationIgnored
    var lastLocationDateStorage: Date? {
        get { UserDefaults.standard.object(forKey: "lastLocationDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastLocationDate") }
    }

    /// The last real fix, or `nil` when the device has not reported one yet.
    /// Deliberately not defaulted to a placeholder coordinate — a note must
    /// never be stamped with a location the user was never at.
    ///
    /// May be arbitrarily old: it survives in `UserDefaults` between launches so
    /// the map has somewhere to point. Use `recentLocation` to stamp a note.
    var lastLocation: [Double]? {
        guard let stored = lastLocationStorage else { return nil }

        let components = stored.split(separator: ",")

        guard components.count >= 2,
              let latitude = Double(components[0]),
              let longitude = Double(components[1])
        else {
            return nil
        }

        return [latitude, longitude]
    }

    /// The last fix, but only while it is fresh enough to describe where the
    /// user is now. A note created shortly after launch must not inherit
    /// yesterday's coordinate from another city.
    var recentLocation: [Double]? {
        guard let location = lastLocation,
              let fixDate = lastLocationDateStorage,
              Date().timeIntervalSince(fixDate) <= Self.maxFixAge
        else {
            return nil
        }

        return location
    }

    var region = MKCoordinateRegion()

    /// The most recent fix Core Location has delivered to this process, for views
    /// that need to react to a new one arriving. `nil` until one does — a fix
    /// restored from `UserDefaults` does not count, since nothing new happened.
    private(set) var latestFix: LocationFix?

    @ObservationIgnored
    private let manager = CLLocationManager()

    /// How many fixes this process has been handed, which is what makes each one
    /// distinguishable from the last — see `LocationFix.sequence`.
    @ObservationIgnored
    private var deliveredFixCount = 0

    /// The authorization status this manager has already acted on.
    ///
    /// Needed because `locationManagerDidChangeAuthorization` does not only report
    /// changes: Core Location also calls it once simply because a delegate was
    /// assigned. That callback asks for a fix — on the assumption that a grant has
    /// just landed — so every launch of an already-authorized app requested the
    /// user's location, whether or not they ever opened the map or wrote a note.
    ///
    /// Seeded from the real status *before* the delegate is set, so the callback
    /// that assignment provokes recognises itself as no change at all.
    @ObservationIgnored
    private var handledAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()

        let center = lastLocation.map {
            CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])
        } ?? defaultMapCenter

        region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: 0.2,
                longitudeDelta: 0.2
            )
        )

        // Read before the delegate is assigned, so the callback that assignment
        // provokes has something to compare against — see
        // `handledAuthorizationStatus`.
        handledAuthorizationStatus = manager.authorizationStatus

        manager.delegate = self

        // A note records roughly where it was written, and the map frames it in a
        // 0.2° span — about 20km across. `Best`, the default, powers up the GPS for
        // metre-level precision that nothing here reads, on a request the note form
        // makes every time it opens.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Whether a status lets this app ask Core Location where the device is.
    ///
    /// Split out as a pure function so the rule has one spelling and can be
    /// exercised at all — a test process cannot be granted location authorization,
    /// so neither `isAuthorized` nor the callback below is reachable end to end.
    static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// Whether the user has refused, so asking again produces neither a prompt nor
    /// a fix. The map says so rather than letting its locate button do nothing.
    static func isDenied(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    /// Whether an authorization callback reporting `status` is a reason to ask for
    /// a fix.
    ///
    /// Only a *change* into an authorized state is. Core Location calls the
    /// delegate once merely because it was assigned, reporting whatever status was
    /// already in force — and treating that as a fresh grant meant every launch of
    /// an already-authorized app went and got the user's location, with the status
    /// bar indicator to match, however little of the app they went on to use.
    ///
    /// Split out as a pure function for the same reason as `isAuthorized`.
    static func shouldRequestFix(
        for status: CLAuthorizationStatus,
        previously previous: CLAuthorizationStatus
    ) -> Bool {
        status != previous && isAuthorized(status)
    }

    /// Whether this app may ask Core Location where the device is.
    ///
    /// Read imperatively, at the moment a note is created or a fix is asked for,
    /// so it goes straight to `CLLocationManager` rather than mirroring the status
    /// into observable state of its own. A published copy used to sit beside it
    /// that no view ever read.
    var isAuthorized: Bool {
        Self.isAuthorized(manager.authorizationStatus)
    }

    /// Whether asking for a fix would be refused outright — see `isDenied(_:)`.
    var isDenied: Bool {
        Self.isDenied(manager.authorizationStatus)
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()

        if isAuthorized {
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        Task { @MainActor in
            let previous = handledAuthorizationStatus
            handledAuthorizationStatus = status

            // Only a grant that has just landed, not the status merely being
            // reported back — see `shouldRequestFix(for:previously:)`.
            guard Self.shouldRequestFix(for: status, previously: previous) else {
                return
            }

            // The grant that `requestLocation()` asked for is in, so the fix it
            // could not make at the time is made now.
            self.manager.requestLocation()
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
            // Taken from the fix itself rather than "now" — Core Location can
            // hand back a cached reading that is already minutes old.
            lastLocationDateStorage = location.timestamp

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

            // Counted so a repeat of the same coordinates is still a new value —
            // see `LocationFix.sequence`.
            deliveredFixCount += 1

            latestFix = LocationFix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                sequence: deliveredFixCount
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            switch (error as? CLError)?.code {
            case .denied:
                Log.location.notice("Location access denied by user")
            case .locationUnknown:
                Log.location.notice("Location temporarily unavailable")
            case .network:
                Log.location.notice("Network error while getting location")
            default:
                Log.location.error("Location manager error: \(error.localizedDescription)")
            }
        }
    }
}
