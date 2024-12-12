import SwiftUI
import MapKit

struct ContentView: View {
    @State private var showMap = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // AR view that displays spheres based on routeCoordinates
            ARWrapper(routeCoordinates: $routeCoordinates)
                .edgesIgnoringSafeArea(.all)

            // Mini-map overlay
            MiniMapView(routeCoordinates: routeCoordinates, userLocation: locationManager.location)
                .frame(width: 150, height: 150)
                .padding()

            VStack {
                Spacer()
                Button(action: {
                    showMap = true
                }) {
                    Text("Select Destination")
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                }
                .padding()
            }
        }
        .onAppear {
            locationManager.startUpdating()
            print("ContentView appeared. Location updates started.")
        }
        .onDisappear {
            locationManager.stopUpdating()
            print("ContentView disappeared. Location updates stopped.")
        }
        .sheet(isPresented: $showMap, onDismiss: {
            if let destination = selectedCoordinate, let userLocation = locationManager.location?.coordinate {
                // Calculate route
                print("User selected destination: \(destination)")
                calculateRoute(from: userLocation, to: destination)
            } else {
                print("User location unavailable or destination not selected")
            }
        }) {
            MapView(selectedCoordinate: $selectedCoordinate, locationManager: locationManager)
        }
    }

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
                routeCoordinates = route.polyline.coordinates
                print("Route calculated with \(routeCoordinates.count) coordinates.")
            } else {
                print("No routes found")
            }
        }
    }
}
