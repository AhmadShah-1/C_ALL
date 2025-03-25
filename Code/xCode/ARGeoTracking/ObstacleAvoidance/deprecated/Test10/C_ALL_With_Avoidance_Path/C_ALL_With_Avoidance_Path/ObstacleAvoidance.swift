import Foundation
import RealityKit
import ARKit
import CoreLocation
import simd
import Combine

class ObstacleAvoidanceController: ObservableObject {
    
    // Root entity for obstacle‑avoidance geometry.
    var rootEntity = AnchorEntity()
    
    // Adjustable path dimensions.
    var pathWidth: Float = 0.3
    var pathLength: Float = 1.0
    
    // The reference route.
    var mainRouteCoordinates: [CLLocationCoordinate2D] = []
    
    // Observable properties for UI integration
    @Published var bestPathDirection: Float = 0.0 // Angle in radians
    @Published var obstaclesDetected: Bool = false
    @Published var scanningProgress: Float = 0.0
    
    // ModelEntity for dynamic path visualization.
    private var pathEntity = ModelEntity()
    
    // Entities for obstacle visualization
    private var obstacleMeshes: [ModelEntity] = []
    private let maxObstacleMeshes = 50
    
    // Scan parameters
    private let scanAngleRange: Float = .pi * 0.8 // 144 degrees (±72°)
    private let scanSteps = 12 // Number of directions to scan
    
    // Direction scan results
    private var directionScores = [Float: Float]() // [angle: clearance score]
    
    // Cache of ARMeshAnchors.
    private var meshAnchors: [ARMeshAnchor] = []
    
    init() {
        rootEntity.addChild(pathEntity)
        setupObstacleMeshes()
    }
    
    private func setupObstacleMeshes() {
        // Clear any existing meshes
        obstacleMeshes.forEach { $0.removeFromParent() }
        obstacleMeshes.removeAll()
        
        // Create placeholder entities for obstacle visualization
        let material = SimpleMaterial(color: .red.withAlphaComponent(0.7), roughness: 0.5, isMetallic: false)
        
        for _ in 0..<maxObstacleMeshes {
            let mesh = MeshResource.generateSphere(radius: 0.05)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.isEnabled = false
            rootEntity.addChild(entity)
            obstacleMeshes.append(entity)
        }
    }
    
    /// Call this each frame to update obstacle avoidance.
    func updateObstacleAvoidance(with frame: ARFrame, routeCoords: [CLLocationCoordinate2D], userLocation: CLLocationCoordinate2D?) {
        // Store route coordinates if provided
        if !routeCoords.isEmpty {
            mainRouteCoordinates = routeCoords
        }
        
        // Extract mesh anchors from the frame
        meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        
        let cameraTransform = frame.camera.transform
        let forwardVector = -simd_normalize(SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        ))
        
        // Determine if user is off route (if we have location data)
        var isUserOffRoute = false
        if let location = userLocation, !mainRouteCoordinates.isEmpty {
            isUserOffRoute = isUserFarFromRoute(userLocation: location, route: mainRouteCoordinates)
        }
        
        // Scan for obstacles in multiple directions
        scanDirectionsForObstacles(cameraTransform: cameraTransform, forwardVector: forwardVector)
        
        // Update path visualization
        updatePathVisualization(isArcing: isUserOffRoute)
        
