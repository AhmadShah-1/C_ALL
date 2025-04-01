import SwiftUI
import ARKit
import RealityKit
import CoreLocation


// Helper function to compare two arrays of CLLocationCoordinate2D
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
    @Binding var clearPathAngle: Double     // New binding for clear path angle
    @Binding var isPathClear: Bool          // New binding for if a clear path exists
    @Binding var showClusteredDepthOverlay: Bool  // New binding for simplified cluster overlay
    @Binding var maxDepthDistance: Float    // New binding for configurable max depth distance
    @Binding var minClearDistance: Float    // New binding for minimum clear path distance
    @Binding var guidanceInstruction: Int   // -1: Turn Left, 0: Straight/Blocked, 1: Turn Right

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
        
        // Obstacle detection parameters - Keep track of the last known state
        var leftObstaclePresent: Bool = false
        var rightObstaclePresent: Bool = false
        var centerObstaclePresent: Bool = false
        private var lastKnownIsPathClear: Bool = false
        private var lastKnownClearPathAngle: Double = 0.0
        private var lastKnownGuidanceInstruction: Int = 0 // Track internal state

        // --- Add state tracking for parent updates ---
        private var lastSentIsUsingLidar: Bool? = nil
        private var lastSentClearPathAngle: Double? = nil
        private var lastSentIsPathClear: Bool? = nil
        private var lastSentGuidanceInstruction: Int? = nil // Track sent state

        // Add scene mesh visualization properties
        var sceneMeshAnchor: AnchorEntity?
        var sceneMeshEntity: ModelEntity?
        var meshOrigin: simd_float4x4?
        var meshUpdateCounter: Int = 0 // To limit update frequency

        // Simplified scene mesh properties
        var debugMeshEnabled: Bool = false

        // Add a frame counter to limit processing frequency
        private var frameCounter = 0
        private let depthProcessingFrameInterval = 5 // Process depth every 5 frames
        private var lastProcessingTime = CFAbsoluteTimeGetCurrent()
        
        // Add automatic cleanup
        private var cleanupTimer: Timer?
        
        // Outside any function, at class/struct level:
        private var depthFrameCounter = 0
        
        // Add properties for angle smoothing
        private var smoothedClearPathAngleRadians: Float? = nil
        private let angleSmoothingFactor: Float = 0.2 // Adjust for more/less smoothing (lower = more smoothing)
        
        // Cached clustered depth image
        private var clusteredDepthImage: UIImage?
        private var lastClusterUpdateTime: Double = 0
        
        init(_ parent: ARWrapper) {
            self.parent = parent
            super.init()
            
            // Setup a timer for periodic cleanup
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                // self?.performMemoryCleanup() // Comment out noisy cleanup log
            }
            
            // Check device capability for LiDAR at initialization
            // if #available(iOS 14.0, *) {
            //     let deviceHasLiDAR = ARConfiguration.supportsFrameSemantics(.sceneDepth)
            //     print("DEBUG: Coordinator init - Device has LiDAR: \(deviceHasLiDAR)")
            // } else {
            //     print("DEBUG: Coordinator init - iOS < 14.0, no LiDAR support expected")
            // }
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
            
            print("DEBUG: Memory cleanup performed") // Keep?
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
            frameCounter += 1

            // --- Only process depth data periodically ---
            guard frameCounter % depthProcessingFrameInterval == 0 else {
                // On skipped frames, do NOT update UI state, just maintain internal state.
                updateMeshVisibility() // Update mesh visibility based on last known internal state
                return
            }

            // Update obstacle mesh positions (can happen every frame)
            positionObstacleMeshes()

            // Process depth data if available
            if let depth = frame.sceneDepth {
                // Use depth data for obstacle detection and clear path finding
                if let rawClearPathAngleRadians = findClearPathFromDepthData(frame: frame) {
                    
                    // --- Apply Smoothing ---
                    if smoothedClearPathAngleRadians == nil {
                        smoothedClearPathAngleRadians = rawClearPathAngleRadians // Initialize on first valid reading
                    } else {
                        // Exponential Moving Average
                        smoothedClearPathAngleRadians = (angleSmoothingFactor * rawClearPathAngleRadians) + ((1.0 - angleSmoothingFactor) * smoothedClearPathAngleRadians!)
                        
                        // Handle wrap-around for smoothing (ensure angle stays in 0 to 2pi)
                         if smoothedClearPathAngleRadians! < 0 { smoothedClearPathAngleRadians! += 2 * Float.pi }
                         if smoothedClearPathAngleRadians! >= 2 * Float.pi { smoothedClearPathAngleRadians! -= 2 * Float.pi }
                    }

                    // Use the smoothed angle for calculations and UI
                    let smoothedAngleDegrees = Double(smoothedClearPathAngleRadians! * 180 / Float.pi)
                    lastKnownClearPathAngle = smoothedAngleDegrees
                    lastKnownIsPathClear = true

                    // --- Interpret Smoothed Angle relative to CORRECTED Forward (0 degrees) ---
                    let forwardDirection: Float = 0.0 // 0 degrees = Forward in calculated system
                    let tolerance: Float = Float.pi / 12 // +/- 15 degrees tolerance
                    let twoPi: Float = 2 * Float.pi

                    let angle = smoothedClearPathAngleRadians!
                    
                    // Calculate shortest distance to forward (0 degrees), handling wrap-around
                    let diffToForward = abs(angle - forwardDirection)
                    let distanceToForward = min(diffToForward, twoPi - diffToForward)

                    if distanceToForward <= tolerance {
                        // Angle is Forward (within tolerance of 0 degrees)
                        leftObstaclePresent = false
                        rightObstaclePresent = false
                        centerObstaclePresent = false // Path clear ahead
                    } else if angle > tolerance && angle < Float.pi - tolerance { 
                        // Angle is Right of Forward (approx 15° to 165°) -> Path is Right
                        leftObstaclePresent = true  // OBSTACLE IS LEFT
                        rightObstaclePresent = false
                        centerObstaclePresent = false
                    } else if angle > Float.pi + tolerance && angle < twoPi - tolerance {
                        // Angle is Left of Forward (approx 195° to 345°) -> Path is Left
                        leftObstaclePresent = false
                        rightObstaclePresent = true // OBSTACLE IS RIGHT
                        centerObstaclePresent = false
                    } else {
                        // Angle is backward or near +/- 180 degrees (invalid for forward path)
                        // Treat as forward path blocked/uncertain.
                        leftObstaclePresent = false // Reset
                        rightObstaclePresent = false // Reset
                        centerObstaclePresent = true // Indicate forward blockage/uncertainty
                        lastKnownGuidanceInstruction = 0 // Reset guidance
                        if frameCounter % 300 == 0 { print("ANGLE DEBUG: Smoothed angle (\(angle * 180 / Float.pi)°) points backward/invalid. Assuming forward path blocked.") }
                    }

                    // --- Calculate Guidance Instruction based on flags --- REVERSED
                    var currentGuidance: Int = 0
                    if leftObstaclePresent { // Obstacle Left -> Turn Left
                        currentGuidance = -1 // Swapped from 1
                    } else if rightObstaclePresent { // Obstacle Right -> Turn Right
                        currentGuidance = 1  // Swapped from -1
                    } else { // Straight or Blocked
                        currentGuidance = 0
                    }

                    // --- Store calculated guidance instruction internally ---
                    lastKnownGuidanceInstruction = currentGuidance

                    // Debug prints using smoothed angle (Keep these)
                    if frameCounter % 300 == 0 { // Print less frequently
                         print("ANGLE DEBUG (Smoothed): Clear path angle: \(smoothedAngleDegrees)° (Raw: \(rawClearPathAngleRadians * 180 / Float.pi)°)")
                         print("ANGLE DEBUG (Flags Set): Left Obstacle: \(leftObstaclePresent), Right Obstacle: \(rightObstaclePresent), Center Obstacle: \(centerObstaclePresent)")
                         // Optional: Keep distance refs if helpful, otherwise remove
                         // print("ANGLE DEBUG (Smoothed): Dist to 90° ref: \(angularDistanceToLeftRef), Dist to 270° ref: \(angularDistanceToRightRef)")
                    }
                    
                    // Update mesh visibility based on current obstacle flags
                    updateMeshVisibility()
                    
                    // --- Update Visualizations (less frequently or if needed) ---
                    let shouldUpdateVisuals = frameCounter % (depthProcessingFrameInterval * 2) == 0 // Further reduce viz updates

                    if parent.showDepthOverlay && shouldUpdateVisuals {
                        parent.depthImage = createDepthVisualization(depthMap: depth.depthMap)
                    }
                    
                    if parent.showClusteredDepthOverlay && shouldUpdateVisuals {
                        clusteredDepthImage = createClusteredDepthVisualization(frame: frame)
                        parent.depthImage = clusteredDepthImage
                    }
                    
                    // Update parent state (use last known values) - ONLY IF CHANGED
                    DispatchQueue.main.async {
                        let currentIsUsingLidar = true // Since we are in the depth processing block
                        var didUpdate = false
                        
                        if self.lastSentIsUsingLidar != currentIsUsingLidar {
                            self.parent.isUsingLidar = currentIsUsingLidar
                            self.lastSentIsUsingLidar = currentIsUsingLidar
                            didUpdate = true
                        }
                        if self.lastSentClearPathAngle != self.lastKnownClearPathAngle {
                            self.parent.clearPathAngle = self.lastKnownClearPathAngle
                            self.lastSentClearPathAngle = self.lastKnownClearPathAngle
                            didUpdate = true
                        }
                        if self.lastSentIsPathClear != self.lastKnownIsPathClear {
                            self.parent.isPathClear = self.lastKnownIsPathClear
                            self.lastSentIsPathClear = self.lastKnownIsPathClear
                            didUpdate = true
                        }
                        if self.lastSentGuidanceInstruction != currentGuidance {
                            self.parent.guidanceInstruction = currentGuidance
                            self.lastSentGuidanceInstruction = currentGuidance
                            didUpdate = true
                        }
                        // if didUpdate { print("DEBUG: UI State Updated") } // Optional: for debugging UI updates
                    }
                } else {
                    // No clear path found this frame
                    lastKnownIsPathClear = false
                    smoothedClearPathAngleRadians = nil // Reset smoother
                     if frameCounter % 300 == 0 { print("ANGLE DEBUG: No clear path found this frame. Resetting side flags.") }
                    
                    // --- Reset obstacle flags when no clear path is found ---
                    leftObstaclePresent = false
                    rightObstaclePresent = false
                    centerObstaclePresent = true // Indicate forward path uncertain/blocked
                    lastKnownGuidanceInstruction = 0 // Reset guidance when path lost

                    // --- Update parent state ONLY IF 'isPathClear' changed ---
                     DispatchQueue.main.async {
                         if self.lastSentIsPathClear != self.lastKnownIsPathClear {
                             self.parent.isPathClear = self.lastKnownIsPathClear
                             self.lastSentIsPathClear = self.lastKnownIsPathClear
                             // Maybe also update angle to 0 or a specific value when path is lost?
                             // self.parent.clearPathAngle = 0
                             // self.lastSentClearPathAngle = 0
                         }
                         // Also update lidar status if needed
                          let currentIsUsingLidar = true // Still using lidar attempt even if path not found
                          if self.lastSentIsUsingLidar != currentIsUsingLidar {
                              self.parent.isUsingLidar = currentIsUsingLidar
                              self.lastSentIsUsingLidar = currentIsUsingLidar
                          }
                          // Also reset guidance instruction if lidar is lost
                          if self.lastSentGuidanceInstruction != 0 {
                              self.parent.guidanceInstruction = 0
                              self.lastSentGuidanceInstruction = 0
                          }
                     }
                }
                
                // Update mesh visibility based on current internal obstacle flags
                updateMeshVisibility()
                
                // --- Update Visualizations (less frequently or if needed) ---
                let shouldUpdateVisuals = frameCounter % (depthProcessingFrameInterval * 2) == 0 // Further reduce viz updates

                if parent.showDepthOverlay && shouldUpdateVisuals {
                    parent.depthImage = createDepthVisualization(depthMap: depth.depthMap)
                }
                
                if parent.showClusteredDepthOverlay && shouldUpdateVisuals {
                    clusteredDepthImage = createClusteredDepthVisualization(frame: frame)
                    parent.depthImage = clusteredDepthImage
                }
                
                // Print depth settings occasionally for debugging
                // if frameCounter % 300 == 0 {
                //     // Print point distribution grid
                //     print("Depth Point Distribution (5x5 grid):")
                //     for row in depthPointsGrid {
                //         let rowStr = row.map { $0 > 0 ? "O" : "·" }.joined()
                //         print(rowStr)
                //     }
                    
                //     print("Clear Point Distribution (5x5 grid):")
                //     for row in clearPointsGrid {
                //         let rowStr = row.map { $0 > 0 ? "C" : "·" }.joined()
                //         print(rowStr)
                //     }
                    
                //     print("Sector occupation (0° → 360°): \(sectorDebug)")
                //     print("Total sampled: \(totalSampledPoints), Valid: \(validSamplePoints), Beyond range: \(beyondRangePoints) (\(Float(beyondRangePoints)/Float(validSamplePoints) * 100)% of valid points)")
                //     print("Using min clear distance: \(minClearDistance)m, max visual range: \(maxDepthDistance)m")
                // }
            } else {
                // --- Handle case where frame.sceneDepth is nil ---
                smoothedClearPathAngleRadians = nil // Reset smoother
                
                // --- Update parent state ONLY IF 'isUsingLidar' changed ---
                DispatchQueue.main.async {
                    let currentIsUsingLidar = false
                    if self.lastSentIsUsingLidar != currentIsUsingLidar {
                        self.parent.isUsingLidar = currentIsUsingLidar
                        self.lastSentIsUsingLidar = currentIsUsingLidar
                    }
                    // Also ensure path clear is false if lidar is lost
                    if self.lastSentIsPathClear != false {
                         self.parent.isPathClear = false
                         self.lastSentIsPathClear = false
                    }
                    // Also reset guidance instruction if lidar is lost
                    if self.lastSentGuidanceInstruction != 0 {
                        self.parent.guidanceInstruction = 0
                        self.lastSentGuidanceInstruction = 0
                    }
                }
                 // Update mesh visibility based on *last known* internal state
                updateMeshVisibility()
            }
            
            // Clean up resources periodically (can stay as is)
            cleanupUnusedResources()
        }

        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            // Optionally handle overlay deactivation.
        }

        func findClearPathFromDepthData(frame: ARFrame) -> Float? {
            guard let depthMap = frame.sceneDepth?.depthMap else {
                return nil
            }
            
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            // Create depth sectors for determining clearest path
            let sectorCount = 16  // Number of sectors to check
            let sectorWidth = Float.pi / Float(sectorCount) // Width of each sector in radians (1/4 of the full circle)
            
            var sectorClearPoints = [Int](repeating: 0, count: sectorCount * 2) // Full 360° circle
            var sectorTotalValidPoints = [Int](repeating: 0, count: sectorCount * 2)
            
            // Set up fixed parameters
            let maxDepthDistance: Float = 4.0 // Maximum visual range fixed at 4.0m
            let minClearDistance = parent.minClearDistance // Minimum distance needed to be considered "clear"
            
            // Use iPhone camera center for calculations
            let centerX = width / 2
            let centerY = height / 2
            
            // Lock the buffer for reading
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                return nil
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // Sample more points for better accuracy
            let step = 8  // Sample every 8th pixel for a balance of performance and accuracy
            
            var totalSampledPoints = 0
            var validSamplePoints = 0
            var beyondRangePoints = 0
            
            // Debug matrices to visualize point distribution (5x5 grid)
            var depthPointsGrid = [[Int]](repeating: [Int](repeating: 0, count: 5), count: 5)
            var clearPointsGrid = [[Int]](repeating: [Int](repeating: 0, count: 5), count: 5)
            
            for y in stride(from: height/4, to: 3*height/4, by: step) {
                for x in stride(from: width/4, to: 3*width/4, by: step) {
                    totalSampledPoints += 1
                    
                    // Calculate coordinates relative to center
                    let relX = Float(x - centerX)
                    let relY = Float(y - centerY)
                    
                    // For debug visualization, map to a 5x5 grid
                    let gridX = min(max(Int((Float(x) / Float(width)) * 5), 0), 4)
                    let gridY = min(max(Int((Float(y) / Float(height)) * 5), 0), 4)
                    
                    // Calculate angle directly from relative coordinates (atan2(y,x))
                    // Should result in: 0=Forward, 90=Right, 180=Backward, 270=Left
                    var angle = atan2(relY, relX)
                    // Normalize angle to 0 to 2π range
                    if angle < 0 {
                        angle += 2 * Float.pi
                    }
                    
                    // Calculate corresponding sector 
                    let sectorIndex = min(Int(angle / sectorWidth), sectorCount * 2 - 1)
                    
                    // Get depth value
                    let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                    let depth = depthData[offset]
                    
                    // Skip NaN or zero depth values
                    if depth.isNaN || depth <= 0 {
                        continue
                    }
                    
                    validSamplePoints += 1
                    depthPointsGrid[gridY][gridX] += 1
                    
                    // Points beyond max depth distance are treated as clear paths
                    if depth > maxDepthDistance {
                        sectorClearPoints[sectorIndex] += 1
                        beyondRangePoints += 1
                        sectorTotalValidPoints[sectorIndex] += 1
                        clearPointsGrid[gridY][gridX] += 1
                        continue
                    }
                    
                    // Count points that are beyond our minimum clear distance
                    if depth >= minClearDistance && depth <= maxDepthDistance {
                        sectorClearPoints[sectorIndex] += 1
                        clearPointsGrid[gridY][gridX] += 1
                    }
                    
                    sectorTotalValidPoints[sectorIndex] += 1
                }
            }
            
            // Find the sector with the most clear space (highest percentage)
            // --- MODIFIED: Find sector with highest ABSOLUTE number of clear points ---
            var maxClearPoints: Int = -1 // Use -1 to ensure any sector with points is initially better
            var clearestSectorIndex = -1
            
            // Debug string to visualize sector occupation
            // var sectorDebug = ""
            
            for i in 0..<(sectorCount * 2) {
                if sectorTotalValidPoints[i] > 0 {
                    let clearPercentage = Float(sectorClearPoints[i]) / Float(sectorTotalValidPoints[i])
                    
                    // Build sector visualization (C=clear, X=obstacle)
                    // let sectorChar = clearPercentage >= 0.6 ? "C" : "X"
                    // sectorDebug += sectorChar
                    
                    // Debug: Print sector percentages occasionally
                    // if frameCounter % 300 == 0 && i % 4 == 0 {
                    //     let angleInDegrees = Float(i) * sectorWidth * 180 / Float.pi
                    //     print("Sector \(i) (\(angleInDegrees)°): \(clearPercentage * 100)% clear (\(sectorClearPoints[i])/\(sectorTotalValidPoints[i]))")
                    // }
                    
                    // --- Compare based on absolute count --- 
                    if sectorClearPoints[i] > maxClearPoints {
                        maxClearPoints = sectorClearPoints[i]
                        clearestSectorIndex = i
                    }
                } else {
                    // sectorDebug += "·" // Empty sector
                }
            }
            
            // Print detailed debug information occasionally
            // if frameCounter % 300 == 0 {
            //     // Print point distribution grid
            //     print("Depth Point Distribution (5x5 grid):")
            //     for row in depthPointsGrid {
            //         let rowStr = row.map { $0 > 0 ? "O" : "·" }.joined()
            //         print(rowStr)
            //     }
                
            //     print("Clear Point Distribution (5x5 grid):")
            //     for row in clearPointsGrid {
            //         let rowStr = row.map { $0 > 0 ? "C" : "·" }.joined()
            //         print(rowStr)
            //     }
                
            //     print("Sector occupation (0° → 360°): \(sectorDebug)")
            //     print("Total sampled: \(totalSampledPoints), Valid: \(validSamplePoints), Beyond range: \(beyondRangePoints) (\(Float(beyondRangePoints)/Float(validSamplePoints) * 100)% of valid points)")
            //     print("Using min clear distance: \(minClearDistance)m, max visual range: \(maxDepthDistance)m")
            // }
            
            // If we found a clear sector with sufficient data
            // --- MODIFIED: Check if any clear points were found, maybe add minimum threshold later --- 
            if clearestSectorIndex >= 0 && maxClearPoints > 5 { // Require at least a few clear points
                // Calculate the center angle of the sector in radians (0 is front)
                let sectorAngle = (Float(clearestSectorIndex) + 0.5) * sectorWidth
                
                // Debug: Print chosen sector occasionally
                // if frameCounter % 300 == 0 {
                //     print("Clearest sector: \(clearestSectorIndex) (\(maxClearPercentage * 100)% clear)")
                //     print("Angle: \(sectorAngle * 180 / Float.pi)° from front")
                // }
                
                return sectorAngle
            }
            
            return nil // No clear path found
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
            
            // Define min/max depth range for visualization - FIXED at 4.0 meters
            let minDepth: Float = 0.0
            let maxDepth: Float = 4.0 // Fixed at 4.0 meters for consistent visualization
            
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
            // --- Add Debug Print Here ---
            if frameCounter % 15 == 0 { // Print occasionally to avoid spam
               print("VIS DEBUG: Flags before mesh update: L=\(leftObstaclePresent), R=\(rightObstaclePresent), C=\(centerObstaclePresent)")
            }
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

        /// Creates a lightweight clustered visualization of depth data
        func createClusteredDepthVisualization(frame: ARFrame) -> UIImage? {
            guard let depthMap = frame.sceneDepth?.depthMap else {
                return nil
            }
            
            // For performance, only update the cluster visualization occasionally
            let currentTime = CFAbsoluteTimeGetCurrent()
            if (currentTime - lastClusterUpdateTime < 0.5) && clusteredDepthImage != nil {
                return clusteredDepthImage // Return cached image if recently updated
            }
            
            lastClusterUpdateTime = currentTime
            
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            // Define cluster grid dimensions - using fewer cells for performance
            let gridWidth = 16  // Use a 16x12 grid for clustering
            let gridHeight = 12
            
            // Set up distance thresholds for color coding - using fixed values
            let nearThreshold: Float = parent.minClearDistance * 0.67  // ~2/3 of min clear distance is "near"
            let midThreshold: Float = parent.minClearDistance  // exactly at min clear distance is "mid"
            let maxVisualDepth: Float = 4.0  // Visual range is 4.0 meters for consistency
            
            // Create rotated grid for proper orientation (matching the full depth view)
            // When we rotate 90° counterclockwise, width and height are swapped
            let rotatedWidth = height
            let rotatedHeight = width
            let rotatedCellWidth = rotatedWidth / gridWidth
            let rotatedCellHeight = rotatedHeight / gridHeight
            
            // Create clusters data structure (average depth and count for each cell)
            var clusterDepths = [[Float]](repeating: [Float](repeating: 0, count: gridWidth), count: gridHeight)
            var clusterCounts = [[Int]](repeating: [Int](repeating: 0, count: gridWidth), count: gridHeight)
            var beyondRangeClusters = [[Bool]](repeating: [Bool](repeating: false, count: gridWidth), count: gridHeight)
            
            // Lock the buffer
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                return nil
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // Sample pixels at a very sparse rate for performance
            let sampleStep = 16  // Sample every 16th pixel
            
            // Calculate average depth values for each cluster, with proper rotation
            for y in stride(from: 0, to: height, by: sampleStep) {
                for x in stride(from: 0, to: width, by: sampleStep) {
                    let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                    let depth = depthData[offset]
                    
                    // Skip invalid depth values but process ALL valid depth points
                    // (even those beyond visual range)
                    if depth.isNaN || depth <= 0 {
                        continue
                    }
                    
                    // Compute rotated coordinates (90° counterclockwise)
                    let rotatedX = height - 1 - y
                    let rotatedY = x
                    
                    // Determine which rotated cluster this pixel belongs to
                    let clusterX = rotatedX / rotatedCellWidth
                    let clusterY = rotatedY / rotatedCellHeight
                    
                    if clusterX < gridWidth && clusterY < gridHeight {
                        clusterDepths[clusterY][clusterX] += depth
                        clusterCounts[clusterY][clusterX] += 1
                        
                        // Mark if this cluster has points beyond our visual range
                        if depth > maxVisualDepth {
                            beyondRangeClusters[clusterY][clusterX] = true
                        }
                    }
                }
            }
            
            // Create an image context for visualization (using rotated dimensions)
            UIGraphicsBeginImageContext(CGSize(width: rotatedWidth, height: rotatedHeight))
            let context = UIGraphicsGetCurrentContext()!
            
            // Clear the background (transparent)
            context.clear(CGRect(x: 0, y: 0, width: rotatedWidth, height: rotatedHeight))
            
            // Draw the clusters
            for y in 0..<gridHeight {
                for x in 0..<gridWidth {
                    if clusterCounts[y][x] > 0 {
                        // Calculate average depth for this cluster
                        let avgDepth = clusterDepths[y][x] / Float(clusterCounts[y][x])
                        
                        // Determine color based on distance
                        var color: UIColor
                        
                        // Special blue-purple color for points beyond our visual range
                        if beyondRangeClusters[y][x] {
                            // Use a distinctive blue-purple color for points beyond visual range
                            color = UIColor(red: 0.3, green: 0.3, blue: 1.0, alpha: 0.7)  // Bright blue for beyond range
                        } else if avgDepth < nearThreshold {
                            color = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.6)  // Red for near
                        } else if avgDepth < midThreshold {
                            color = UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 0.6)  // Yellow for mid
                        } else {
                            color = UIColor(red: 0.1, green: 0.8, blue: 0.1, alpha: 0.5)  // Green for far
                        }
                        
                        // Draw a simple circle for each cluster
                        let circleSize = CGFloat(min(rotatedCellWidth, rotatedCellHeight)) * 0.7
                        let circleRect = CGRect(
                            x: CGFloat(x * rotatedCellWidth) + CGFloat(rotatedCellWidth - Int(circleSize)) / 2,
                            y: CGFloat(y * rotatedCellHeight) + CGFloat(rotatedCellHeight - Int(circleSize)) / 2,
                            width: circleSize,
                            height: circleSize
                        )
                        
                        context.setFillColor(color.cgColor)
                        context.fillEllipse(in: circleRect)
                    }
                }
            }
            
            // Get the image from context
            let resultImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return resultImage
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
