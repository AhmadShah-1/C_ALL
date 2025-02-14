import SwiftUI
import ARKit
import RealityKit
import CoreLocation

// Helper function to compare two arrays of CLLocationCoordinate2D.
func areCoordinatesEqual(_ lhs: [CLLocationCoordinate2D], _ rhs: [CLLocationCoordinate2D]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (c1, c2) in zip(lhs, rhs) {
        if c1.latitude != c2.latitude || c1.longitude != c2.longitude {
            return false
        }
    }
    return true
}

struct ARWrapper: UIViewRepresentable {
    @Binding var routeCoordinates: [CLLocationCoordinate2D]
    @Binding var userLocation: CLLocation?
    @Binding var isGeoLocalized: Bool
    @Binding var obstacleOffset: Double  // obstacle offset (in degrees)
    @Binding var depthImage: UIImage?      // depth image for visualization (unchanged, for now)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        // Debug options (you may remove these later)
        arView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        startGeoTracking(in: arView, coordinator: context.coordinator)
        arView.session.delegate = context.coordinator

        if #available(iOS 15.0, *) {
            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.delegate = context.coordinator
            coachingOverlay.goal = .geoTracking
            arView.addSubview(coachingOverlay)
        }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateRouteIfNeeded(newCoordinates: routeCoordinates)
    }

    private func startGeoTracking(in arView: ARView, coordinator: Coordinator) {
        guard ARGeoTrackingConfiguration.isSupported else {
            print("ARGeoTracking not supported")
            return
        }
        let config = ARGeoTrackingConfiguration()
        config.environmentTexturing = .automatic
        arView.session.run(config)
        coordinator.isGeoTrackingActive = true
    }

    class Coordinator: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
        let parent: ARWrapper
        weak var arView: ARView?
        var isGeoTrackingActive = false

        // Cache for the current route so we update only on change.
        private var cachedRouteCoordinates: [CLLocationCoordinate2D] = []
        // Main path anchors built from the route coordinates.
        var mainPathAnchors: [ARGeoAnchor] = []

        init(_ parent: ARWrapper) {
            self.parent = parent
        }

        func updateRouteIfNeeded(newCoordinates: [CLLocationCoordinate2D]) {
            guard !areCoordinatesEqual(newCoordinates, cachedRouteCoordinates) else { return }
            cachedRouteCoordinates = newCoordinates
            updateRoute(newCoordinates)
        }

        func updateRoute(_ newCoordinates: [CLLocationCoordinate2D]) {
            guard let session = arView?.session else { return }
            for anchor in mainPathAnchors {
                session.remove(anchor: anchor)
            }
            mainPathAnchors.removeAll()
            for coord in newCoordinates {
                let altitude = parent.userLocation?.altitude ?? 11.0
                let geoAnchor = ARGeoAnchor(coordinate: coord, altitude: altitude)
                session.add(anchor: geoAnchor)
                mainPathAnchors.append(geoAnchor)
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView = arView else { return }
            for anchor in anchors {
                if let geoAnchor = anchor as? ARGeoAnchor {
                    let anchorEntity = AnchorEntity(anchor: geoAnchor)
                    let sphereMesh = MeshResource.generateSphere(radius: 0.2)
                    let material = SimpleMaterial(color: .red, roughness: 0.2, isMetallic: false)
                    let model = ModelEntity(mesh: sphereMesh, materials: [material])
                    anchorEntity.addChild(model)
                    arView.scene.addAnchor(anchorEntity)
                }
            }
        }

        /// Called every frame.
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            updateObstacleOffsetFromFeaturePoints(frame: frame)
            // (Optional) You may still update depthImage if desired.
            // updateDepthImage(frame: frame)
        }

        /// New function that uses ARKit's raw feature points to compute an obstacle offset.
        func updateObstacleOffsetFromFeaturePoints(frame: ARFrame) {
            guard let pointCloud = frame.rawFeaturePoints else {
                print("No feature points available")
                self.parent.obstacleOffset = 0
                return
            }
            let points = pointCloud.points  // in world coordinates
            let cameraTransform = frame.camera.transform
            let cameraPos = cameraTransform.columns.3.xyz
            // Get camera coordinate axes.
            let right = cameraTransform.columns.0.xyz
            let up = cameraTransform.columns.1.xyz
            // Define forward such that it points out in front of the camera.
            // In ARKit, the camera's forward vector is -Z, so we reverse it:
            let forward = -cameraTransform.columns.2.xyz

            var leftCount = 0
            var rightCount = 0
            // Process each feature point.
            for point in points {
                let relative = point - cameraPos
                // Project relative vector onto forward direction.
                let zComp = simd_dot(relative, forward)
                // Only consider points that are at least 0.2 meters away.
                if zComp < 0.2 { continue }
                // Project onto the right vector.
                let xComp = simd_dot(relative, right)
                if xComp < 0 {
                    leftCount += 1
                } else {
                    rightCount += 1
                }
            }
            // Debug prints:
            print("Left: \(leftCount), Right: \(rightCount)")
            let diff = leftCount - rightCount
            let thresholdCount = 20
            var offset: Double = 0
            if diff > thresholdCount {
                // Too many points on left -> obstacle on left -> steer right.
                offset = 30
            } else if diff < -thresholdCount {
                // Too many points on right -> obstacle on right -> steer left.
                offset = -30
            } else {
                offset = 0
            }
            self.parent.obstacleOffset = offset
        }

        // (Optional) Old depth-based method; left here for reference.
        func updateDepthImage(frame: ARFrame) {
            // Implementation omitted for brevity.
        }

        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            // Optionally handle overlay deactivation.
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
