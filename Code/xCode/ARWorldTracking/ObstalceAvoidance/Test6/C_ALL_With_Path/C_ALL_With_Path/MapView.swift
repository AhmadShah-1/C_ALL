import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @ObservedObject var locationManager: LocationManager
    
    @Binding var isPresented: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        
        if let userLoc = locationManager.location {
            let region = MKCoordinateRegion(center: userLoc.coordinate,
                                            latitudinalMeters: 500,
                                            longitudinalMeters: 500)
            mapView.setRegion(region, animated: false)
        } else {
            // Default region if no location
            let defaultCoord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            let region = MKCoordinateRegion(center: defaultCoord,
                                            latitudinalMeters: 500,
                                            longitudinalMeters: 500)
            mapView.setRegion(region, animated: false)
        }
        
        // Long-press for picking destination
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Optionally recenter on new user location
        if let userLoc = locationManager.location {
            let region = MKCoordinateRegion(center: userLoc.coordinate,
                                            latitudinalMeters: 500,
                                            longitudinalMeters: 500)
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
                let coord = mapView.convert(point, toCoordinateFrom: mapView)
                
                // Remove old pins
                mapView.removeAnnotations(mapView.annotations)
                
                // Add new pin
                let annotation = MKPointAnnotation()
                annotation.coordinate = coord
                mapView.addAnnotation(annotation)
                
                parent.selectedCoordinate = coord
                print("[MapView] Picked coord lat=\(coord.latitude), lon=\(coord.longitude). Dismissing sheet.")
                
                // Dismiss the map sheet
                parent.isPresented = false
            }
        }
    }
}
