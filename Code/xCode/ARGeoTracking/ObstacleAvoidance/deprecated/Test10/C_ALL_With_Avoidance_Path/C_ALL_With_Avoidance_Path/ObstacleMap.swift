import Foundation
import simd

// Define regions of the obstacle map - should be declared ONCE at file level
public enum ObstacleRegion {
    case front
    case middle
    case back
}

public struct ObstacleMap {
    // Grid dimensions
    private let width: Int
    private let height: Int
    private let cellSize: Float
    
    // Grid origin (center of the grid)
    private let originX: Float
    private let originZ: Float
    
    // Grid data (true = obstacle present)
    var grid: [[Bool]]
    
    public init(width: Int, height: Int, cellSize: Float) {
        self.width = width
        self.height = height
        self.cellSize = cellSize
        
        // Center the grid around the origin point
        self.originX = Float(width) * cellSize / 2.0
        self.originZ = Float(height) * cellSize / 2.0
        
        // Initialize empty grid
        self.grid = Array(repeating: Array(repeating: false, count: width), count: height)
    }
    
    // Add an obstacle at world position
    mutating public func addObstacle(at position: SIMD3<Float>) {
        // Convert world position to grid indices
        let gridX = Int((position.x + originX) / cellSize)
        let gridZ = Int((position.z + originZ) / cellSize)
        
        // Check if indices are within grid bounds
        guard gridX >= 0, gridX < width, gridZ >= 0, gridZ < height else {
            return
        }
        
        // Mark as obstacle
        grid[gridZ][gridX] = true
    }
    
    // Check if there are obstacles in a corridor from origin in a specific direction
    public func hasObstaclesInCorridor(from origin: SIMD3<Float>, direction: SIMD3<Float>, width: Float, length: Float) -> Bool {
        // Normalize direction vector
        let normalizedDirection = normalize(SIMD3<Float>(direction.x, 0, direction.z))
        
        // Calculate perpendicular vector (right vector)
        let perpendicular = SIMD3<Float>(normalizedDirection.z, 0, -normalizedDirection.x)
        
        // Check multiple points across the corridor width
        let checkPoints = 5 // Number of points to check across width
        let widthStep = width / Float(checkPoints - 1)
        
        for i in 0..<checkPoints {
            // Calculate offset from center
            let offset = (Float(i) * widthStep) - (width / 2.0)
            
            // Starting point for this check line
            let startPoint = origin + (perpendicular * offset)
            
            // Check along the length of the corridor
            for dist in stride(from: 0.5, through: length, by: 0.5) {
                let checkPoint = startPoint + (normalizedDirection * dist)
                
                // Convert to grid coordinates
                let gridX = Int((checkPoint.x + originX) / cellSize)
                let gridZ = Int((checkPoint.z + originZ) / cellSize)
                
                // Check if within grid bounds
                if gridX >= 0, gridX < self.width, gridZ >= 0, gridZ < self.height {
                    // Check if obstacle exists at this point
                    if grid[gridZ][gridX] {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    // Count total obstacles for debugging
    public func countObstacles() -> Int {
        var count = 0
        for row in grid {
            for cell in row {
                if cell {
                    count += 1
                }
            }
        }
        return count
    }
    
    // Get region boundaries for a specific region of the map
    public func getRegionBoundaries(_ region: ObstacleRegion) -> (start: Int, end: Int) {
        switch region {
        case .front:
            return (0, height / 3)
        case .middle:
            return (height / 3, 2 * height / 3)
        case .back:
            return (2 * height / 3, height)
        }
    }
} 