        // Update obstacle visualization
        updateObstacleVisualization(cameraTransform: cameraTransform)
    }
    
    // MARK: - Check distance from route.
    private func isUserFarFromRoute(userLocation: CLLocationCoordinate2D, route: [CLLocationCoordinate2D]) -> Bool {
        guard !route.isEmpty else { return false }
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        var minDistance = Double.greatestFiniteMagnitude
        for coord in route {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = userLoc.distance(from: loc)
            if dist < minDistance { minDistance = dist }
        }
        return (minDistance > 5.0)
    }
    
    // MARK: - Scan multiple directions for obstacles
    private func scanDirectionsForObstacles(cameraTransform: simd_float4x4, forwardVector: SIMD3<Float>) {
        // Reset scores
        directionScores.removeAll()
        
        // Calculate right vector (perpendicular to forward and up)
        let upVector = SIMD3<Float>(0, 1, 0)
        let rightVector = simd_normalize(simd_cross(forwardVector, upVector))
        
        var anyObstacleDetected = false
        
        // Scan in multiple directions within the angle range
        for i in 0..<scanSteps {
            // Calculate scan angle (-scanAngleRange/2 to +scanAngleRange/2)
            let scanAngle = -scanAngleRange/2 + scanAngleRange * Float(i) / Float(scanSteps-1)
            
            // Create rotation matrix around Y axis
            let rotation = simd_matrix4x4(simd_quatf(angle: scanAngle, axis: upVector))
            
            // Calculate direction vector by rotating the forward vector
            let directionVector = simd_normalize(SIMD3<Float>(
                (rotation * SIMD4<Float>(forwardVector.x, forwardVector.y, forwardVector.z, 0)).x,
                (rotation * SIMD4<Float>(forwardVector.x, forwardVector.y, forwardVector.z, 0)).y,
                (rotation * SIMD4<Float>(forwardVector.x, forwardVector.y, forwardVector.z, 0)).z
            ))
            
            // Check for obstacles in this direction
            let (hasObstacle, clearanceDistance) = checkObstaclesInDirection(
                cameraTransform: cameraTransform,
                directionVector: directionVector
            )
            
            // Store result
            directionScores[scanAngle] = hasObstacle ? clearanceDistance : pathLength
            
            if hasObstacle {
                anyObstacleDetected = true
            }
        }
        
        // Find best direction (maximum clearance)
        if anyObstacleDetected {
            let bestDirection = directionScores.max { a, b in a.value < b.value }
            bestPathDirection = bestDirection?.key ?? 0.0
        } else {
            bestPathDirection = 0.0 // Forward if no obstacles
        }
        
        // Update published properties
        obstaclesDetected = anyObstacleDetected
        scanningProgress = 1.0 // Completed scan
    }
    
    // MARK: - Check obstacles in a specific direction
    private func checkObstaclesInDirection(cameraTransform: simd_float4x4, directionVector: SIMD3<Float>) -> (hasObstacle: Bool, clearanceDistance: Float) {
        let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var minDistance = pathLength
        var obstacleFound = false
        
        for anchor in meshAnchors {
            let meshGeometry = anchor.geometry
            let vertexCount = meshGeometry.vertices.count
            let anchorTransform = anchor.transform
            
            // Only check a subset of vertices for performance
            let strideAmount = max(1, vertexCount / 100)
            for i in stride(from: 0, to: vertexCount, by: strideAmount) {
                let localVertex = meshGeometry.vertex(at: UInt32(i))
                var vertexPos = SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1)
                vertexPos = anchorTransform * vertexPos
                
                let relativePos = SIMD3<Float>(vertexPos.x, vertexPos.y, vertexPos.z) - cameraPos
                let distance = simd_length(relativePos)
                
                // Skip points that are too far
                if distance > pathLength { continue }
                
                // Project onto direction vector
                let projectedDist = simd_dot(relativePos, directionVector)
                if projectedDist < 0 { continue } // Behind us
                
                // Calculate perpendicular distance to the direction line
                let perpendicular = simd_length(relativePos - directionVector * projectedDist)
                
                // Check if within path width
                if perpendicular <= (pathWidth / 2) && 
                   // Check if not too low (ground)
                   vertexPos.y > (cameraTransform.columns.3.y - 0.2) &&
                   // Check if not too high (ceiling)
                   vertexPos.y < (cameraTransform.columns.3.y + 1.0) {
                    
                    obstacleFound = true
                    minDistance = min(minDistance, projectedDist)
                }
            }
        }
        
        return (obstacleFound, minDistance)
    }
    
    // MARK: - Update path visualization
    private func updatePathVisualization(isArcing: Bool) {
        let material = SimpleMaterial(
            color: obstaclesDetected ? .red.withAlphaComponent(0.7) : .blue.withAlphaComponent(0.7),
            roughness: 0.1,
            isMetallic: false
        )
        
        // Generate mesh based on current state
        let newMesh: MeshResource
        if !isArcing && !obstaclesDetected {
            // Straight path when no obstacles and on route
            newMesh = .generateBox(width: pathWidth, height: 0.02, depth: pathLength)
        } else if obstaclesDetected {
            // Show curved path in direction of best clearance
            newMesh = generateCurvedPathMesh(angle: bestPathDirection)
        } else {
            // Fallback to cylinder for off-route
            newMesh = .generateCylinder(height: pathLength, radius: pathWidth / 2)
        }
        
        // Update path entity
        pathEntity.model = ModelComponent(mesh: newMesh, materials: [material])
    }
    
    // MARK: - Generate curved path mesh
    private func generateCurvedPathMesh(angle: Float) -> MeshResource {
        // For simplicity, just use a cylinder rotated in the direction of clearance
        // In a more advanced implementation, this could generate a true curved path
        return .generateCylinder(height: pathLength, radius: pathWidth / 2)
    }
    
    // MARK: - Update obstacle visualization
    private func updateObstacleVisualization(cameraTransform: simd_float4x4) {
        // Disable all meshes initially
        obstacleMeshes.forEach { $0.isEnabled = false }
        
        guard obstaclesDetected else { return }
        
        let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var meshIndex = 0
        
        // Collect obstacle points to visualize
        for anchor in meshAnchors {
            let meshGeometry = anchor.geometry
            let vertexCount = meshGeometry.vertices.count
            let anchorTransform = anchor.transform
            
            // Only visualize a subset of vertices for performance
            let strideAmount = max(1, vertexCount / 20)
            for i in stride(from: 0, to: vertexCount, by: strideAmount) {
                guard meshIndex < maxObstacleMeshes else { break }
                
                let localVertex = meshGeometry.vertex(at: UInt32(i))
                var vertexPos = SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1)
                vertexPos = anchorTransform * vertexPos
                
                let relativePos = SIMD3<Float>(vertexPos.x, vertexPos.y, vertexPos.z) - cameraPos
                let distance = simd_length(relativePos)
                
                // Only visualize close obstacles
                if distance <= pathLength && 
                   // Not too low (ground)
                   vertexPos.y > (cameraTransform.columns.3.y - 0.2) &&
                   // Not too high (ceiling)
                   vertexPos.y < (cameraTransform.columns.3.y + 1.0) {
                    
                    let mesh = obstacleMeshes[meshIndex]
                    mesh.isEnabled = true
                    mesh.position = SIMD3<Float>(vertexPos.x, vertexPos.y, vertexPos.z)
                    
                    // Scale based on distance
                    let scale = 0.03 + 0.05 * (1.0 - distance / pathLength)
                    mesh.scale = SIMD3<Float>(scale, scale, scale)
                    
                    meshIndex += 1
                }
            }
            
            if meshIndex >= maxObstacleMeshes { break }
        }
    }
}
