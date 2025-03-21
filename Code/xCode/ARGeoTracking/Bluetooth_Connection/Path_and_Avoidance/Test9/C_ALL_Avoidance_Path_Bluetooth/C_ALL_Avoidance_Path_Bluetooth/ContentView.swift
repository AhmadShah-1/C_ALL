import SwiftUI
import MapKit
import CoreLocation
import CoreBluetooth

struct ContentView: View {
    @State private var showMap = false
    @State private var showBluetoothSheet = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject private var bluetoothService: BluetoothService
    @State private var isGeoLocalized = false
    @State private var forceLocalMode = false
    @State private var currentTargetIndex: Int = 0
    @State private var obstacleOffset: Double = 0
    @State private var depthImage: UIImage? = nil
    @State private var showDepthOverlay: Bool = false  // Toggle for depth view
    @State private var blinkOpacity: Double = 1.0      // For blinking notification
    @State private var currentCompassAngle: Double = 0

    /// Returns the current target coordinate from the route.
    var nextAnchorCoordinate: CLLocationCoordinate2D? {
        guard !routeCoordinates.isEmpty, currentTargetIndex < routeCoordinates.count else { return nil }
        return routeCoordinates[currentTargetIndex]
    }

    /// Calculates the bearing (in degrees) from coordinate c1 to coordinate c2.
    func bearingBetween(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180.0 / .pi
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)
        return bearing
    }

    func updateCompassAngle() {
        guard let userCoord = locationManager.location?.coordinate,
              let heading = locationManager.heading?.trueHeading,
              let targetCoord = nextAnchorCoordinate else { return }
        
        let bearingToTarget = bearingBetween(userCoord, targetCoord)
        var relativeAngle = (bearingToTarget - heading) + obstacleOffset
        
        // Normalize to -180 to +180 range
        relativeAngle = (relativeAngle + 180).truncatingRemainder(dividingBy: 360) - 180
        if relativeAngle < -180 {
            relativeAngle += 360
        }
        
        print("[COMPASS_POINTER] userCoord: \(userCoord), heading: \(heading), targetCoord: \(targetCoord), bearingToTarget: \(bearingToTarget), obstacleOffset: \(obstacleOffset), relativeAngle: \(relativeAngle)")
        currentCompassAngle = relativeAngle
        bluetoothService.sendCompassAngle(relativeAngle)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // AR experience.
            ARWrapper(
                routeCoordinates: $routeCoordinates,
                userLocation: $locationManager.location,
                isGeoLocalized: $isGeoLocalized,
                obstacleOffset: $obstacleOffset,
                depthImage: $depthImage
            )
            .edgesIgnoringSafeArea(.all)
            
            // Optionally overlay the depth image.
            if showDepthOverlay, let depthImg = depthImage {
                Image(uiImage: depthImg)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.5)
                    .ignoresSafeArea()
            }
            
            // Top overlay: HStack with Compass (top left) and MiniMap (top right).
            VStack {
                HStack {
                    // Compass at top left.
                    if locationManager.location != nil && 
                       locationManager.heading != nil && 
                       nextAnchorCoordinate != nil {
                        CompassView(angle: currentCompassAngle)
                            .padding()
                            .onChange(of: locationManager.heading) { _ in
                                updateCompassAngle()
                            }
                            .onChange(of: locationManager.location) { _ in
                                updateCompassAngle()
                            }
                            .onChange(of: obstacleOffset) { _ in
                                updateCompassAngle()
                            }
                    }
                    Spacer()
                    // MiniMap at top right.
                    MiniMapView(routeCoordinates: routeCoordinates, userLocation: locationManager.location)
                        .frame(width: 150, height: 150)
                        .padding()
                }
                // Blinking notification if obstacleOffset is nonzero.
                if obstacleOffset != 0 {
                    Text("Obstacle Detected!")
                        .foregroundColor(.red)
                        .font(.headline)
                        .padding(8)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(8)
                        .opacity(blinkOpacity)
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                blinkOpacity = 0.2
                            }
                        }
                        .padding(.top, 10)
                }
                Spacer()
            }
            
            // Bottom UI controls.
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        showBluetoothSheet = true
                    }) {
                        HStack {
                            Image(systemName: bluetoothService.connectedPeripheral != nil ? "bluetooth.circle.fill" : "bluetooth.circle")
                            Text(bluetoothService.connectedPeripheral != nil ? "Connected" : "Connect Bluetooth")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        showMap = true
                    }) {
                        Image(systemName: "map.fill")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.5))
            }
        }
        .onAppear {
            locationManager.startUpdating()
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .sheet(isPresented: $showMap) {
            MapView(selectedCoordinate: $selectedCoordinate, locationManager: locationManager, isPresented: $showMap)
        }
        .sheet(isPresented: $showBluetoothSheet) {
            BluetoothDeviceView()
        }
        .onChange(of: showMap) { oldValue, newValue in
            // When the map sheet is dismissed, fetch a route.
            if oldValue && !newValue {
                if let destination = selectedCoordinate,
                   let userLoc = locationManager.location?.coordinate {
                    fetchOSMWalkableRoute(from: userLoc, to: destination) { coords in
                        guard let coords = coords, !coords.isEmpty else { return }
                        let spacedCoords = resampleCoordinates(from: coords, spacingMeters: 5.0)
                        DispatchQueue.main.async {
                            self.routeCoordinates = spacedCoords
                            self.currentTargetIndex = 0 // Reset target index for new route.
                            updateCompassAngle()
                        }
                    }
                }
            }
        }
        // Update current target index when the user's location changes.
        .onChange(of: locationManager.location) { newLocation in
            guard let newLocation = newLocation,
                  !routeCoordinates.isEmpty,
                  currentTargetIndex < routeCoordinates.count else { return }
            let targetCoord = routeCoordinates[currentTargetIndex]
            let targetLocation = CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude)
            if newLocation.distance(from: targetLocation) < 1.0 {
                currentTargetIndex += 1
                updateCompassAngle()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BluetoothService())
    }
}

