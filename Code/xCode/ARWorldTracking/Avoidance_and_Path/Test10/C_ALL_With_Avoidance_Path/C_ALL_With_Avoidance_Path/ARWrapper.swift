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
    @Binding var obstacleOffset: Double
    @Binding var depthImage: UIImage?
    @Binding var isUsingLidar: Bool
    @Binding var showObstacleMeshes: Bool
    @Binding var showSceneMesh: Bool
    @Binding var depthHorizontalShift: Int  // Binding for horizontal shift
    @Binding var depthVerticalShift: Int    // Binding for vertical shift
    @Binding var showDepthOverlay: Bool     // Binding for depth overlay toggle

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        
        // Reduce default rendering quality to improve performance
        arView.renderOptions = [.disableFaceMesh, .disableMotionBlur, .disableDepthOfField]
        
        // Only show necessary debug visualizations
        arView.debugOptions = []  // Start with none, toggle as needed
        
        startGeoTracking(in: arView, coordinator: context.coordinator)
        arView.session.delegate = context.coordinator
        
        // Only create obstacle meshes if actually showing them
        if showObstacleMeshes {
            context.coordinator.setupObstacleMeshes()
        }
        
        // Add coaching overlay
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
        
        // Update obstacle meshes
        if let leftMesh = context.coordinator.leftObstacleMeshEntity,
           let rightMesh = context.coordinator.rightObstacleMeshEntity,
           let centerMesh = context.coordinator.centerObstacleMeshEntity {
            
            leftMesh.isEnabled = showObstacleMeshes && context.coordinator.leftObstaclePresent
            rightMesh.isEnabled = showObstacleMeshes && context.coordinator.rightObstaclePresent
            centerMesh.isEnabled = showObstacleMeshes && context.coordinator.centerObstaclePresent
        } else if showObstacleMeshes {
            // Only create meshes if they don't exist and are needed
            context.coordinator.setupObstacleMeshes()
        }
        
        // Update ARKit debug options for scene mesh
        if showSceneMesh != context.coordinator.debugMeshEnabled {
            context.coordinator.debugMeshEnabled = showSceneMesh
            
            // Use built-in mesh visualization
            if showSceneMesh {
                uiView.debugOptions = [.showSceneUnderstanding]
            } else {
                uiView.debugOptions = []
            }
        }
    }

    private func startGeoTracking(in arView: ARView, coordinator: Coordinator) {
        guard ARGeoTrackingConfiguration.isSupported else {
            print("DEBUG: ARGeoTracking not supported on this device")
            return
        }
        
        let config = ARGeoTrackingConfiguration()
        
        // Reduce quality for better performance
        config.environmentTexturing = .automatic
        
        // Only enable depth data if we're actually using it
        if #available(iOS 14.0, *) {
            if (showDepthOverlay || showObstacleMeshes) && 
               ARGeoTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
                print("DEBUG: Enabled scene depth in configuration")
            }
        }
        
        // Add performance-focused configuration
        if #available(iOS 13.4, *) {
            config.videoHDRAllowed = false  // Disable HDR for better performance
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

        // Add scene mesh visualization properties
        var sceneMeshAnchor: AnchorEntity?
        var sceneMeshEntity: ModelEntity?
        var meshOrigin: simd_float4x4?
        var meshUpdateCounter: Int = 0 // To limit update frequency

        // Simplified scene mesh properties
        var debugMeshEnabled: Bool = false

        // Add a frame counter to limit processing frequency
        private var frameCounter = 0
        private var lastProcessingTime = CFAbsoluteTimeGetCurrent()
        
        // Add automatic cleanup
        private var cleanupTimer: Timer?
        
        // Outside any function, at class/struct level:
        private var depthFrameCounter = 0
        
        init(_ parent: ARWrapper) {
            self.parent = parent
            super.init()
            
            // Setup a timer for periodic cleanup
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                self?.performMemoryCleanup()
            }
            
            // Check device capability for LiDAR at initialization
            if #available(iOS 14.0, *) {
                let deviceHasLiDAR = ARConfiguration.supportsFrameSemantics(.sceneDepth)
                print("DEBUG: Coordinator init - Device has LiDAR: \(deviceHasLiDAR)")
            } else {
                print("DEBUG: Coordinator init - iOS < 14.0, no LiDAR support expected")
            }
        }

        deinit {
            cleanupTimer?.invalidate()
        }

        func performMemoryCleanup() {
            // Release any cached resources
            if !parent.showObstacleMeshes {
                leftObstacleMeshEntity = nil
                rightObstacleMeshEntity = nil
                centerObstacleMeshEntity = nil
            }
            
            // Force a garbage collection cycle
            autoreleasepool {
                // Just creating an autorelease pool can help with memory
            }
            
            print("DEBUG: Memory cleanup performed")
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
            // Throttle processing for better performance
            frameCounter += 1
            if frameCounter % 2 != 0 {
                return  // Process every other frame
            }
            
            // Update obstacle mesh positions
            positionObstacleMeshes()
            
            // Process depth or feature points for obstacle detection
            if frame.sceneDepth != nil {
                // Use depth data for obstacle detection
                processDepthDataForObstacles(frame: frame)
                
                // Update depth visualization if enabled
                if parent.showDepthOverlay {
                    parent.depthImage = createDepthVisualization(depthMap: frame.sceneDepth!.depthMap)
                }
                
                DispatchQueue.main.async {
                    self.parent.isUsingLidar = true
                }
            } else {
                // Use feature points for obstacle detection
                updateObstacleOffsetFromFeaturePoints(frame: frame)
                DispatchQueue.main.async {
                    self.parent.isUsingLidar = false
                }
            }
            
            // Clean up resources periodically
            cleanupUnusedResources()
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
            _ = cameraTransform.columns.1.xyz  // Or just remove it if not needed
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
            // Check if depth data is available
            guard let depthMap = frame.sceneDepth?.depthMap else {
                print("DEBUG: processDepthDataForObstacles called but no depth map available")
                return
            }
            
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            // Lock the buffer
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                return
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // Define regions of interest
            let leftRegion = CGRect(x: 0, y: 0, width: width/3, height: height)
            let rightRegion = CGRect(x: 2*width/3, y: 0, width: width/3, height: height)
            
            var leftObstacleCount = 0
            var rightObstacleCount = 0
            
            // Sample at a lower resolution to improve performance
            let samplingStep = 8  // Check every 8th pixel
            
            // Check points in the left region
            for y in stride(from: Int(leftRegion.minY), to: Int(leftRegion.maxY), by: samplingStep) {
                for x in stride(from: Int(leftRegion.minX), to: Int(leftRegion.maxX), by: samplingStep) {
                    let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                    let depth = depthData[offset]
                    
                    // Count as obstacle if within range (0.3m to 1.5m)
                    if depth >= 0.3 && depth <= 1.5 {
                        leftObstacleCount += 1
                    }
                }
            }
            
            // Check points in the right region
            for y in stride(from: Int(rightRegion.minY), to: Int(rightRegion.maxY), by: samplingStep) {
                for x in stride(from: Int(rightRegion.minX), to: Int(rightRegion.maxX), by: samplingStep) {
                    let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                    let depth = depthData[offset]
                    
                    // Count as obstacle if within range (0.3m to 1.5m)
                    if depth >= 0.3 && depth <= 1.5 {
                        rightObstacleCount += 1
                    }
                }
            }
            
            // Calculate obstacle presence
            let threshold = width * height / (samplingStep * samplingStep) / 20  // Adaptive threshold
            
            // Determine obstacle direction
            var offset: Double = 0
            leftObstaclePresent = leftObstacleCount > threshold
            rightObstaclePresent = rightObstacleCount > threshold
            
            // Fix the type conversion issue here
            let leftThreshold = Int(Double(rightObstacleCount) * 1.2)
            let rightThreshold = Int(Double(leftObstacleCount) * 1.2)
            
            if leftObstacleCount > threshold && leftObstacleCount > leftThreshold {
                // More obstacles on left, steer right
                offset = 30
            } else if rightObstacleCount > threshold && rightObstacleCount > rightThreshold {
                // More obstacles on right, steer left
                offset = -30
            }
            
            self.parent.obstacleOffset = offset
        }

        func createDepthVisualization(depthMap: CVPixelBuffer) -> UIImage? {
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            // Lock the buffer
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            // Get depth data
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                return nil
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // Create an RGBA bitmap context for the output
            let rotatedWidth = height
            let rotatedHeight = width
            let bitsPerComponent = 8
            let bytesPerPixel = 4
            let rotatedBytesPerRow = rotatedWidth * bytesPerPixel
            
            guard let context = CGContext(
                data: nil,
                width: rotatedWidth,
                height: rotatedHeight,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: rotatedBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            
            guard let buffer = context.data else {
                return nil
            }
            
            let pixelBuffer = buffer.bindMemory(to: UInt8.self, capacity: rotatedHeight * rotatedBytesPerRow)
            
            // Define min/max depth range for visualization
            let minDepth: Float = 0.0
            let maxDepth: Float = 3.0  // 3 meters
            
            // Use parent's shift values
            let horizontalShift = parent.depthHorizontalShift
            let verticalShift = parent.depthVerticalShift
            
            // Moderate downsampling for performance
            let downsample = 2
            
            // ROTATE LEFT (90° counterclockwise) WITH SHIFTS
            for y in stride(from: 0, to: height, by: downsample) {
                for x in stride(from: 0, to: width, by: downsample) {
                    let inputOffset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                    let depth = depthData[inputOffset]
                    
                    // Skip invalid depth values
                    if depth.isNaN || depth < minDepth || depth > maxDepth {
                        continue
                    }
                    
                    // Normalize depth value to 0-1 range
                    let normalizedDepth = 1.0 - ((depth - minDepth) / (maxDepth - minDepth))
                    
                    // Convert to color (red = near, blue = far)
                    let red = UInt8(normalizedDepth * 255.0)
                    let blue = UInt8((1.0 - normalizedDepth) * 255.0)
                    
                    // Compute rotated coordinates (90° counterclockwise)
                    let rotatedX = height - 1 - y
                    let rotatedY = x
                    
                    // Apply shifts
                    let shiftedX = rotatedX + horizontalShift
                    let shiftedY = rotatedY + verticalShift
                    
                    // Skip if the shifted coordinate is outside bounds
                    if shiftedX < 0 || shiftedX >= rotatedWidth || 
                       shiftedY < 0 || shiftedY >= rotatedHeight {
                        continue
                    }
                    
                    // Set pixel color in output buffer
                    let outputOffset = (shiftedY * rotatedBytesPerRow) + (shiftedX * bytesPerPixel)
                    pixelBuffer[outputOffset] = red     // R
                    pixelBuffer[outputOffset + 1] = 0   // G
                    pixelBuffer[outputOffset + 2] = blue // B
                    pixelBuffer[outputOffset + 3] = 255 // A (fully opaque)
                    
                    // Fill a small square for each depth point to compensate for downsampling
                    for dy in 0..<downsample {
                        for dx in 0..<downsample {
                            let fillX = shiftedX + dx
                            let fillY = shiftedY + dy
                            if fillX < rotatedWidth && fillY < rotatedHeight {
                                let fillOffset = (fillY * rotatedBytesPerRow) + (fillX * bytesPerPixel)
                                pixelBuffer[fillOffset] = red     // R
                                pixelBuffer[fillOffset + 1] = 0   // G
                                pixelBuffer[fillOffset + 2] = blue // B
                                pixelBuffer[fillOffset + 3] = 255 // A (fully opaque)
                            }
                        }
                    }
                }
            }
            
            // Create image from context
            guard let cgImage = context.makeImage() else {
                return nil
            }
            
            return UIImage(cgImage: cgImage)
        }

        // Helper function to add orientation markers
        func addOrientationMarkers(to inputImage: CGImage) -> CGImage {
            let width = inputImage.width
            let height = inputImage.height
            
            // Create a context with the same dimensions
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            
            // Draw the original image
            context.draw(inputImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Draw orientation markers
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(5)
            
            // Draw a T shape at the top of the image
            context.move(to: CGPoint(x: width/2, y: 10))
            context.addLine(to: CGPoint(x: width/2, y: height/10))
            context.strokePath()
            
            context.move(to: CGPoint(x: width/2 - width/10, y: 10))
            context.addLine(to: CGPoint(x: width/2 + width/10, y: 10))
            context.strokePath()
            
            // Draw a circle at the right side
            context.addEllipse(in: CGRect(x: width - 30, y: height/2 - 15, width: 30, height: 30))
            context.strokePath()
            
            // Draw a square at the bottom
            context.addRect(CGRect(x: width/2 - 15, y: height - 30, width: 30, height: 30))
            context.strokePath()
            
            // Draw a triangle at the left side
            context.move(to: CGPoint(x: 15, y: height/2))
            context.addLine(to: CGPoint(x: 30, y: height/2 - 15))
            context.addLine(to: CGPoint(x: 30, y: height/2 + 15))
            context.closePath()
            context.strokePath()
            
            // Get the resulting image
            return context.makeImage()!
        }

        // Method to create and position obstacle meshes
        func setupObstacleMeshes() {
            guard let arView = arView else { return }
            
            // Create anchor if it doesn't exist
            if obstacleAnchor == nil {
                obstacleAnchor = AnchorEntity(.camera)
                arView.scene.addAnchor(obstacleAnchor!)
            }
            
            // Create meshes using a shared material to reduce memory usage
            let redMaterial = SimpleMaterial(color: .red.withAlphaComponent(0.3), roughness: 0.5, isMetallic: false)
            let blueMaterial = SimpleMaterial(color: .blue.withAlphaComponent(0.3), roughness: 0.5, isMetallic: false)
            let yellowMaterial = SimpleMaterial(color: .yellow.withAlphaComponent(0.3), roughness: 0.5, isMetallic: false)
            
            // Use a shared mesh for all obstacles to reduce memory usage
            let sharedMesh = MeshResource.generateBox(width: 1.0, height: 2.0, depth: 0.2)
            
            // Create obstacle entities
            leftObstacleMeshEntity = ModelEntity(mesh: sharedMesh, materials: [redMaterial])
            rightObstacleMeshEntity = ModelEntity(mesh: sharedMesh, materials: [blueMaterial])
            centerObstacleMeshEntity = ModelEntity(mesh: sharedMesh, materials: [yellowMaterial])
            
            // Position meshes
            leftObstacleMeshEntity?.position = SIMD3<Float>(-1.0, 0, -2.0)
            rightObstacleMeshEntity?.position = SIMD3<Float>(1.0, 0, -2.0)
            centerObstacleMeshEntity?.position = SIMD3<Float>(0, 0, -2.0)
            
            // Start with all meshes disabled
            leftObstacleMeshEntity?.isEnabled = false
            rightObstacleMeshEntity?.isEnabled = false
            centerObstacleMeshEntity?.isEnabled = false
            
            // Add to scene
            obstacleAnchor?.addChild(leftObstacleMeshEntity!)
            obstacleAnchor?.addChild(rightObstacleMeshEntity!)
            obstacleAnchor?.addChild(centerObstacleMeshEntity!)
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

        // Add a lightweight obstacle detection function
        func processDepthDataForObstaclesLightweight(frame: ARFrame) {
            guard let depthMap = frame.sceneDepth?.depthMap else { return }
            
            // Very lightweight sampling - just check a few key areas
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
            let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // Sample just 9 points (left, center, right) x (top, middle, bottom)
            var leftObstacleCount = 0
            var rightObstacleCount = 0
            
            // Use very sparse sampling - just a few points in each region
            let samplePoints = [
                (width/6, height/4), (width/6, height/2), (width/6, 3*height/4),   // Left column
                (width/2, height/4), (width/2, height/2), (width/2, 3*height/4),   // Center column
                (5*width/6, height/4), (5*width/6, height/2), (5*width/6, 3*height/4)  // Right column
            ]
            
            for (x, y) in samplePoints {
                let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                let depth = depthData[offset]
                
                // Skip invalid depths or those too far away
                if depth.isNaN || depth <= 0.2 || depth > 3.0 {
                    continue
                }
                
                // Count obstacles in left and right regions
                if x < width/3 {
                    leftObstacleCount += 1
                } else if x > 2*width/3 {
                    rightObstacleCount += 1
                }
            }
            
            // Determine obstacle direction
            var offset: Double = 0
            if leftObstacleCount > rightObstacleCount && leftObstacleCount >= 2 {
                offset = 30
            } else if rightObstacleCount > leftObstacleCount && rightObstacleCount >= 2 {
                offset = -30
            }
            
            self.parent.obstacleOffset = offset
        }

        func cleanupUnusedResources() {
            // Only perform cleanup occasionally
            if frameCounter % 300 != 0 { // Every ~10 seconds at 30fps
                return
            }
            
            // Force release autoreleased objects
            autoreleasepool {
                if !parent.showDepthOverlay && parent.depthImage != nil {
                    DispatchQueue.main.async {
                        self.parent.depthImage = nil
                    }
                }
            }
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
