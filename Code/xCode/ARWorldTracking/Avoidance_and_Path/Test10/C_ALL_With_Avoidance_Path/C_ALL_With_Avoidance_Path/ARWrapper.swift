import SwiftUI
import ARKit
import RealityKit
import CoreLocation

//asd
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
    @Binding var depthImage: UIImage?    // depth image for visualization
    @Binding var isUsingLidar: Bool      // Add this binding to report active method
    @Binding var showObstacleMeshes: Bool  // Add this binding

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
        
        // Setup obstacle meshes
        context.coordinator.setupObstacleMeshes()

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
        
        // Update mesh visibility based on toggle
        if let leftMesh = context.coordinator.leftObstacleMeshEntity,
           let rightMesh = context.coordinator.rightObstacleMeshEntity,
           let centerMesh = context.coordinator.centerObstacleMeshEntity {
            
            // Only show meshes if toggle is on and obstacles are detected
            leftMesh.isEnabled = showObstacleMeshes && context.coordinator.leftObstaclePresent
            rightMesh.isEnabled = showObstacleMeshes && context.coordinator.rightObstaclePresent
            centerMesh.isEnabled = showObstacleMeshes && context.coordinator.centerObstaclePresent
        }
    }

    private func startGeoTracking(in arView: ARView, coordinator: Coordinator) {
        guard ARGeoTrackingConfiguration.isSupported else {
            print("DEBUG: ARGeoTracking not supported on this device")
            return
        }
        
        let config = ARGeoTrackingConfiguration()
        config.environmentTexturing = .automatic
        
        // IMPORTANT: Enable depth data collection if available
        if #available(iOS 14.0, *) {
            // Try to enable scene depth
            print("DEBUG: Attempting to enable frameSemantics for sceneDepth")
            if ARGeoTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
                print("DEBUG: Device supports depth with GeoTracking - enabled sceneDepth")
            } else {
                print("DEBUG: Device does NOT support depth with GeoTracking")
            }
        }
        
        arView.session.run(config)
        coordinator.isGeoTrackingActive = true
        print("DEBUG: Started ARGeoTracking session")
    }

    class Coordinator: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
        let parent: ARWrapper
        weak var arView: ARView?
        var isGeoTrackingActive = false
        
        // Cache for the current route
        private var cachedRouteCoordinates: [CLLocationCoordinate2D] = []
        // Main path anchors built from the route coordinates
        var mainPathAnchors: [ARGeoAnchor] = []
        
        // Add these properties for obstacle visualization
        var leftObstacleMeshEntity: ModelEntity?
        var rightObstacleMeshEntity: ModelEntity?
        var centerObstacleMeshEntity: ModelEntity?
        var obstacleAnchor: AnchorEntity?
        
        // Obstacle detection parameters
        var leftObstaclePresent: Bool = false
        var rightObstaclePresent: Bool = false
        var centerObstaclePresent: Bool = false

        init(_ parent: ARWrapper) {
            self.parent = parent
            
            // Check device capability for LiDAR at initialization
            if #available(iOS 14.0, *) {
                let deviceHasLiDAR = ARConfiguration.supportsFrameSemantics(.sceneDepth)
                print("DEBUG: Coordinator init - Device has LiDAR: \(deviceHasLiDAR)")
            } else {
                print("DEBUG: Coordinator init - iOS < 14.0, no LiDAR support expected")
            }
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
            // Update mesh positions based on camera position
            positionObstacleMeshes()
            
            // Existing code for depth or feature point processing
            if frame.sceneDepth != nil {
                print("DEBUG: LiDAR DEPTH DATA AVAILABLE - using LiDAR for obstacle detection")
                processDepthDataForObstacles(frame: frame)
                DispatchQueue.main.async {
                    self.parent.isUsingLidar = true
                }
            } else {
                print("DEBUG: NO DEPTH DATA - using feature points for obstacle detection")
                updateObstacleOffsetFromFeaturePoints(frame: frame)
                DispatchQueue.main.async {
                    self.parent.isUsingLidar = false
                }
            }
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
            
            // Update obstacle presence flags
            leftObstaclePresent = diff > thresholdCount
            rightObstaclePresent = diff < -thresholdCount
            centerObstaclePresent = false // Could add center detection logic
            
            // Update mesh visibility
            updateMeshVisibility()
        }

        // (Optional) Old depth-based method; left here for reference.
        func updateDepthImage(frame: ARFrame) {
            // Implementation omitted for brevity.
        }

        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            // Optionally handle overlay deactivation.
        }

        func processDepthDataForObstacles(frame: ARFrame) {
            // Check if depth data is available (LiDAR)
            guard let depthMap = frame.sceneDepth?.depthMap else {
                print("DEBUG: processDepthDataForObstacles called but no depth map available")
                return
            }
            
            print("DEBUG: Processing depth map with dimensions: \(CVPixelBufferGetWidth(depthMap)) x \(CVPixelBufferGetHeight(depthMap))")
            
            // Process the depth map to detect obstacles
            // This is a simplified version - you would need to adapt this
            
            // Get the depth image dimensions
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            // Calculate the center region of interest
            let centerX = width / 2
            let centerY = height / 2
            let regionSize = min(width, height) / 4
            
            // Lock the buffer for reading
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                return
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // Check left and right regions for obstacles
            var leftObstacles = 0
            var rightObstacles = 0
            
            // Check points in the left and right regions
            for y in (centerY - regionSize)...(centerY + regionSize) {
                for x in 0..<width {
                    // Skip points outside our horizontal regions of interest
                    if x > centerX - regionSize && x < centerX + regionSize {
                        continue // Skip the center region
                    }
                    
                    let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                    let depth = depthPointer[offset]
                    
                    // Check if this point is within our obstacle detection range
                    if depth > 0.5 && depth < 2.0 { // Between 0.5 and 2 meters
                        if x < centerX {
                            leftObstacles += 1
                        } else {
                            rightObstacles += 1
                        }
                    }
                }
            }
            
            // Determine which side has more obstacles
            let threshold = 100 // You'll need to tune this based on testing
            
            var offset: Double = 0
            // Convert to Double for comparison
            let leftObstaclesDouble = Double(leftObstacles)
            let rightObstaclesDouble = Double(rightObstacles)

            if leftObstacles > threshold && leftObstaclesDouble > rightObstaclesDouble * 1.5 {
                // More obstacles on left side, suggest steering right
                offset = 30
            } else if rightObstacles > threshold && rightObstaclesDouble > leftObstaclesDouble * 1.5 {
                // More obstacles on right side, suggest steering left
                offset = -30
            }
            
            self.parent.obstacleOffset = offset
            
            // Create a visualization of the depth map for debugging
            self.parent.depthImage = createDepthVisualization(depthMap: depthMap)
            
            // After processing depth data, update obstacle detection flags
            leftObstaclePresent = leftObstacles > threshold
            rightObstaclePresent = rightObstacles > threshold
            centerObstaclePresent = false // You can add center obstacle detection logic
            
            // Update mesh visibility based on obstacle detection
            updateMeshVisibility()
        }

        func createDepthVisualization(depthMap: CVPixelBuffer) -> UIImage? {
            // Convert depth data to a visualization
            let ciImage = CIImage(cvPixelBuffer: depthMap)
            let context = CIContext()
            
            // Apply a filter to make the depth visible
            let colorFilter = CIFilter(name: "CIFalseColor")
            colorFilter?.setValue(ciImage, forKey: kCIInputImageKey)
            colorFilter?.setValue(CIColor(red: 0, green: 0, blue: 1), forKey: "inputColor0")
            colorFilter?.setValue(CIColor(red: 1, green: 0, blue: 0), forKey: "inputColor1")
            
            guard let outputImage = colorFilter?.outputImage,
                  let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }
            
            return UIImage(cgImage: cgImage)
        }

        // Method to create and position obstacle meshes
        func setupObstacleMeshes() {
            guard let arView = arView else { return }
            
            // Create anchor if it doesn't exist
            if obstacleAnchor == nil {
                obstacleAnchor = AnchorEntity(.camera)
                arView.scene.addAnchor(obstacleAnchor!)
            }
            
            // Create left obstacle mesh if it doesn't exist
            if leftObstacleMeshEntity == nil {
                leftObstacleMeshEntity = createObstacleMesh(color: .red)
            }
            
            // Create right obstacle mesh if it doesn't exist
            if rightObstacleMeshEntity == nil {
                rightObstacleMeshEntity = createObstacleMesh(color: .blue)
            }
            
            // Create center obstacle mesh if it doesn't exist
            if centerObstacleMeshEntity == nil {
                centerObstacleMeshEntity = createObstacleMesh(color: .yellow)
            }
            
            // Position the meshes
            positionObstacleMeshes()
        }

        // Create a semi-transparent colored mesh for obstacle visualization
        func createObstacleMesh(color: UIColor) -> ModelEntity {
            let boxMesh = MeshResource.generateBox(width: 1.0, height: 2.0, depth: 0.2)
            let material = SimpleMaterial(color: color.withAlphaComponent(0.3), roughness: 0.3, isMetallic: true)
            let entity = ModelEntity(mesh: boxMesh, materials: [material])
            entity.isEnabled = false  // Start disabled
            
            // Add to obstacle anchor
            obstacleAnchor?.addChild(entity)
            
            return entity
        }

        // Position the obstacle meshes in front of the camera
        func positionObstacleMeshes() {
            // Left obstacle position
            leftObstacleMeshEntity?.position = SIMD3<Float>(-1.0, 0, -2.0)
            
            // Right obstacle position
            rightObstacleMeshEntity?.position = SIMD3<Float>(1.0, 0, -2.0)
            
            // Center obstacle position
            centerObstacleMeshEntity?.position = SIMD3<Float>(0, 0, -2.0)
        }

        // Update mesh visibility based on obstacle detection
        func updateMeshVisibility() {
            // Make meshes visible or invisible based on obstacle detection
            leftObstacleMeshEntity?.isEnabled = leftObstaclePresent
            rightObstacleMeshEntity?.isEnabled = rightObstaclePresent
            centerObstacleMeshEntity?.isEnabled = centerObstaclePresent
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
