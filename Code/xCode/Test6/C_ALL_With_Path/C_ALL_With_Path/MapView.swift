import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @ObservedObject var locationManager: LocationManager

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator

        // If we know user location, center on them
        if let userLoc = locationManager.location {
            let region = MKCoordinateRegion(center: userLoc.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: false)
        } else {
            // Default to some region if unknown
            let defaultCoord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // SF
            let region = MKCoordinateRegion(center: defaultCoord, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: false)
        }

        // A long-press gesture to pick a destination
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // If user location changes, could update region
        if let userLoc = locationManager.location {
            let region = MKCoordinateRegion(center: userLoc.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            uiView.setRegion(region, animated: true)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            if gesture.state == .began {
                let point = gesture.location(in: mapView)
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

                // Clear old annotations
                mapView.removeAnnotations(mapView.annotations)

                // Place new annotation
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                mapView.addAnnotation(annotation)

                parent.selectedCoordinate = coordinate
                print("Selected coordinate: \(coordinate)")

                // Optionally auto-dismiss the sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    // SwiftUI version: might pop the sheet if needed
                    // e.g. by some binding approach
                }
            }
        }
    }
}
