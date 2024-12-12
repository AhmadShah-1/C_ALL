//
//  ARWrapper.swift
//  C_ALL_With_Avoidance
//
//  Created by SSW - Design Team  on 12/11/24.
//

import SwiftUI
import RealityKit
import ARKit
import AVFoundation
import CoreLocation
import UIKit

struct ARWrapper: UIViewRepresentable {
    @Binding var submittedExportRequest: Bool
    @Binding var submittedName: String

    let arView = ARView(frame: .zero)

    func makeUIView(context: Context) -> ARView {
        checkCameraAccess { granted in
            if granted {
                DispatchQueue.main.async {
                    setupARView(context: context)
                }
            } else {
                print("Camera access not granted.")
            }
        }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        return Coordinator(arView: arView)
    }

    private func setupARView(context: Context) {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("ARWorldTrackingConfiguration is not supported on this device.")
            return
        }

        setARViewOptions(arView)
        let configuration = buildConfiguration()

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        arView.session.delegate = context.coordinator
    }

    private func buildConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.sceneReconstruction = .meshWithClassification
        configuration.planeDetection = [.horizontal]
        configuration.frameSemantics = .sceneDepth

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        } else {
            print("Scene reconstruction not supported on this device.")
        }

        return configuration
    }

    private func setARViewOptions(_ arView: ARView) {
        arView.debugOptions = [.showFeaturePoints, .showWorldOrigin, .showAnchorOrigins]
        arView.automaticallyConfigureSession = false
    }

    private func checkCameraAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            fatalError("Unknown authorization status for camera.")
        }
    }

    class Coordinator: NSObject, ARSessionDelegate, ARSessionObserver, CLLocationManagerDelegate {
        var arView: ARView
        var locationManager: CLLocationManager
        var currentHeading: Double?
        var lastPathAnchors: [AnchorEntity] = []
        var lastUpdateTime: TimeInterval = 0
        var estimatedFloorY: Float?
        let floorHeightTolerance: Float = 0.05
        var initialUserPosition: SIMD3<Float>?
        let movementThreshold: Float = 0.5 // Update path if user moves more than 0.5 meters

        init(arView: ARView) {
            self.arView = arView
            self.locationManager = CLLocationManager()
            super.init()
            self.locationManager.delegate = self
            self.locationManager.requestWhenInUseAuthorization()
            if CLLocationManager.headingAvailable() {
                self.locationManager.startUpdatingHeading()
            } else {
                print("Heading not available")
            }
        }

        // CLLocationManagerDelegate methods
        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            if newHeading.headingAccuracy < 0 {
                print("Invalid heading")
                return
            }
            self.currentHeading = newHeading.trueHeading
            // No need to print every heading update
        }

        func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if CLLocationManager.headingAvailable() {
                    locationManager.startUpdatingHeading()
                } else {
                    print("Heading not available")
                }
            case .denied, .restricted:
                print("Location access denied or restricted")
            default:
                break
            }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            print("Location manager failed with error: \(error.localizedDescription)")
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Limit update frequency
            let currentTime = frame.timestamp
            if currentTime - lastUpdateTime < 0.5 {
                return
            }

            guard let cameraTransform = arView.session.currentFrame?.camera.transform else {
                print("Camera transform is unavailable")
                return
            }

            guard estimatedFloorY != nil else {
                print("Floor not yet detected. Waiting to update path.")
                return
            }

            guard currentHeading != nil else {
                print("Waiting for heading data")
                return
            }

            // Get current user position
            let currentUserPosition = SIMD3<Float>(
                x: cameraTransform.translation.x,
                y: estimatedFloorY!,
                z: cameraTransform.translation.z
            )

            // Initialize initialUserPosition if not set
            if initialUserPosition == nil {
                initialUserPosition = currentUserPosition
                // Place the test cube at the initial position
                addTestCube(at: initialUserPosition!)
                // Generate the initial path
                updatePath(from: initialUserPosition!)
            } else {
                // Check if user has moved beyond the threshold
                let distanceMoved = simd_distance(currentUserPosition, initialUserPosition!)
                if distanceMoved > movementThreshold {
                    // Update the path from the new position
                    initialUserPosition = currentUserPosition
                    // Place the test cube at the new position
                    addTestCube(at: initialUserPosition!)
                    updatePath(from: initialUserPosition!)
                } else {
                    // Do not update the path if user hasn't moved significantly
                    print("User hasn't moved significantly; not updating path.")
                }
            }

            lastUpdateTime = currentTime
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
                    updateEstimatedFloorY(with: planeAnchor)
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
                    updateEstimatedFloorY(with: planeAnchor)
                }
            }
        }

        private func updateEstimatedFloorY(with planeAnchor: ARPlaneAnchor) {
            if #available(iOS 13.0, *) {
                if planeAnchor.classification == .floor {
                    estimatedFloorY = planeAnchor.transform.translation.y
                    return
                }
            }

            let planeY = planeAnchor.transform.translation.y
            if let currentFloorY = estimatedFloorY {
                if planeY < currentFloorY {
                    estimatedFloorY = planeY
                }
            } else {
                estimatedFloorY = planeY
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            // Handle tracking state changes if necessary
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("ARSession did fail with error: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("ARSession was interrupted.")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("ARSession interruption ended.")
        }

        private func updatePath(from startingPosition: SIMD3<Float>) {
            // Remove previous path anchors
            for anchor in lastPathAnchors {
                arView.scene.removeAnchor(anchor)
            }
            lastPathAnchors.removeAll()

            guard let estimatedFloorY = estimatedFloorY else {
                print("Floor not yet detected. Waiting to update path.")
                return
            }

            guard let heading = currentHeading else {
                print("Waiting for heading data")
                return
            }

            // Convert heading to radians and calculate the North direction vector
            let headingRadians = Float(heading * (.pi / 180.0))
            let northDirection = SIMD3<Float>(
                x: sin(headingRadians),
                y: 0,
                z: -cos(headingRadians)
            )

            // Generate the path starting from the startingPosition towards North
            let pathAnchors = createPath(from: startingPosition, direction: northDirection)
            lastPathAnchors.append(contentsOf: pathAnchors)

            // Add each path anchor to the AR scene
            for anchor in pathAnchors {
                arView.scene.addAnchor(anchor)
            }
        }

        private func addTestCube(at position: SIMD3<Float>) {
            // Remove existing test cube if any
            if let existingCube = arView.scene.findEntity(named: "TestCube") {
                existingCube.removeFromParent()
            }

            let material = SimpleMaterial(color: UIColor.blue, isMetallic: false)
            let testCube = ModelEntity(mesh: .generateBox(size: 0.1), materials: [material])
            testCube.name = "TestCube"
            let testAnchor = AnchorEntity(world: position)
            testAnchor.addChild(testCube)
            arView.scene.addAnchor(testAnchor)
        }

        private func createPath(from startingPosition: SIMD3<Float>, direction: SIMD3<Float>) -> [AnchorEntity] {
            var anchors: [AnchorEntity] = []
            let pathSegmentLength: Float = 0.5
            let numberOfSegments = 20

            var currentPosition = startingPosition
            var currentDirection = normalize(direction)

            for _ in 0..<numberOfSegments {
                let nextPosition = currentPosition + currentDirection * pathSegmentLength
                var adjustedNextPosition = nextPosition
                adjustedNextPosition.y = estimatedFloorY!

                // Obstacle detection
                let obstacleDetected = isObstacleInDirection(
                    from: currentPosition,
                    direction: currentDirection,
                    distance: pathSegmentLength
                )

                if obstacleDetected {
                    // Adjust the direction to avoid obstacle
                    let adjusted = adjustDirection(
                        &currentDirection,
                        initialDirection: direction,
                        from: currentPosition,
                        pathSegmentLength: pathSegmentLength
                    )
                    if !adjusted {
                        print("Cannot find path around obstacle")
                        break
                    } else {
                        print("Adjusted direction to avoid obstacle")
                        continue
                    }
                } else {
                    // Create a path segment at the adjustedNextPosition
                    let pathAnchor = AnchorEntity(world: adjustedNextPosition)

                    let material = SimpleMaterial(color: UIColor.red, isMetallic: false)
                    let pathEntity = ModelEntity(
                        mesh: .generateBox(size: [0.3, 0.01, 0.3]),
                        materials: [material]
                    )

                    pathEntity.scale = SIMD3<Float>(repeating: 1.0)
                    pathAnchor.addChild(pathEntity)
                    anchors.append(pathAnchor)

                    currentPosition = adjustedNextPosition
                    // Keep currentDirection as adjusted
                }
            }
            return anchors
        }

        private func adjustDirection(
            _ direction: inout SIMD3<Float>,
            initialDirection: SIMD3<Float>,
            from position: SIMD3<Float>,
            pathSegmentLength: Float
        ) -> Bool {
            // Try rotating the direction in increments to the left and right
            for angle in stride(from: 15, through: 90, by: 15) {
                let radians = Float(angle) * .pi / 180
                // Rotate to the right
                var rotationMatrix = simd_float3x3(simd_quatf(angle: -radians, axis: SIMD3<Float>(0, 1, 0)))
                var newDirection = normalize(rotationMatrix * initialDirection)
                if !isObstacleInDirection(from: position, direction: newDirection, distance: pathSegmentLength) {
                    direction = newDirection
                    return true
                }
                // Rotate to the left
                rotationMatrix = simd_float3x3(simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0)))
                newDirection = normalize(rotationMatrix * initialDirection)
                if !isObstacleInDirection(from: position, direction: newDirection, distance: pathSegmentLength) {
                    direction = newDirection
                    return true
                }
            }
            return false
        }

        private func isObstacleInDirection(
            from position: SIMD3<Float>,
            direction: SIMD3<Float>,
            distance: Float
        ) -> Bool {
            let obstacleQuery = ARRaycastQuery(
                origin: position + SIMD3<Float>(0, 0.1, 0), // Slightly above floor level
                direction: direction,
                allowing: .estimatedPlane,
                alignment: .any
            )
            let obstacleResults = arView.session.raycast(obstacleQuery)
            if let obstacleResult = obstacleResults.first {
                let obstacleDistance = simd_distance(position, obstacleResult.worldTransform.translation)
                if obstacleDistance < distance {
                    return true
                }
            }
            return false
        }
    }
}

// Extensions to extract translation from transform matrices
extension simd_float4x4 {
    var translation: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension simd_float4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
