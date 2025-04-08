import Foundation
import RealityKit
import ARKit
import CoreLocation
import simd

class ObstacleAvoidanceController {
    
    // Root entity for obstacle‑avoidance geometry.
    var rootEntity = AnchorEntity()
    
    // Adjustable path dimensions.
    var pathWidth: Float = 0.3
    var pathLength: Float = 1.0
    
    // The reference route.
    var mainRouteCoordinates: [CLLocationCoordinate2D] = []
    
    // ModelEntity for dynamic path visualization.
    private var pathEntity = ModelEntity()
    
    // Cache of ARMeshAnchors.
    private var meshAnchors: [ARMeshAnchor] = []
    
    init() {
        rootEntity.addChild(pathEntity)
    }
    
    /// Call this each frame to update obstacle avoidance.
    func updateObstacleAvoidance(with frame: ARFrame, routeCoords: [CLLocationCoordinate2D], userLocation: CLLocationCoordinate2D?) {
        guard let userLocation = userLocation else { return }
        mainRouteCoordinates = routeCoords
        meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        let cameraTransform = frame.camera.transform
        let forwardVector = -simd_normalize(SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        ))
        let isUserOffRoute = isUserFarFromRoute(userLocation: userLocation, route: routeCoords)
        let obstacleDetected = isObstacleInFront(cameraTransform: cameraTransform, forwardVector: forwardVector)
        let newMesh = generatePathMesh(isArcing: isUserOffRoute, obstacleDetected: obstacleDetected)
        pathEntity.model = ModelComponent(
            mesh: newMesh,
            materials: [SimpleMaterial(color: obstacleDetected ? .red : .blue, roughness: 0.1, isMetallic: false)]
        )
        let cameraPos = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        pathEntity.position = cameraPos
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
    
    // MARK: - Obstacle detection.
    private func isObstacleInFront(cameraTransform: simd_float4x4, forwardVector: SIMD3<Float>) -> Bool {
        var obstacleFound = false
        for anchor in meshAnchors {
            let meshGeometry = anchor.geometry
            let vertexCount = meshGeometry.vertices.count
            let anchorTransform = anchor.transform
            for i in 0..<vertexCount {
                let localVertex = meshGeometry.vertex(at: UInt32(i))
                var vertexPos = SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1)
                vertexPos = anchorTransform * vertexPos
                let cameraPos = cameraTransform.columns.3.xyz
                let relativePos = vertexPos.xyz - cameraPos
                let forwardDist = simd_dot(relativePos, forwardVector)
                if forwardDist < 0 || forwardDist > pathLength { continue }
                let crossWithForward = simd_length(simd_cross(relativePos, forwardVector))
                if crossWithForward > (pathWidth / 2) { continue }
                if vertexPos.y < (cameraTransform.columns.3.y - 0.1) { continue }
                obstacleFound = true
                break
            }
            if obstacleFound { break }
        }
        return obstacleFound
    }
    
    // MARK: - Path geometry generation.
    private func generatePathMesh(isArcing: Bool, obstacleDetected: Bool) -> MeshResource {
        if !isArcing && !obstacleDetected {
            return .generateBox(width: pathWidth, height: 0.02, depth: pathLength)
        } else {
            return .generateCylinder(height: pathLength, radius: pathWidth / 2)
        }
    }
}
