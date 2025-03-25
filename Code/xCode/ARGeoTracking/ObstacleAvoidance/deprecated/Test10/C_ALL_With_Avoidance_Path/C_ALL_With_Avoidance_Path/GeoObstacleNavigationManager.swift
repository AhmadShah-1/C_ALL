import Foundation
import CoreLocation
import ARKit
import RealityKit
import Combine
import SwiftUI

class GeoObstacleNavigationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    // MARK: - Properties
    
    // Location properties
    private var locationManager: CLLocationManager
    private var currentLocation: CLLocationCoordinate2D?
    private var currentHeading: CLLocationDirection?
    
    // Route and navigation properties
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var currentTargetIndex: Int = 0
    
    // Obstacle avoidance properties
    @Published var navigationAngle: Float = 0.0
    @Published var obstacleAvoidanceActive: Bool = false
    @Published var trackingState: TrackingState = .initializing
    
    // Published for UI visibility
    @Published public var obstaclesDetected: Bool = false
    
    // Navigation angles
    @Published var geoNavigationAngle: Float = 0.0
    // The pure obstacle avoidance direction (points toward blue/clear areas)
    @Published var safePathDirection: Float = 0.0
    // Flag to indicate if a safe path has been found (for UI)
    @Published var safePathAvailable: Bool = false
    
    // Avoidance direction
    private var avoidanceDirection: Float = 0.0
    
    // Constants
    private let obstacleDetectionDistance: Float = 20.0
    private let thresholdDistance: Double = 20.0  // meters
    private let sampleStride: Int = 16  // Renamed from 'stride' to avoid conflict
    
    // Obstacle detection
    @Published var leftObstacles: Int = 0
    @Published var rightObstacles: Int = 0
    private var leftObstacleDistances: [Float] = []
    private var rightObstacleDistances: [Float] = []
    
    // Obstacle detection parameters
    private var consecutiveFramesWithoutObstacles = 0
    public let maxObstacleDistance: Float = 15.0  // Maximum distance to check for obstacles (15 meters)
    public var obstacleThreshold: Float = 0.8
    private let maxAvoidanceAngle: Float = 0.8  // Maximum avoidance angle in radians (about 45 degrees)
    
    // AR Frame Processing
    var framesProcessed: Int = 0
    var lastFrameTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        setupLocationManager()
        
        // Start in a state ready for obstacle detection
        trackingState = .localized
        
        // Lower the obstacle threshold initially for better sensitivity
        obstacleThreshold = 3
        
        // Log startup state
        print("GeoObstacleNavigationManager: Initialized and ready for obstacle detection")
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        // Use async to prevent "Publishing changes from within view updates" error
        DispatchQueue.main.async { [weak self] in
            self?.locationManager.startUpdatingLocation()
            self?.locationManager.startUpdatingHeading()
        }
    }
    
    // MARK: - Route Management
    
    func setRoute(coordinates: [CLLocationCoordinate2D]) {
        routeCoordinates = coordinates
        currentTargetIndex = 0
        print("Route set with \(coordinates.count) coordinates")
    }
    
    // MARK: - AR Frame Processing
    
    func processFrame(_ frame: ARFrame) {
        // Update frame statistics
        framesProcessed += 1
        lastFrameTime = frame.timestamp
        
        // Process depth data if available
        if let depthData = frame.sceneDepth {
            if framesProcessed % 300 == 0 {
                print("DEBUG: Processing depth data (size: \(CVPixelBufferGetWidth(depthData.depthMap))x\(CVPixelBufferGetHeight(depthData.depthMap)))")
            }
        } else {
            if framesProcessed % 300 == 0 {
                print("WARNING: No depth data available in frame")
            }
        }
        
        // Update tracking state based on the AR camera tracking state
        updateTrackingState(frame.camera.trackingState)
    }
    
    private func updateTrackingState(_ arTrackingState: ARCamera.TrackingState) {
        // Update our tracking state based on AR tracking state
        let newState: TrackingState
        
        switch arTrackingState {
        case .normal:
            newState = .localized
        case .limited(let reason):
            if reason == .initializing {
                newState = .initializing
            } else {
                // Don't drop back to localizing for obstacle detection
                // Keep as localized so obstacle detection continues to work
                newState = .localized
            }
        case .notAvailable:
            // Even if tracking is not ideal, continue obstacle detection
            newState = .localized
        @unknown default:
            newState = .localized
        }
        
        // Only update if changed to avoid unnecessary UI updates
        if newState != trackingState {
            DispatchQueue.main.async { [weak self] in
                self?.trackingState = newState
            }
        }
    }
    
    // MARK: - Obstacle Detection
    
    // Track consecutive empty frames to detect potential issues
    private var consecutiveEmptyFrames = 0
    private var consecutiveFramesWithObstacles = 0
    private var totalObstaclesProcessed = 0
    
    func detectObstacles(in depthMap: CVPixelBuffer, camera: ARCamera) {
        // Track consecutive frames for better diagnostics
        if obstaclesDetected {
            consecutiveFramesWithObstacles += 1
            consecutiveFramesWithoutObstacles = 0
        } else {
            consecutiveFramesWithoutObstacles += 1
            consecutiveFramesWithObstacles = 0
        }
        
        // Only log every 100 frames to avoid console spam
        if framesProcessed % 100 == 0 {
            print("DEBUG: Obstacle detection status - Frames with obstacles: \(consecutiveFramesWithObstacles), Without: \(consecutiveFramesWithoutObstacles)")
        }
        
        // Get depth map dimensions
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Lock the buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        // Get depth data
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return
        }
        
        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        // Reset obstacle counts
        leftObstacles = 0
        rightObstacles = 0
        leftObstacleDistances = []
        rightObstacleDistances = []
        
        // Calculate the vertical range to focus on (approximately 1 meter off the ground)
        // This is a rough approximation - we'll focus on the middle third of the depth map
        let verticalStart = height / 3
        let verticalEnd = (height * 2) / 3
        
        // Process depth data with a more sensitive sampling step
        let samplingStep = 6 // Increased from 8 for better sensitivity
        
        // Track total points processed for diagnostics
        var totalPointsProcessed = 0
        var validPointsFound = 0
        
        // Process the focused vertical range
        for y in stride(from: verticalStart, to: verticalEnd, by: samplingStep) {
            for x in stride(from: 0, to: width, by: samplingStep) {
                let offset = (y * bytesPerRow / MemoryLayout<Float32>.size) + x
                let depth = depthData[offset]
                totalPointsProcessed += 1
                
                // Skip invalid depth values
                if depth.isNaN || depth <= 0.0 || depth > maxObstacleDistance {
                    continue
                }
                
                validPointsFound += 1
                
                // Calculate angle from center (in radians)
                let normalizedX = Float(x) / Float(width) * 2.0 - 1.0
                let angle = atan2(normalizedX, 1.0)
                
                // Consider points within a wider cone (60° instead of 45°)
                if abs(angle) <= .pi / 3 {
                    // Determine if point is on left or right side
                    if angle < 0 {
                        leftObstacles += 1
                        leftObstacleDistances.append(depth)
                    } else {
                        rightObstacles += 1
                        rightObstacleDistances.append(depth)
                    }
                }
            }
        }
        
        // Log diagnostics every 100 frames
        if framesProcessed % 100 == 0 {
            print("DEBUG: Depth processing - Total: \(totalPointsProcessed), Valid: \(validPointsFound)")
        }
        
        // Determine if obstacles are detected based on point count
        let prevObstaclesDetected = obstaclesDetected
        obstaclesDetected = (Float(leftObstacles) >= obstacleThreshold) || (Float(rightObstacles) >= obstacleThreshold)
        
        // If obstacles detected changed state, update the UI
        if prevObstaclesDetected != obstaclesDetected {
            if obstaclesDetected {
                print("OBSTACLE DETECTION: Obstacles detected! Left: \(leftObstacles), Right: \(rightObstacles)")
            } else {
                print("OBSTACLE DETECTION: No obstacles detected")
            }
        }
        
        // Calculate average distances for each side
        let leftAvgDistance = leftObstacleDistances.isEmpty ? Float.infinity : leftObstacleDistances.reduce(0, +) / Float(leftObstacleDistances.count)
        let rightAvgDistance = rightObstacleDistances.isEmpty ? Float.infinity : rightObstacleDistances.reduce(0, +) / Float(rightObstacleDistances.count)
        
        // Update safe path direction based on obstacles
        updateSafePathDirection(leftObstacles: leftObstacles, rightObstacles: rightObstacles, 
                             leftAvgDistance: leftAvgDistance, rightAvgDistance: rightAvgDistance)
        
        // Set obstacle avoidance active if obstacles are detected
        let prevObstacleAvoidanceActive = obstacleAvoidanceActive
        obstacleAvoidanceActive = obstaclesDetected
        
        // Update safePathAvailable status for UI
        safePathAvailable = obstaclesDetected
        
        // If obstacle avoidance state changed, log this
        if prevObstacleAvoidanceActive != obstacleAvoidanceActive {
            if obstacleAvoidanceActive {
                print("OBSTACLE AVOIDANCE: Activated")
            } else {
                print("OBSTACLE AVOIDANCE: Deactivated")
            }
        }
    }
    
    // New helper method to update safe path direction
    private func updateSafePathDirection(leftObstacles: Int, rightObstacles: Int, 
                                    leftAvgDistance: Float, rightAvgDistance: Float) {
        if Float(leftObstacles) < obstacleThreshold && Float(rightObstacles) >= obstacleThreshold {
            // Left is clear, go left
            safePathDirection = -maxAvoidanceAngle
        } else if Float(rightObstacles) < obstacleThreshold && Float(leftObstacles) >= obstacleThreshold {
            // Right is clear, go right
            safePathDirection = maxAvoidanceAngle
        } else if Float(leftObstacles) >= obstacleThreshold && Float(rightObstacles) >= obstacleThreshold {
            // Both sides have obstacles
            if leftAvgDistance > rightAvgDistance {
                // Left has farther obstacles, go left
                safePathDirection = -maxAvoidanceAngle
            } else {
                // Right has farther obstacles, go right
                safePathDirection = maxAvoidanceAngle
            }
        } else {
            // No significant obstacles detected
            safePathDirection = 0
        }
        
        // Set the combined navigation angle (for backward compatibility)
        navigationAngle = safePathDirection
    }
    
    // MARK: - Helper Methods
    
    private func calculateDistance(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Double {
        let sourceLocation = CLLocation(latitude: source.latitude, longitude: source.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return sourceLocation.distance(from: destinationLocation)
    }
    
    // MARK: - Types
    
    // Tracking state enum
    enum TrackingState: Equatable {
        case initializing
        case localizing
        case localized
        case error(String)
        
        static func == (lhs: TrackingState, rhs: TrackingState) -> Bool {
            switch (lhs, rhs) {
            case (.initializing, .initializing),
                 (.localizing, .localizing),
                 (.localized, .localized):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
}


