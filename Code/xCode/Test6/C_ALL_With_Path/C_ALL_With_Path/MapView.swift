import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var locationManager: LocationManager

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(parent: MapView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
            if gestureRecognizer.state == .began {
                let mapView = gestureRecognizer.view as! MKMapView
                let point = gestureRecognizer.location(in: mapView)
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

                // Remove existing annotations
                mapView.removeAnnotations(mapView.annotations)

                // Add annotation at the selected point
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                mapView.addAnnotation(annotation)

                // Update the selected coordinate
                parent.selectedCoordinate = coordinate
            } else if gestureRecognizer.state == .ended {
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // Zoom into user's current location if available
        if let userLocation = locationManager.location {
            let region = MKCoordinateRegion(center: userLocation.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
        } else {
            // Default region if user location not available
            let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // SF
            let region = MKCoordinateRegion(center: defaultCoordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
        }

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPressGesture)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let userLocation = locationManager.location {
            let region = MKCoordinateRegion(center: userLocation.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            uiView.setRegion(region, animated: true)
        }
    }
}
