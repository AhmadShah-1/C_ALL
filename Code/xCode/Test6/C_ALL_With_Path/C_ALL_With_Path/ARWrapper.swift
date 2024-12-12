import SwiftUI
import RealityKit
import ARKit
import CoreLocation

struct ARWrapper: UIViewRepresentable {
    @Binding var routeCoordinates: [CLLocationCoordinate2D]

    let arView = ARView(frame: .zero)

    func makeUIView(context: Context) -> ARView {
        print("Setting up ARView...")

        // Check if ARWorldTrackingConfiguration is supported
        guard ARWorldTrackingConfiguration.isSupported else {
            print("ARWorldTrackingConfiguration not supported on this device.")
            return arView
        }

        // Set up the AR session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        
        // Optionally enable people occlusion if supported
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }

        // Run the session with the configuration
        arView.session.run(configuration)
        print("ARSession started.")

        // Set the session delegate
        arView.session.delegate = context.coordinator

        // Place a simple test box at the start to confirm rendering
        let boxAnchor = AnchorEntity(world: [0, 0, -0.5])
        let box = ModelEntity(mesh: .generateBox(size: 0.1),
                              materials: [SimpleMaterial(color: .red, isMetallic: false)])
        boxAnchor.addChild(box)
        arView.scene.addAnchor(boxAnchor)
        print("Added a test box to the scene as a reference.")

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        print("ARWrapper.updateUIView called. Route count: \(routeCoordinates.count)")
        // Update route spheres whenever routeCoordinates change
        context.coordinator.updateRoute(routeCoordinates: routeCoordinates)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(arView: arView)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView
        var lastPathAnchors: [AnchorEntity] = []

        init(arView: ARView) {
            self.arView = arView
            super.init()
        }

        // ARSessionDelegate methods

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("ARSession failed with error: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("ARSession was interrupted. The session will pause until the interruption ends.")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("ARSession interruption ended. Resetting tracking if needed.")
            // Optionally: session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Handle frame updates if needed
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .notAvailable:
                print("Camera tracking not available.")
            case .limited(let reason):
                print("Camera tracking limited: \(reason).")
            case .normal:
                // Good tracking
                break
            }
        }

        // Custom method to update route in AR
        func updateRoute(routeCoordinates: [CLLocationCoordinate2D]) {
            guard !routeCoordinates.isEmpty else {
                print("No route coordinates to update")
                return
            }

            // Remove old anchors
            for anchor in lastPathAnchors {
                arView.scene.removeAnchor(anchor)
            }
            lastPathAnchors.removeAll()

            print("Coordinator.updateRoute called with \(routeCoordinates.count) coords.")
            print("Placing route spheres now...")

            guard let frame = arView.session.currentFrame else {
                print("No current ARFrame available. Cannot place route spheres.")
                return
            }
            let cameraPosition = frame.camera.transform.translation

            // For demonstration, place spheres in a line in front of the camera.
            // In a real scenario, you'd convert these coordinates into AR world positions
            // based on user location and heading.
            for (index, _) in routeCoordinates.enumerated() {
                let offset = Float(index) * 0.5 // spheres half a meter apart
                let position = SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z - offset)
                let anchor = AnchorEntity(world: position)

                let material = SimpleMaterial(color: .green, isMetallic: false)
                let sphere = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [material])
                anchor.addChild(sphere)
                arView.scene.addAnchor(anchor)
                lastPathAnchors.append(anchor)
            }

            print("Route spheres placed.")
        }
    }
}

// Helper to extract translation from a simd_float4x4 matrix
extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
