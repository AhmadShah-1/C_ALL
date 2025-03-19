import SwiftUI
import ARKit
import RealityKit
import CoreLocation

/// Exclusively uses ARGeoTrackingConfiguration (no fallback).
/// Places ARGeoAnchor for each route coordinate once the session localizes.
/// Sets isGeoLocalized=true/false to show "ARGeo has localized!" in ContentView.
struct ARWrapper: UIViewRepresentable {
    /// The route from e.g. OSM route (lat/lon waypoints).
    @Binding var routeCoordinates: [CLLocationCoordinate2D]
    /// The user’s current location (if altitude needed).
    @Binding var userLocation: CLLocation?
    /// Whether ARKit’s geotracking is localized (for UI display).
    @Binding var isGeoLocalized: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        
        // Debug info (feature points, origin).
        arView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        
        // Start ARGeoTracking (no fallback).
        startGeoTracking(in: arView, coordinator: context.coordinator)
        
        // Session delegate.
        arView.session.delegate = context.coordinator
        
        // iOS 15+ => optional geoTracking coaching overlay.
        if #available(iOS 15.0, *) {
            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.delegate = context.coordinator
            coachingOverlay.goal = .geoTracking
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            arView.addSubview(coachingOverlay)
            NSLayoutConstraint.activate([
                coachingOverlay.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
                coachingOverlay.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
                coachingOverlay.widthAnchor.constraint(equalTo: arView.widthAnchor),
                coachingOverlay.heightAnchor.constraint(equalTo: arView.heightAnchor)
            ])
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Called whenever routeCoordinates changes.
        context.coordinator.updateRoute(routeCoordinates)
    }
    
    // MARK: - Private
    
    private func startGeoTracking(in arView: ARView, coordinator: Coordinator) {
        guard #available(iOS 14.0, *) else {
            print("[ARWrapper] iOS 14+ required for ARGeoTracking.")
            return
        }
        
        let config = ARGeoTrackingConfiguration()
        config.environmentTexturing = .automatic
        
        print("[ARWrapper] Checking ARGeoTracking availability.")
        ARGeoTrackingConfiguration.checkAvailability { available, error in
            if let e = error {
                print("[ARWrapper] ARGeoTracking check error => \(e.localizedDescription)")
            }
            if available {
                print("[ARWrapper] ARGeoTracking is available. Running session...")
                arView.session.run(config)
                coordinator.isGeoTrackingActive = true
            } else {
                print("[ARWrapper] ARGeoTracking not available => handle differently.")
            }
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, ARSessionDelegate {
        let parent: ARWrapper
        weak var arView: ARView?
        
        /// True once ARGeoTracking config has started.
        var isGeoTrackingActive = false
        
        /// Track placed anchors by lat/lon string.
        private var placedCoords: Set<String> = []
        
        init(_ parent: ARWrapper) {
            self.parent = parent
        }
        
        /// Places ARGeoAnchors for new route points if AR geoTracking is active.
        func updateRoute(_ newCoordinates: [CLLocationCoordinate2D]) {
            guard isGeoTrackingActive, let session = arView?.session else {
                print("[ARWrapper.Coordinator] ARGeoTracking not active yet. Cannot place anchors.")
                return
            }
            
            let ansiBoldCyan = "\u{001B}[1;36m"
            let ansiReset = "\u{001B}[0m"
            print("[ARWrapper.Coordinator] \(ansiBoldCyan)Full routeCoordinates:\n\(newCoordinates)\(ansiReset)")
            
            // For each coordinate, if not placed, add an ARGeoAnchor.
            for coord in newCoordinates {
                let idString = "\(coord.latitude),\(coord.longitude)"
                if !placedCoords.contains(idString) {
                    // Use user altitude if available, else default to 11.0
                    let alt = parent.userLocation?.altitude ?? 11.0
                    print("[ARWrapper.Coordinator] Placing ARGeoAnchor lat=\(coord.latitude), lon=\(coord.longitude), alt=\(alt)")
                    let anchor = ARGeoAnchor(coordinate: coord, altitude: alt)
                    session.add(anchor: anchor)
                    placedCoords.insert(idString)
                }
            }
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {}
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("[ARWrapper.Coordinator] AR session failed => \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("[ARWrapper.Coordinator] AR session was interrupted.")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("[ARWrapper.Coordinator] AR session interruption ended. Restarting tracking.")
        }
        
        @available(iOS 14.0, *)
        func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
            switch geoTrackingStatus.state {
            case .localized:
                parent.isGeoLocalized = true
            default:
                parent.isGeoLocalized = false
            }
            print("[ARWrapper.Coordinator] geoTrackingStatus => state=\(geoTrackingStatus.state.rawValue), accuracy=\(geoTrackingStatus.accuracy.rawValue)")
        }
        
        // Attach a simple red sphere to each ARGeoAnchor
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let arView = arView, anchor is ARGeoAnchor else { continue }
                
                // Wrap this ARAnchor in a RealityKit AnchorEntity
                let anchorEntity = AnchorEntity(anchor: anchor)
                
                // Create a small sphere
                let sphereMesh = MeshResource.generateSphere(radius: 0.2)
                let material = SimpleMaterial(color: .red, roughness: 0.2, isMetallic: false)
                let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])
                
                // Attach sphere and add to ARView's scene
                anchorEntity.addChild(sphereEntity)
                arView.scene.addAnchor(anchorEntity)
            }
        }
    }
}

// MARK: - iOS 15 Coaching Overlay

@available(iOS 15.0, *)
extension ARWrapper.Coordinator: ARCoachingOverlayViewDelegate {
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        print("[ARWrapper.Coordinator] Coaching overlay will activate.")
    }
    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        print("[ARWrapper.Coordinator] Coaching overlay did deactivate.")
    }
    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        print("[ARWrapper.Coordinator] Coaching overlay requested session reset.")
        guard let view = arView else { return }
        view.session.pause()
        if let config = view.session.configuration {
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
    }
}
