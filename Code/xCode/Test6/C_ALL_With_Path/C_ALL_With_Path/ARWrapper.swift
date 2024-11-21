import SwiftUI
import RealityKit
import ARKit

// ARWrapper is a UIViewRepresentable that integrates UIKit's UIView into SwiftUI.
// It wraps an ARView and provides AR functionalities within a SwiftUI view.
struct ARWrapper: UIViewRepresentable {
    // Bindings to track export requests and submitted names (if needed elsewhere in your app).
    @Binding var submittedExportRequest: Bool
    @Binding var submittedName: String

    // The ARView that will display the AR content.
    let arView = ARView(frame: .zero)

    // This function creates and configures the ARView when the SwiftUI view is initialized.
    func makeUIView(context: Context) -> ARView {
        // Configure ARView options such as debug options.
        setARViewOptions(arView)
        // Build and configure the AR session.
        let configuration = buildConfiguration()
        // Run the AR session with the specified configuration.
        arView.session.run(configuration)
        // Set the session delegate to the Coordinator for AR session callbacks.
        arView.session.delegate = context.coordinator
        return arView
    }

    // This function updates the ARView when the SwiftUI view updates.
    func updateUIView(_ uiView: ARView, context: Context) { }

    // Creates a Coordinator object to act as the delegate for AR session updates.
    func makeCoordinator() -> Coordinator {
        return Coordinator(arView: arView)
    }

