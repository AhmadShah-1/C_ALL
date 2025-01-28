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
    
    /// Whether ARKit’s geotracking is localized (for UI display).
    @State private var isGeoLocalized = false
    
    /// Example toggle to demonstrate other UI elements
    @State private var forceLocalMode = false
    
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
            
            // If the sheet was just dismissed
            if oldValue && !newValue {
                if let destination = selectedCoordinate,
                   let userLoc = locationManager.location?.coordinate {
                    
                    print("[ContentView] Map sheet dismissed, have destination lat=\(destination.latitude), lon=\(destination.longitude). Fetching OSM route!")
                    
                    // Instead of Apple’s MKDirections, use OSM foot-walking data:
                    fetchOSMWalkableRoute(from: userLoc, to: destination) { coords in
                        guard let coords = coords, !coords.isEmpty else {
                            print("[ContentView] OSM route fetch returned no coordinates.")
                            return
                        }
                        // Optionally resample them for anchor spacing
                        let spacedCoords = resampleCoordinates(from: coords, spacingMeters: 5.0)
                        
                        // Update the AR route
                        DispatchQueue.main.async {
                            self.routeCoordinates = spacedCoords
                            print("[ContentView] OSM route found \(coords.count) coords; resampled to \(spacedCoords.count).")
                        }
                    }
                } else {
                    print("[ContentView] Map sheet dismissed, but no destination or userLoc missing.")
                }
            }
        }
    }
}

// MARK: - OpenRouteService OSM-based "foot-walking" route
extension ContentView {
    
    /// Fetch a walking/sidewalk route from OpenRouteService, returning raw coordinates (lon-lat order -> lat-lon).
    func fetchOSMWalkableRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        completion: @escaping ([CLLocationCoordinate2D]?) -> Void
    ) {
        // Replace with your real ORS API key
        let apiKey = "5b3ce3597851110001cf624890ecd5b750e3402a818663b03cbc6f07"
        
        // ORS wants coordinates as "lon,lat"
        let urlString = """
        https://api.openrouteservice.org/v2/directions/foot-walking?api_key=\(apiKey)&start=\(origin.longitude),\(origin.latitude)&end=\(destination.longitude),\(destination.latitude)
        """
        
        guard let url = URL(string: urlString) else {
            print("[fetchOSMWalkableRoute] Invalid URL string.")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let e = error {
                print("[fetchOSMWalkableRoute] error => \(e.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[fetchOSMWalkableRoute] No data or bad status code.")
                completion(nil)
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(OpenRouteServiceResponse.self, from: data)
                guard let feature = decoded.features.first else {
                    print("[fetchOSMWalkableRoute] No features found in response.")
                    completion(nil)
                    return
                }
                // Convert [lon, lat] arrays to CLLocationCoordinate2D
                let routeCoords = feature.geometry.coordinates.map { arr -> CLLocationCoordinate2D in
                    CLLocationCoordinate2D(latitude: arr[1], longitude: arr[0])
                }
                
                completion(routeCoords)
            } catch {
                print("[fetchOSMWalkableRoute] JSON parse error => \(error)")
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - ORS Response Models
struct OpenRouteServiceResponse: Decodable {
    let features: [Feature]
    
    struct Feature: Decodable {
        let geometry: Geometry
    }
    
    struct Geometry: Decodable {
        let coordinates: [[Double]] // each [lon, lat]
    }
}

// MARK: - MKPolyline Helper
// (No longer used for Apple’s MKDirections, but we can still use if needed for debugging)
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

// MARK: - (Optional) Resample for consistent anchor spacing
func resampleCoordinates(
    from coords: [CLLocationCoordinate2D],
    spacingMeters: Double = 1.0
) -> [CLLocationCoordinate2D] {
    guard coords.count > 1 else { return coords }

    var result: [CLLocationCoordinate2D] = []
    result.reserveCapacity(coords.count * 10) // just a guess

    // Start with the first point
    result.append(coords[0])
    var previousCoord = coords[0]

    for i in 1..<coords.count {
        let currentCoord = coords[i]
        
        // Distance between previous and current
        let dist = distanceBetween(previousCoord, currentCoord)
        
        // If less than spacing, skip (or just append final if end)
        guard dist >= spacingMeters else {
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

private func distanceBetween(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
    let loc1 = CLLocation(latitude: c1.latitude, longitude: c1.longitude)
    let loc2 = CLLocation(latitude: c2.latitude, longitude: c2.longitude)
    return loc1.distance(from: loc2)
}

/// Bearing in degrees from c1 to c2 (0 = north, 90 = east, etc.)
private func bearingBetween(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
    let lat1 = degreesToRadians(c1.latitude)
    let lon1 = degreesToRadians(c1.longitude)
    let lat2 = degreesToRadians(c2.latitude)
    let lon2 = degreesToRadians(c2.longitude)
    let dLon = lon2 - lon1
    
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let radBearing = atan2(y, x)
    
    return radiansToDegrees(radBearing).normalizedHeading()
}

/// Returns a new coordinate by moving `distanceMeters` on a given bearing from `coord`.
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
    let lon2 = lon1 + atan2(
        sin(bearingRad) * sin(distanceMeters / radiusEarth) * cos(lat1),
        cos(distanceMeters / radiusEarth) - sin(lat1) * sin(lat2)
    )
    
    return CLLocationCoordinate2D(
        latitude: radiansToDegrees(lat2),
        longitude: radiansToDegrees(lon2)
    )
}

// Utility
private func degreesToRadians(_ deg: Double) -> Double {
    deg * .pi / 180.0
}
private func radiansToDegrees(_ rad: Double) -> Double {
    rad * 180.0 / .pi
}
private extension Double {
    /// Normalize heading into [0, 360)
    func normalizedHeading() -> Double {
        let mod = fmod(self, 360.0)
        return mod < 0 ? mod + 360.0 : mod
    }
}
