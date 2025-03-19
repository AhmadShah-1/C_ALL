import SwiftUI
import MapKit

struct MiniMapView: UIViewRepresentable {
    let routeCoordinates: [CLLocationCoordinate2D]
    let userLocation: CLLocation?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays)
        
        if !routeCoordinates.isEmpty {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            uiView.addOverlay(polyline)
            
            // Fit route + user location if available
            if let userLoc = userLocation {
                let allCoords = routeCoordinates + [userLoc.coordinate]
                let bounding = MKPolyline(coordinates: allCoords, count: allCoords.count).boundingMapRect
                uiView.setVisibleMapRect(bounding, edgePadding: .init(top: 8, left: 8, bottom: 8, right: 8), animated: false)
            }
        } else {
            // Just center user location
            if let userLoc = userLocation {
                let region = MKCoordinateRegion(center: userLoc.coordinate,
                                                latitudinalMeters: 200,
                                                longitudinalMeters: 200)
                uiView.setRegion(region, animated: false)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .green
                renderer.lineWidth = 3.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