    // Builds and returns an ARWorldTrackingConfiguration with desired settings.
    private func buildConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Enable environment texturing for realistic reflections.
        configuration.environmentTexturing = .automatic
        // Enable scene reconstruction to build a mesh of the environment.
        configuration.sceneReconstruction = .meshWithClassification
        // Detect horizontal planes (e.g., floors, tables).
        configuration.planeDetection = [.horizontal]
        // Enable frame semantics to receive scene depth information.
        configuration.frameSemantics = .sceneDepth
        return configuration
    }

    // Sets various options for the ARView.
    private func setARViewOptions(_ arView: ARView) {
        // Show scene understanding visualization (e.g., detected planes, meshes).
        arView.debugOptions.insert(.showSceneUnderstanding)
        // Prevent ARView from automatically configuring the session, as we do it manually.
        arView.automaticallyConfigureSession = false
    }

    // Coordinator class acts as the ARSessionDelegate to handle AR session updates.
    class Coordinator: NSObject, ARSessionDelegate {
        // Reference to the ARView.
        var arView: ARView
        // Array to keep track of the last path anchors added to the scene, so we can remove them later.
        var lastPathAnchors: [AnchorEntity] = []
        // Timestamp of the last update, used to limit update frequency.
        var lastUpdateTime: TimeInterval = 0

        // Initialize the Coordinator with a reference to the ARView.
        init(arView: ARView) {
            self.arView = arView
        }

        // Called every time the ARSession updates (i.e., every frame).
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Limit the frequency of path updates to avoid performance issues.
            let currentTime = frame.timestamp
            if currentTime - lastUpdateTime < 0.5 {
                // If less than 0.5 seconds have passed since the last update, skip this frame.
                return
            }
            // Update the timestamp of the last update.
            lastUpdateTime = currentTime
            // Call the function to update the path.
            updatePath()
        }

        // Function to update the path displayed in the AR scene.
        private func updatePath() {
            // Remove the previous path anchors from the scene to prevent clutter.
            for anchor in lastPathAnchors {
                arView.scene.removeAnchor(anchor)
            }
            // Clear the list of last path anchors.
            lastPathAnchors.removeAll()

            // Get the current camera transform to determine the user's position and orientation.
            guard let cameraTransform = arView.session.currentFrame?.camera.transform else {
                // If the camera transform is unavailable, exit the function.
                return
            }

            // Perform a downward raycast from the camera position to find the floor.
            let cameraPosition = cameraTransform.translation
            let raycastQuery = ARRaycastQuery(
                origin: cameraPosition,
                direction: SIMD3<Float>(0, -1, 0), // Downward direction.
                allowing: .estimatedPlane,
                alignment: .horizontal
            )

            // Execute the raycast query to find intersections with horizontal planes (floors).
            guard let result = arView.session.raycast(raycastQuery).first else {
                // If no floor is detected, log and exit the function.
                print("No floor detected")
                return
            }

            // The starting position for the path is the point where the raycast hit the floor.
            let startingPosition = result.worldTransform.translation

            // Generate the path starting from the startingPosition.
            let pathAnchors = createPath(from: startingPosition, cameraTransform: cameraTransform)
            // Keep track of the new path anchors to remove them later.
            lastPathAnchors.append(contentsOf: pathAnchors)

            // Add each path anchor to the AR scene.
            for anchor in pathAnchors {
                arView.scene.addAnchor(anchor)
            }
        }

        // Function to create the path anchors starting from a given position.
        private func createPath(from startingPosition: SIMD3<Float>, cameraTransform: simd_float4x4) -> [AnchorEntity] {
            var anchors: [AnchorEntity] = []
            let pathSegmentLength: Float = 0.5 // Length of each path segment in meters.
            let numberOfSegments = 20          // Total number of path segments to create.

            var currentPosition = startingPosition

            // Calculate the forward direction based on the camera's orientation.
            var forwardVector = -normalize(cameraTransform.columns.2.xyz)
            forwardVector.y = 0 // Ignore vertical component to keep movement on the horizontal plane.
            forwardVector = normalize(forwardVector)

            // The direction the path will proceed in; initially set to the forward vector.
            var direction = forwardVector

            // Loop to create each segment of the path.
            for _ in 0..<numberOfSegments {
                // Calculate the next position by moving along the direction vector.
                let nextPosition = currentPosition + direction * pathSegmentLength

                // Raycast downward from the nextPosition to find the floor at that point.
                let raycastQuery = ARRaycastQuery(
                    origin: nextPosition + SIMD3<Float>(0, 0.5, 0), // Slightly above to avoid intersecting with the floor.
                    direction: SIMD3<Float>(0, -1, 0), // Downward direction.
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )

                // Execute the raycast to find the floor.
                guard let result = arView.session.raycast(raycastQuery).first else {
                    // If no floor is detected at the next position, stop generating the path.
                    print("No floor detected at next position")
                    break
                }

                // The exact position on the floor where the path segment will be placed.
                let pathPosition = result.worldTransform.translation

                // Check for obstacles in the current direction.
                let obstacleDetected = isObstacleInDirection(
                    from: currentPosition,
                    direction: direction,
                    distance: pathSegmentLength
                )

                if obstacleDetected {
                    // If an obstacle is detected, attempt to adjust the path direction.
                    let adjusted = adjustDirection(
                        &direction,
                        forwardVector: forwardVector,
                        from: currentPosition,
                        pathSegmentLength: pathSegmentLength
                    )
                    if !adjusted {
                        // If unable to adjust the path to avoid the obstacle, stop generating the path.
                        print("Cannot find path around obstacle")
                        break
                    } else {
                        // If the direction was adjusted, retry generating the next segment with the new direction.
                        continue
                    }
                } else {
                    // If no obstacle is detected, create a path segment at the pathPosition.
                    let pathAnchor = AnchorEntity(world: pathPosition)
                    // Use an unlit material with a green color for the path segment.
                    let material = UnlitMaterial(color: .green)
                    // Create a plane to represent the path segment.
                    let pathEntity = ModelEntity(
                        mesh: .generatePlane(width: 0.3, depth: pathSegmentLength),
                        materials: [material]
                    )
                    // Rotate the plane to lie flat on the floor.
                    pathEntity.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                    // Adjust the position so that the plane extends forward from the anchor.
                    pathEntity.position.z -= pathSegmentLength / 2
                    // Add the path entity to the anchor.
                    pathAnchor.addChild(pathEntity)
                    // Add the anchor to the list of anchors to be added to the scene.
                    anchors.append(pathAnchor)

                    // Update the current position for the next segment.
                    currentPosition = nextPosition
                    // Reset the direction to the forward vector after a successful placement.
                    direction = forwardVector
                }
            }
            return anchors
        }

        // Function to adjust the direction of the path to avoid obstacles.
        private func adjustDirection(
            _ direction: inout SIMD3<Float>,
            forwardVector: SIMD3<Float>,
            from position: SIMD3<Float>,
            pathSegmentLength: Float
        ) -> Bool {
            // Try rotating the direction in increments to the left and right.
            for angle in stride(from: 15, through: 90, by: 15) {
                let radians = Float(angle) * .pi / 180
                // Rotate to the right.
                var rotationMatrix = simd_float3x3(simd_quatf(angle: -radians, axis: SIMD3<Float>(0, 1, 0)))
                var newDirection = normalize(rotationMatrix * forwardVector)
                if !isObstacleInDirection(from: position, direction: newDirection, distance: pathSegmentLength) {
                    // If no obstacle is detected in the new direction, update the direction and return true.
                    direction = newDirection
                    return true
                }
                // Rotate to the left.
                rotationMatrix = simd_float3x3(simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0)))
                newDirection = normalize(rotationMatrix * forwardVector)
                if !isObstacleInDirection(from: position, direction: newDirection, distance: pathSegmentLength) {
                    // If no obstacle is detected in the new direction, update the direction and return true.
                    direction = newDirection
                    return true
                }
            }
            // If no suitable direction is found, return false.
            return false
        }

        // Function to check if there is an obstacle in a given direction within a certain distance.
        private func isObstacleInDirection(
            from position: SIMD3<Float>,
            direction: SIMD3<Float>,
            distance: Float
        ) -> Bool {
            // Create a raycast query in the given direction.
            let obstacleQuery = ARRaycastQuery(
                origin: position + SIMD3<Float>(0, 0.5, 0), // Slightly above to avoid ground interference.
                direction: direction,
                allowing: .existingPlaneGeometry,
                alignment: .any
            )
            // Execute the raycast to detect obstacles.
            let obstacleResults = arView.session.raycast(obstacleQuery)
            if let obstacleResult = obstacleResults.first {
                // Calculate the distance to the detected obstacle.
                let obstacleDistance = simd_distance(position, obstacleResult.worldTransform.translation)
                // If the obstacle is within the specified distance, return true.
                return obstacleDistance < distance
            }
            // If no obstacle is detected, return false.
            return false
        }
    }
}

// Extension to extract the translation (position) from a 4x4 transformation matrix.
extension simd_float4x4 {
    var translation: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

// Extension to extract the x, y, z components from a simd_float4 (ignoring w component).
extension simd_float4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
