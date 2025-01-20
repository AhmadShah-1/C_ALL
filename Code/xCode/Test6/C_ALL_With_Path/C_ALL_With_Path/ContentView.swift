import SwiftUI
import MapKit

struct ContentView: View {
    @State private var showMap = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 1) AR wrapper that uses ARGeoTracking to place anchors
            ARWrapper(routeCoordinates: $routeCoordinates)
                .edgesIgnoringSafeArea(.all)

            // 2) A small mini-map overlay
            MiniMapView(routeCoordinates: routeCoordinates,
                        userLocation: locationManager.location)
                .frame(width: 150, height: 150)
                .padding()

            // 3) Button to open map for selecting a destination
            VStack {
                Spacer()
                Button("Select Destination") {
                    showMap = true
                }
                .padding()
                .background(Color.white.opacity(0.8))
                .cornerRadius(10)
                .padding()
            }
        }
        .onAppear {
            locationManager.startUpdating()
            print("ContentView: location updates started.")
        }
        .onDisappear {
            locationManager.stopUpdating()
            print("ContentView: location updates stopped.")
        }
        .sheet(isPresented: $showMap, onDismiss: {
            if let destination = selectedCoordinate,
               let userLocation = locationManager.location?.coordinate {
                print("User picked a destination: \(destination)")
                calculateRoute(from: userLocation, to: destination)
            } else {
                print("No destination or user location is missing.")
            }
        }) {
            // The map view for picking a coordinate
            MapView(selectedCoordinate: $selectedCoordinate,
                    locationManager: locationManager)
        }
    }

    // Using MKDirections to get route steps
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        print("Calculating route from \(from) to \(to)")
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let error = error {
                print("Failed to calculate route: \(error.localizedDescription)")
                return
            }
            if let route = response?.routes.first {
                // Extract coordinates
                let polyline = route.polyline
                routeCoordinates = polyline.coordinates
                print("Route found with \(routeCoordinates.count) coords.")
            } else {
                print("No route found.")
            }
        }
    }
}

// MARK: - A helper extension to get coordinates from MKPolyline
extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
