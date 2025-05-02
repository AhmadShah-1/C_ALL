import SwiftUI
import MapKit
import CoreLocation
import ARKit
import CoreBluetooth
import Intents

//a sads
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
    @State private var showClusteredDepthOverlay: Bool = false  // Toggle for clustered depth view
    @State private var blinkOpacity: Double = 1.0      // For blinking notification
    @State private var lidarAvailable: Bool = false
    @State private var isUsingLidar: Bool = false  // Track whether LiDAR is actively being used
    @State private var showObstacleMeshes: Bool = true  // Add this property
    @State private var depthHorizontalShift: Int = -10  // Default horizontal offset
    @State private var depthVerticalShift: Int = 0      // Default vertical offset
    @State private var showSceneMesh: Bool = false  // Added for ARWrapper
    @State private var clearPathAngle: Double = 0.0  // Clear path direction angle
    @State private var isPathClear: Bool = false     // Whether a clear path exists
    
    @State private var maxDepthDistance: Float = 4.0  // Fixed maximum depth distance (4 meters)
    @State private var minClearDistance: Float = 1.5  // Default minimum clear distance (meters)
    @State private var showDistanceControls: Bool = false // Toggle for distance controls
    @State private var guidanceInstruction: Int = 0 // State for guidance: -1 Left, 0 Straight/Blocked, 1 Right
    @State private var lastAddressSearched: String = "" // Track last address for Siri donations

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

    // MARK: - Computed Properties for Guidance (NEW LOGIC based on guidanceInstruction)
    
    /// Returns the textual guidance based on the instruction.
    var guidanceText: String {
        switch guidanceInstruction {
        case 3:  // Sharp right turn
            return "TURN RIGHT SHARPLY - Obstacle Left"
        case 2:  // Medium right turn
            return "Turn RIGHT - Obstacle Left"
        case 1:  // Slight right turn
            return "Turn slightly RIGHT"
        case -1: // Slight left turn
            return "Turn slightly LEFT"
        case -2: // Medium left turn
            return "Turn LEFT - Obstacle Right"
        case -3: // Sharp left turn
            return "TURN LEFT SHARPLY - Obstacle Right"
        case 0:  // Straight or Blocked
            if isPathClear {
                return "Proceed Straight"
            } else {
                return "CAUTION: Path Blocked Ahead"
            }
        default:
            return "Analyzing Path..."
        }
    }
    
    /// Returns the color for the guidance message.
    var guidanceColor: Color {
        switch guidanceInstruction {
        case 3, -3: // Sharp turns
            return .red
        case 2, -2: // Medium turns
            return .orange
        case 1, -1: // Slight turns
            return .yellow
        case 0:     // Straight or Blocked
            return isPathClear ? .green : .red
        default:
            return .gray
        }
    }
    
    /// Returns the target angle for the avoidance compass.
    var avoidanceCompassAngle: Double {
        switch guidanceInstruction {
        case 3:  // Sharp right turn
            return 70.0  // Point compass far right
        case 2:  // Medium right turn
            return 45.0  // Point compass medium right
        case 1:  // Slight right turn
            return 20.0  // Point compass slightly right
        case -1: // Slight left turn
            return -20.0 // Point compass slightly left
        case -2: // Medium left turn
            return -45.0 // Point compass medium left
        case -3: // Sharp left turn
            return -70.0 // Point compass far left
        default: // Straight or Blocked
            return 0.0   // Point compass straight
        }
    }
    
    // Update both compass angles and send to Bluetooth
    func updateCompassAngles() {
        guard let userCoord = locationManager.location?.coordinate,
              let heading = locationManager.heading?.trueHeading,
              let targetCoord = nextAnchorCoordinate else { return }
        
        // Calculate target compass angle
        let bearingToTarget = bearingBetween(userCoord, targetCoord)
        let targetRelativeAngle = (bearingToTarget - heading + 360).truncatingRemainder(dividingBy: 360)
        // Normalize to -180 to +180 range for display and servo control
        let normalizedTargetAngle = targetRelativeAngle > 180 ? targetRelativeAngle - 360 : targetRelativeAngle
        
        // Send target angle to Bluetooth if connected
        bluetoothService.sendTargetAngle(normalizedTargetAngle)
        
        // Send avoidance angle to Bluetooth if connected
        bluetoothService.sendAvoidanceAngle(avoidanceCompassAngle)
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
                showDepthOverlay: $showDepthOverlay,
                clearPathAngle: $clearPathAngle,
                isPathClear: $isPathClear,
                showClusteredDepthOverlay: $showClusteredDepthOverlay,
                maxDepthDistance: $maxDepthDistance,
                minClearDistance: $minClearDistance,
                guidanceInstruction: $guidanceInstruction
            )
            .edgesIgnoringSafeArea(.all)
            
            // Optionally overlay the depth image.
            if (showDepthOverlay || showClusteredDepthOverlay), let depthImg = depthImage {
                Image(uiImage: depthImg)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.7)
                    .ignoresSafeArea()
            }
            
            // Direction message at the very top
            if isUsingLidar {
                Text(guidanceText)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(10)
                    .background(guidanceColor.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.top, 10)
                    .padding(.horizontal)
                    .animation(.easeInOut, value: guidanceInstruction)
                    .animation(.easeInOut, value: isPathClear)
            }
            
            // Top overlay: Compasses and MiniMap
            VStack {
                HStack(alignment: .top) {
                    // Left section - Target compass
                    VStack {
                        // Compass at top left - Direct to target destination
                        if let userCoord = locationManager.location?.coordinate,
                           let heading = locationManager.heading?.trueHeading,
                           let targetCoord = nextAnchorCoordinate {
                            let bearingToTarget = bearingBetween(userCoord, targetCoord)
                            // Compute relative angle - no more obstacle offset
                            let relativeAngle = bearingToTarget - heading
                            CompassView(angle: relativeAngle)
                                .padding()
                                .overlay(
                                    Text("Target")
                                        .font(.caption)
                                        .foregroundColor(.black)
                                        .padding(4)
                                        .background(Color.white.opacity(0.8))
                                        .cornerRadius(4)
                                        .offset(y: 40)
                                )
                                .onChange(of: locationManager.heading) { _ in
                                    updateCompassAngles()
                                }
                                .onChange(of: locationManager.location) { _ in
                                    updateCompassAngles()
                                }
                        }
                        
                        // Add sensor method indicators here
                        HStack(spacing: 8) {
                            lidarIcon
                            featurePointsIcon
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Center section - MiniMap
                    MiniMapView(routeCoordinates: routeCoordinates, userLocation: locationManager.location)
                        .frame(width: 120, height: 120)
                        .padding()
                    
                    Spacer()
                    
                    // Right section - Avoidance compass
                    if let heading = locationManager.heading?.trueHeading {
                        // Use the transformed angle that points in the direction to turn
                        AvoidanceCompassView(angle: avoidanceCompassAngle, isPathClear: isPathClear)
                            .padding()
                            .overlay(
                                Text("Turn Direction")
                                    .font(.caption)
                                    .foregroundColor(.black)
                                    .padding(4)
                                    .background(Color.white.opacity(0.8))
                                    .cornerRadius(4)
                                    .offset(y: 40)
                            )
                            .onChange(of: avoidanceCompassAngle) { _ in
                                updateCompassAngles()
                            }
                            .onChange(of: guidanceInstruction) { _ in
                                updateCompassAngles()
                            }
                    }
                }
                
                // Show notification if no clear path is found
                if !isPathClear && isUsingLidar {
                    Text("No Clear Path Found - Proceed with Caution!")
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
                            Text(bluetoothService.connectedPeripheral != nil ? "BT Connected" : "BT Connect")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Toggle("Force Local AR", isOn: $forceLocalMode)
                        .toggleStyle(.button)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                    
                    Button("Select Destination") {
                        showMap = true
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                    
                    Menu {
                        Button("Toggle Full Depth View") {
                            showDepthOverlay.toggle()
                            if showDepthOverlay {
                                showClusteredDepthOverlay = false
                            }
                        }
                        
                        Button("Toggle Clustered Depth") {
                            showClusteredDepthOverlay.toggle()
                            if showClusteredDepthOverlay {
                                showDepthOverlay = false
                            }
                        }
                    } label: {
                        Text("Depth Options")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            
            // This should be part of your UI section when showDepthOverlay is true
            if showDepthOverlay || showClusteredDepthOverlay {
                VStack {
                    // Existing shift controls
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
                    
                    // Add button to show/hide distance controls
                    Button(action: {
                        showDistanceControls.toggle()
                    }) {
                        Text(showDistanceControls ? "Hide Distance Controls" : "Show Distance Controls")
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    // Distance controls
                    if showDistanceControls {
                        VStack(spacing: 10) {
                            Text("Depth Distance Settings")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(5)
                            
                            // Fixed max depth distance display (4.0m)
                            HStack {
                                Text("Max Range:")
                                    .foregroundColor(.white)
                                
                                Text("4.0m (Fixed)")
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            
                            // Min clear distance slider - KEEP THE SAME RANGE
                            HStack {
                                Text("Min: \(String(format: "%.1f", minClearDistance))m")
                                    .foregroundColor(.white)
                                    .frame(width: 80)
                                
                                Slider(value: $minClearDistance, in: 0.5...3.0, step: 0.1)
                                    .accentColor(.yellow)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            
                            // Add helpful information text
                            Text("Fixed 4m range ensures consistent detection and visualization.")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(5)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(10)
                    }
                }
                .position(x: UIScreen.main.bounds.width - 150, y: 150)
                .animation(.easeInOut, value: showDepthOverlay)
                .animation(.easeInOut, value: showDistanceControls)
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
        .sheet(isPresented: $showBluetoothSheet) {
            BluetoothDeviceView()
        }
        .onChange(of: showMap) { oldValue, newValue in
            // When the map sheet is dismissed, fetch a route.
            if oldValue && !newValue {
                if let destination = selectedCoordinate,
                   let userLoc = locationManager.location?.coordinate {
                    setupNavigationRoute(from: userLoc, to: destination)
                    
                    // Donate navigation intent to Siri for future shortcuts
                    if !lastAddressSearched.isEmpty {
                        C_ALL_With_Avoidance_PathApp.donateNavigationIntent(to: destination, with: lastAddressSearched)
                    }
                }
            }
        }
        // Receive Siri notifications
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SiriSelectedDestination"))) { notification in
            if let coordinate = notification.userInfo?["coordinate"] as? CLLocationCoordinate2D {
                self.selectedCoordinate = coordinate
                
                // If we have the user location, fetch the route immediately
                if let userLoc = locationManager.location?.coordinate {
                    setupNavigationRoute(from: userLoc, to: coordinate)
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
                updateCompassAngles() // Update angles when moving to next target
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

    // Update avoidance compass view to show intensity
    struct AvoidanceCompassView: View {
        let angle: Double
        let isPathClear: Bool
        
        var body: some View {
            ZStack {
                Circle()
                    .stroke(isPathClear ? Color.green.opacity(0.5) : Color.red.opacity(0.5), lineWidth: 3)
                    .frame(width: 60, height: 60)
                
                // Direction indicator with size based on angle magnitude
                let absAngle = abs(angle)
                let arrowSize = 20.0 + (absAngle / 90.0) * 10.0 // Size increases with angle
                
                Image(systemName: "arrowtriangle.up.fill")
                    .resizable()
                    .frame(width: arrowSize, height: arrowSize)
                    .foregroundColor(turnIntensityColor)
                    .rotationEffect(.degrees(angle))
                    .animation(.easeInOut, value: angle)
            }
        }
        
        // Color based on turn intensity
        var turnIntensityColor: Color {
            let absAngle = abs(angle)
            if absAngle >= 60.0 {
                return .red       // Sharp turn
            } else if absAngle >= 30.0 {
                return .orange    // Medium turn
            } else if absAngle > 0 {
                return .yellow    // Slight turn
            } else {
                return .green     // No turn
            }
        }
    }

    // Helper method to set up navigation route
    private func setupNavigationRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        fetchOSMWalkableRoute(from: origin, to: destination) { coords in
            guard let coords = coords, !coords.isEmpty else { return }
            let spacedCoords = resampleCoordinates(from: coords, spacingMeters: 5.0)
            DispatchQueue.main.async {
                self.routeCoordinates = spacedCoords
                self.currentTargetIndex = 0 // Reset target index for new route.
                self.updateCompassAngles() // Update angles for new route
            }
        }
        
        // Reverse geocode destination to get the address (for Siri donation)
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: destination.latitude, longitude: destination.longitude)) { placemarks, error in
            if let placemark = placemarks?.first {
                var addressComponents: [String] = []
                
                if let thoroughfare = placemark.thoroughfare {
                    addressComponents.append(thoroughfare)
                }
                
                if let subThoroughfare = placemark.subThoroughfare {
                    // Insert at the beginning if it's a street number
                    if let index = addressComponents.firstIndex(of: placemark.thoroughfare ?? "") {
                        addressComponents.insert(subThoroughfare, at: index)
                    } else {
                        addressComponents.append(subThoroughfare)
                    }
                }
                
                if let locality = placemark.locality {
                    addressComponents.append(locality)
                }
                
                if let administrativeArea = placemark.administrativeArea {
                    addressComponents.append(administrativeArea)
                }
                
                if let postalCode = placemark.postalCode {
                    addressComponents.append(postalCode)
                }
                
                self.lastAddressSearched = addressComponents.joined(separator: " ")
            }
        }
    }
}

// MARK: - Preview Provider

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BluetoothService())
    }
}

// MARK: - Extensions

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
