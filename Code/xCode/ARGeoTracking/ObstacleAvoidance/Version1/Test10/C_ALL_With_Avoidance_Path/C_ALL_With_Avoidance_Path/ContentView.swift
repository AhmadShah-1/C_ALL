import SwiftUI
import MapKit
import CoreLocation
import ARKit

//a sads
struct ContentView: View {
    @State private var showMap = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @StateObject private var locationManager = LocationManager()
    @State private var isGeoLocalized = false
    @State private var forceLocalMode = false
    @State private var currentTargetIndex: Int = 0
    @State private var obstacleOffset: Double = 0
    @State private var depthImage: UIImage? = nil
    @State private var showDepthOverlay: Bool = false  // Toggle for depth view
    @State private var blinkOpacity: Double = 1.0      // For blinking notification
    @State private var lidarAvailable: Bool = false
    @State private var isUsingLidar: Bool = false  // Track whether LiDAR is actively being used
    @State private var showObstacleMeshes: Bool = true  // Add this property
    @State private var depthHorizontalShift: Int = -10  // Default horizontal offset
    @State private var depthVerticalShift: Int = 0      // Default vertical offset
    @State private var showSceneMesh: Bool = false  // Added for ARWrapper

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

    var body: some View {
        ZStack(alignment: .top) {
            // AR experience.
            ARWrapper(
                routeCoordinates: $routeCoordinates,
                userLocation: $locationManager.location,
                isGeoLocalized: $isGeoLocalized,
                obstacleOffset: $obstacleOffset,
                depthImage: $depthImage,
                isUsingLidar: $isUsingLidar,
                showObstacleMeshes: $showObstacleMeshes,
                showSceneMesh: $showSceneMesh,
                depthHorizontalShift: $depthHorizontalShift,
                depthVerticalShift: $depthVerticalShift,
                showDepthOverlay: $showDepthOverlay
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
                    if let userCoord = locationManager.location?.coordinate,
                       let heading = locationManager.heading?.trueHeading,
                       let targetCoord = nextAnchorCoordinate {
                        let bearingToTarget = bearingBetween(userCoord, targetCoord)
                        // Compute relative angle: (bearing to target − user heading) + obstacle offset.
                        let relativeAngle = (bearingToTarget - heading) + obstacleOffset
                        CompassView(angle: relativeAngle)
                            .padding()
                    }
                    
                    // Add sensor method indicators here
                    HStack(spacing: 8) {
                        lidarIcon
                        featurePointsIcon
                    }
                    .padding(.horizontal)
                    
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
                    Toggle("Force Local AR", isOn: $forceLocalMode)
                        .toggleStyle(.button)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                    
                    Button("Select Destination") {
                        showMap = true
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                    
                    Button("Toggle Depth View") {
                        showDepthOverlay.toggle()
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                    
                    Toggle("Show Meshes", isOn: $showObstacleMeshes)
                        .toggleStyle(.button)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                }
                .padding()
            }
            
            // Icons for sensing methods
            HStack(spacing: 8) {
                lidarIcon
                featurePointsIcon
            }
            .padding(.horizontal)
            
            // This should be part of your UI section when showDepthOverlay is true
            if showDepthOverlay {
                VStack {
                    HStack {
                        Button("-") {
                            depthHorizontalShift -= 5
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Text("H: \(depthHorizontalShift)")
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        
                        Button("+") {
                            depthHorizontalShift += 5
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.top, 50)
                    
                    HStack {
                        Button("-") {
                            depthVerticalShift -= 5
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Text("V: \(depthVerticalShift)")
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        
                        Button("+") {
                            depthVerticalShift += 5
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.bottom, 5)
                }
                .position(x: UIScreen.main.bounds.width - 100, y: 100)
                .animation(.easeInOut, value: showDepthOverlay)
            }
        }
        .onAppear {
            locationManager.startUpdating()
            
            // Check for LiDAR capability
            if #available(iOS 14.0, *) {
                // Check using ARKit capabilities
                let deviceHasLiDAR = ARConfiguration.supportsFrameSemantics(.sceneDepth)
                print("DEBUG: Device LiDAR capability check: \(deviceHasLiDAR)")
                lidarAvailable = deviceHasLiDAR
            } else {
                lidarAvailable = false
                print("DEBUG: iOS < 14.0, no LiDAR support")
            }
            
            print("DEBUG: LiDAR availability set to: \(lidarAvailable)")
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .sheet(isPresented: $showMap) {
            MapView(
                selectedCoordinate: $selectedCoordinate,
                locationManager: locationManager,
                isPresented: $showMap
            )
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
            }
        }
    }

    // Icons for sensing methods
    var lidarIcon: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.3.stack.3d.top.fill")
                .font(.system(size: 24))
                .foregroundColor(isUsingLidar ? .green : .gray.opacity(0.5))
            Text("LiDAR")
                .font(.caption)
                .foregroundColor(isUsingLidar ? .green : .gray.opacity(0.5))
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }

    var featurePointsIcon: some View {
        VStack(spacing: 4) {
            Image(systemName: "dot.viewfinder")
                .font(.system(size: 24))
                .foregroundColor(!isUsingLidar ? .yellow : .gray.opacity(0.5))
            Text("Features")
                .font(.caption)
                .foregroundColor(!isUsingLidar ? .yellow : .gray.opacity(0.5))
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
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
