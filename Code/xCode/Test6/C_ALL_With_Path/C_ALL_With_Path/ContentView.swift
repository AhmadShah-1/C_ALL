import SwiftUI
import MapKit

struct ContentView: View {
    @State private var showMap = false
    
    /// The coordinate the user picks on the map
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    /// The route coordinates used in ARWrapper
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    
    /// Location manager for user location
    @StateObject private var locationManager = LocationManager()
    
    /// Optionally toggle to force local AR fallback
    @State private var forceLocalMode = false
    
    /// Now we match ARWrapper's third parameter (Binding<Bool>).
    @State private var isGeoLocalized = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            // 1) AR view
            ARWrapper(
                routeCoordinates: $routeCoordinates,
                userLocation: $locationManager.location,
                // ARWrapper expects isGeoLocalized: Binding<Bool>, so pass $isGeoLocalized
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
            routeCoordinates = polyline.coordinates
            print("[ContentView] Route found with \(routeCoordinates.count) coords => routeCoordinates updated.")
        }
    }
}

// MARK: - Helper
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
