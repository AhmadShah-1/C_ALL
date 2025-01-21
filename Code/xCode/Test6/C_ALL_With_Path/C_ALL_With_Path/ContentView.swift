import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @State private var showMap = false
    
    /// The coordinate the user picks on the map
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    /// The route coordinates used in ARWrapper
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    
    /// Location manager for user location
    @StateObject private var locationManager = LocationManager()
    
    /// Optionally toggle to force local AR fallback (not used in this snippet)
    @State private var forceLocalMode = false
    
    /// Matches ARWrapper's third parameter (Binding<Bool>).
    @State private var isGeoLocalized = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            // 1) AR view
            ARWrapper(
                routeCoordinates: $routeCoordinates,
                userLocation: $locationManager.location,
                isGeoLocalized: $isGeoLocalized
            )
            .edgesIgnoringSafeArea(.all)
            
            // 2) Mini-map overlay
            MiniMapView(
                routeCoordinates: routeCoordinates,
                userLocation: locationManager.location
            )
            .frame(width: 150, height: 150)
            .padding()
            
            // 3) UI controls
            VStack {
                Toggle("Force Local AR", isOn: $forceLocalMode)
                    .toggleStyle(.button)
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                
                Button("Select Destination") {
                    print("[ContentView] 'Select Destination' tapped -> showMap = true")
                    showMap = true
                }
                .padding()
                .background(Color.white.opacity(0.8))
                .cornerRadius(10)
            }
            .padding()
        }
        // Start/stop location updates
        .onAppear {
            print("[ContentView] onAppear -> startUpdating()")
            locationManager.startUpdating()
        }
        .onDisappear {
            print("[ContentView] onDisappear -> stopUpdating()")
            locationManager.stopUpdating()
        }
        // Present the map as a sheet
        .sheet(isPresented: $showMap) {
            MapView(
                selectedCoordinate: $selectedCoordinate,
                locationManager: locationManager,
                isPresented: $showMap
            )
        }
        // iOS 17 style: two-parameter onChange
        .onChange(of: showMap) { oldValue, newValue in
            print("[ContentView] onChange(showMap) old=\(oldValue), new=\(newValue)")
            
            // If the sheet was dismissed (oldValue=true -> newValue=false)...
            if oldValue && !newValue {
                if let destination = selectedCoordinate,
                   let userLoc = locationManager.location?.coordinate {
                    
                    print("[ContentView] Map sheet dismissed, have selected destination lat=\(destination.latitude), lon=\(destination.longitude). Calculating route!")
                    calculateRoute(from: userLoc, to: destination)
                } else {
                    print("[ContentView] Map sheet dismissed, but no destination or userLoc missing.")
                }
            }
        }
    }
    
    // MARK: - Calculate Route
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        print("[ContentView] calculateRoute from lat=\(from.latitude), lon=\(from.longitude) to lat=\(to.latitude), lon=\(to.longitude)")
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let e = error {
                print("[ContentView] calculateRoute error: \(e.localizedDescription)")
                return
            }
            guard let route = response?.routes.first else {
                print("[ContentView] No routes found in directions response.")
                return
            }
            let polyline = route.polyline
            let rawCoords = polyline.coordinates
            
            // ************** NEW: Resample to get ~1 meter spacing **************
            let spacedCoords = resampleCoordinates(from: rawCoords, spacingMeters: 5.0)
            
            // Update the binding used by ARWrapper
            self.routeCoordinates = spacedCoords
            
            print("[ContentView] Route found with \(rawCoords.count) raw coords; resampled to \(spacedCoords.count).")
        }
    }
}

// MARK: - MKPolyline Helper
extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}

// MARK: - 1-meter spacing utility
// You can place this here or in a separate file
func resampleCoordinates(
    from coords: [CLLocationCoordinate2D],
    spacingMeters: Double = 1.0
) -> [CLLocationCoordinate2D] {
    guard coords.count > 1 else { return coords }

    var result: [CLLocationCoordinate2D] = []
    result.reserveCapacity(coords.count * 10) // Rough guess to reduce re-allocation

    // Start with the very first point
    result.append(coords[0])
    var previousCoord = coords[0]

    for i in 1..<coords.count {
        let currentCoord = coords[i]
        
        // Distance between previous and current
        let dist = distanceBetween(previousCoord, currentCoord)
        
        // If less than spacing, just append current and move on
        guard dist >= spacingMeters else {
            // If it's the final point in the entire route, ensure we include it
            if i == coords.count - 1 {
                result.append(currentCoord)
            }
            continue
        }

        // Bearing from previousCoord to currentCoord
        let bearing = bearingBetween(previousCoord, currentCoord)
        
        // Insert as many points as fit in the distance
        var remainingDist = dist
        var lastCoord = previousCoord
        while remainingDist >= spacingMeters {
            let nextCoord = coordinate(
                from: lastCoord,
                distanceMeters: spacingMeters,
                bearingDegrees: bearing
            )
            result.append(nextCoord)
            remainingDist -= spacingMeters
            lastCoord = nextCoord
        }

        // Append the final point if it's the last segment
        if i == coords.count - 1 {
            result.append(currentCoord)
        }

        previousCoord = currentCoord
    }

    return result
}

private func distanceBetween(
    _ coord1: CLLocationCoordinate2D,
    _ coord2: CLLocationCoordinate2D
) -> Double {
    let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
    let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
    return loc1.distance(from: loc2)
}

/// Bearing in degrees from coord1 to coord2 (0 = north, 90 = east, etc.)
private func bearingBetween(
    _ coord1: CLLocationCoordinate2D,
    _ coord2: CLLocationCoordinate2D
) -> Double {
    let lat1 = degreesToRadians(coord1.latitude)
    let lon1 = degreesToRadians(coord1.longitude)
    let lat2 = degreesToRadians(coord2.latitude)
    let lon2 = degreesToRadians(coord2.longitude)
    let dLon = lon2 - lon1
    
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let radBearing = atan2(y, x)
    
    return radiansToDegrees(radBearing).normalizedHeading()
}

/// Returns a new coordinate by moving `distanceMeters` toward `bearingDegrees` from `coord`.
private func coordinate(
    from coord: CLLocationCoordinate2D,
    distanceMeters: Double,
    bearingDegrees: Double
) -> CLLocationCoordinate2D {
    let radiusEarth = 6371000.0
    let bearingRad = degreesToRadians(bearingDegrees)
    let lat1 = degreesToRadians(coord.latitude)
    let lon1 = degreesToRadians(coord.longitude)
    
    let lat2 = asin(sin(lat1) * cos(distanceMeters / radiusEarth)
                    + cos(lat1) * sin(distanceMeters / radiusEarth) * cos(bearingRad))
    let lon2 = lon1 + atan2(sin(bearingRad) * sin(distanceMeters / radiusEarth) * cos(lat1),
                            cos(distanceMeters / radiusEarth) - sin(lat1) * sin(lat2))
    
    return CLLocationCoordinate2D(
        latitude: radiansToDegrees(lat2),
        longitude: radiansToDegrees(lon2)
    )
}

// Degree/radian conversions
private func degreesToRadians(_ degrees: Double) -> Double {
    degrees * .pi / 180.0
}
private func radiansToDegrees(_ radians: Double) -> Double {
    radians * 180.0 / .pi
}

private extension Double {
    /// Normalize any heading angle into [0, 360).
    func normalizedHeading() -> Double {
        let mod = fmod(self, 360.0)
        return mod < 0 ? mod + 360.0 : mod
    }
}
