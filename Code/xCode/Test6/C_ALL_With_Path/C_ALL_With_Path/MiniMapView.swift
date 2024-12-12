//
//  MiniMapView.swift
//  C_ALL_With_Path
//
//  Created by SSW - Design Team  on 12/11/24.
//

import SwiftUI
import MapKit

struct MiniMapView: UIViewRepresentable {
    var routeCoordinates: [CLLocationCoordinate2D]
    var userLocation: CLLocation?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations.filter { !$0.isEqual(uiView.userLocation) })

        // Show route if available
        if !routeCoordinates.isEmpty {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            uiView.addOverlay(polyline)

            // Adjust region
            if let userLoc = userLocation {
                let allCoords = routeCoordinates + [userLoc.coordinate]
                let rect = MKPolyline(coordinates: allCoords, count: allCoords.count).boundingMapRect
                uiView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10), animated: false)
            } else {
                uiView.showAnnotations(uiView.annotations, animated: false)
            }
        } else {
            // Just center on user if route not available
            if let userLoc = userLocation {
                let region = MKCoordinateRegion(center: userLoc.coordinate, latitudinalMeters: 200, longitudinalMeters: 200)
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
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
