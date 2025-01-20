import SwiftUI
import ARKit
import RealityKit
import CoreLocation

struct ARWrapper: UIViewRepresentable {
    @Binding var routeCoordinates: [CLLocationCoordinate2D]

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Check ARGeoTracking availability
        guard ARGeoTrackingConfiguration.isSupported else {
            print("ARGeoTracking is NOT supported on this device.")
            return arView
        }

        // Optionally, check region coverage:
        ARGeoTrackingConfiguration.checkAvailability { (available, error) in
            if let error = error {
                print("GeoTracking availability check error: \(error.localizedDescription)")
            }
            if !available {
                print("GeoTracking not available in this region, or not enough map data.")
            } else {
                print("GeoTracking is available in this region!")
            }
        }

        let config = ARGeoTrackingConfiguration()
        config.environmentTexturing = .automatic

        // If device can do mesh + classification
        if ARGeoTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }

        // Start AR session
        arView.session.run(config)
        arView.session.delegate = context.coordinator
        print("ARGeoTracking session started.")

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateRoute(uiView, routeCoordinates)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSessionDelegate {
        // We'll keep references to placed anchors
        private var geoAnchors = [ARAnchor]()

        // Called when AR session fails
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("ARSession error: \(error.localizedDescription)")
        }

        // We can track camera updates, if needed
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // e.g., handle debugging or camera pose
        }

        // Called when new anchors are added
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let geoAnchor = anchor as? ARGeoAnchor {
                    print("ARGeoAnchor added, lat:\(geoAnchor.coordinate.latitude), lon:\(geoAnchor.coordinate.longitude)")
                }
            }
        }

        // Called when anchors are updated (important for geo anchors)
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let arView = session.delegate as? ARView else { return }

            for anchor in anchors {
                // If it's a geo anchor, check if it's localized yet
                if let geoAnchor = anchor as? ARGeoAnchor {
                    switch geoAnchor.trackingState {
                    case .localized:
                        // If we haven't already added a visible entity:
                        if !arView.scene.anchors.contains(where: { entityAnchor in
                            guard let anchorEntity = entityAnchor as? AnchorEntity else { return false }
                            return anchorEntity.name == anchor.identifier.uuidString
                        }) {
                            // Attach a sphere anchor at geoAnchor's transform
                            print("GeoAnchor localized, placing sphere at lat:\(geoAnchor.coordinate.latitude), lon:\(geoAnchor.coordinate.longitude)")

                            let sphereAnchor = AnchorEntity(world: geoAnchor.transform)
                            sphereAnchor.name = anchor.identifier.uuidString

                            let sphere = ModelEntity(
                                mesh: .generateSphere(radius: 0.15),
                                materials: [SimpleMaterial(color: .green, roughness: 0.2, isMetallic: false)]
                            )

                            sphereAnchor.addChild(sphere)
                            arView.scene.addAnchor(sphereAnchor)
                        }

                    case .localizing:
                        print("GeoAnchor is localizing (lat:\(geoAnchor.coordinate.latitude))")
                    case .notAvailable:
                        print("GeoAnchor not available.")
                    @unknown default:
                        break
                    }
                }
            }
        }

        // MARK: - Placing GeoAnchors for route coordinates

        func updateRoute(_ arView: ARView, _ coords: [CLLocationCoordinate2D]) {
            guard !coords.isEmpty else {
                print("No route coords to place.")
                return
            }

            // Remove old geo anchors from the session
            for anchor in geoAnchors {
                arView.session.remove(anchor: anchor)
            }
            geoAnchors.removeAll()

            print("Placing ARGeoAnchor for each route coord: \(coords.count) points")

            // Create ARGeoAnchor for each route coordinate
            for c in coords {
                let anchor = ARGeoAnchor(coordinate: c)
                geoAnchors.append(anchor)
                arView.session.add(anchor: anchor)
            }
        }
    }
}