extension ContentView {
    /// Fetch a walking route from OpenRouteService.
    func fetchOSMWalkableRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, completion: @escaping ([CLLocationCoordinate2D]?) -> Void) {
        let apiKey = "5b3ce3597851110001cf624890ecd5b750e3402a818663b03cbc6f07" // Replace with your ORS API key.
        let urlString = "https://api.openrouteservice.org/v2/directions/foot-walking?api_key=\(apiKey)&start=\(origin.longitude),\(origin.latitude)&end=\(destination.longitude),\(destination.latitude)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let _ = error {
                completion(nil)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion(nil)
                return
            }
            do {
                let decoded = try JSONDecoder().decode(OpenRouteServiceResponse.self, from: data)
                guard let feature = decoded.features.first else {
                    completion(nil)
                    return
                }
                let routeCoords = feature.geometry.coordinates.map { arr -> CLLocationCoordinate2D in
                    CLLocationCoordinate2D(latitude: arr[1], longitude: arr[0])
                }
                completion(routeCoords)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}

struct OpenRouteServiceResponse: Decodable {
    let features: [Feature]
    struct Feature: Decodable {
        let geometry: Geometry
    }
    struct Geometry: Decodable {
        let coordinates: [[Double]]
    }
}

func resampleCoordinates(from coords: [CLLocationCoordinate2D], spacingMeters: Double = 1.0) -> [CLLocationCoordinate2D] {
    guard coords.count > 1 else { return coords }
    var result: [CLLocationCoordinate2D] = []
    result.reserveCapacity(coords.count * 10)
    result.append(coords[0])
    var previousCoord = coords[0]
    for i in 1..<coords.count {
        let currentCoord = coords[i]
        let dist = distanceBetween(previousCoord, currentCoord)
        guard dist >= spacingMeters else {
            if i == coords.count - 1 { result.append(currentCoord) }
            continue
        }
        let bearing = bearingBetween(previousCoord, currentCoord)
        var remainingDist = dist
        var lastCoord = previousCoord
        while remainingDist >= spacingMeters {
            let nextCoord = coordinate(from: lastCoord, distanceMeters: spacingMeters, bearingDegrees: bearing)
            result.append(nextCoord)
            remainingDist -= spacingMeters
            lastCoord = nextCoord
        }
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

private func coordinate(from coord: CLLocationCoordinate2D, distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
    let radiusEarth = 6371000.0
    let bearingRad = degreesToRadians(bearingDegrees)
    let lat1 = degreesToRadians(coord.latitude)
    let lon1 = degreesToRadians(coord.longitude)
    let lat2 = asin(sin(lat1) * cos(distanceMeters / radiusEarth) +
                    cos(lat1) * sin(distanceMeters / radiusEarth) * cos(bearingRad))
    let lon2 = lon1 + atan2(sin(bearingRad) * sin(distanceMeters / radiusEarth) * cos(lat1),
                            cos(distanceMeters / radiusEarth) - sin(lat1) * sin(lat2))
    return CLLocationCoordinate2D(latitude: radiansToDegrees(lat2), longitude: radiansToDegrees(lon2))
}

private func degreesToRadians(_ deg: Double) -> Double { deg * .pi / 180.0 }
private func radiansToDegrees(_ rad: Double) -> Double { rad * 180.0 / .pi }
private extension Double {
    func normalizedHeading() -> Double {
        let mod = fmod(self, 360.0)
        return mod < 0 ? mod + 360.0 : mod
    }
}
