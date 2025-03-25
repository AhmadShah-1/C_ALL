import SwiftUI
import RealityKit
import ARKit
import Combine

class ARWrapper: NSObject, ObservableObject {
    // AR View
    var arView: ARView
    
    // Published properties
    @Published var depthImage: UIImage?
    
    // Configuration
    var showDepthOverlay: Bool = true {
        didSet {
            // If turning off, immediately clear the image to save resources
            if !showDepthOverlay {
                DispatchQueue.main.async {
                    self.depthImage = nil
                }
            }
        }
    }
    
    // Configurable depth visualization parameters
    var maxDepthDistance: Float = 5.0  // Maximum depth in meters
    var detailLevel: DetailLevel = .medium // Default to medium to reduce CPU usage
    
    // Navigation manager for core functionality 
    var navigationManager: GeoObstacleNavigationManager
    
    // Display link for updates
    private var displayLink: CADisplayLink?
    private var cancellables = Set<AnyCancellable>()
    
    // Tracking statistics and throttling
    private var frameCount: Int = 0
    private var framesSinceLastDepth: Int = 0
    private var lastDepthProcessingTime = Date()
    private var isProcessingDepth = false
    
    // Reusable image context for better performance
    private var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Detail level enum
    enum DetailLevel: Int, CaseIterable {
        case low = 16      // Process every 16th pixel
        case medium = 8    // Process every 8th pixel
        case high = 4      // Process every 4th pixel
        case ultra = 2     // Process every 2nd pixel
        
        var description: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .ultra: return "Ultra"
            }
        }
    }
    
    // MARK: - Initialization
    
    init(arView: ARView, navigationManager: GeoObstacleNavigationManager) {
        self.arView = arView
        self.navigationManager = navigationManager
        
        super.init()
        
        // Start AR session
        setupAndStartARSession()
        
        // Setup display link for updates
        setupDisplayLink()
    }
    
    // MARK: - AR Session Setup
    
    func setupAndStartARSession() {
        // Create configuration
        let config = ARWorldTrackingConfiguration()
        
        // Enable depth if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]  // Removed smoothedSceneDepth to reduce processing
        }
        
        // Enable scene reconstruction if available, but reduce quality
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .mesh  // Use simpler mesh without classification
        }
        
        // Start AR session
        arView.session.run(config)
        
        // Set AR view options for better performance
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableHDR,
                               .disablePersonOcclusion, .disableFaceMesh]
    }
    
    func resetARSession() {
        // Create new configuration
        let config = ARWorldTrackingConfiguration()
        
        // Enable depth if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]  // Removed smoothedSceneDepth
        }
        
        // Enable scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .mesh  // Use simpler mesh
        }
        
        // Run with reset options
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Update Loop
    
    func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.preferredFramesPerSecond = 10  // Reduced from 30 to 10 fps to save CPU
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc func update() {
        // Skip updates if app is in background
        guard UIApplication.shared.applicationState == .active else { return }
        
        // Process AR frame (needed for basic functionality)
        processCurrentFrame()
        
        // Only update depth visualization if needed and not too frequent
        if showDepthOverlay && !isProcessingDepth {
            let timeSinceLastProcess = Date().timeIntervalSince(lastDepthProcessingTime)
            if timeSinceLastProcess > 0.2 { // Only process depth 5 times per second max
                updateDepthVisualization()
                lastDepthProcessingTime = Date()
            }
        }
    }
    
    // MARK: - Frame Processing
    
    func processCurrentFrame() {
        guard let frame = arView.session.currentFrame else { return }
        
        // Send frame to navigation manager just to keep it running
        navigationManager.processFrame(frame)
        
        // Track frames with depth data
        if frame.sceneDepth != nil {
            framesSinceLastDepth = 0
        } else {
            framesSinceLastDepth += 1
        }
        
        frameCount += 1
    }
    
    // MARK: - Visualization Updates
    
    func updateDepthVisualization() {
        // Skip if depth visualization is disabled
        guard showDepthOverlay, !isProcessingDepth else { return }
        
        // Get depth data from current frame
        guard let frame = arView.session.currentFrame,
              let depthData = frame.sceneDepth,
              let confidenceMap = frame.sceneDepth?.confidenceMap else {
            return
        }
        
        // Set flag to prevent concurrent processing
        isProcessingDepth = true
        
        // Process depth data in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { 
                return 
            }
            
            if let visualizedDepth = self.visualizeDepthMap(depthData: depthData, confidenceData: confidenceMap) {
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.depthImage = visualizedDepth
                    self.isProcessingDepth = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isProcessingDepth = false
                }
            }
        }
    }
    
    // MARK: - Depth Visualization
    
    func visualizeDepthMap(depthData: ARDepthData, confidenceData: CVPixelBuffer) -> UIImage? {
        // Use autoreleasepool to manage memory better during image processing
        return autoreleasepool { () -> UIImage? in
            let depthMap = depthData.depthMap
            
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            
            // For performance, let's downscale the output buffer
            let scaleFactor: Int = 2
            let rotatedWidth = height / scaleFactor
            let rotatedHeight = width / scaleFactor
            
            // Create pixel buffer with smaller dimensions
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                           rotatedWidth, rotatedHeight,
                                           kCVPixelFormatType_32ARGB,
                                           attributes as CFDictionary,
                                           &pixelBuffer)
            
            guard status == kCVReturnSuccess, let visualBuffer = pixelBuffer else {
                return nil
            }
            
            // Lock buffers for reading/writing
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            CVPixelBufferLockBaseAddress(confidenceData, .readOnly)
            CVPixelBufferLockBaseAddress(visualBuffer, CVPixelBufferLockFlags(rawValue: 0))
            
            defer {
                CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
                CVPixelBufferUnlockBaseAddress(confidenceData, .readOnly)
                CVPixelBufferUnlockBaseAddress(visualBuffer, CVPixelBufferLockFlags(rawValue: 0))
            }
            
            // Get base addresses for all buffers
            guard let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap),
                  let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceData),
                  let visualBaseAddress = CVPixelBufferGetBaseAddress(visualBuffer) else {
                return nil
            }
            
            // Setup pointers for easy access
            let depthDataPtr = depthBaseAddress.assumingMemoryBound(to: Float32.self)
            let confidenceDataPtr = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)
            let visualDataPtr = visualBaseAddress.assumingMemoryBound(to: UInt32.self)
            
            // Calculate bytes per row for each buffer
            let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceData)
            let visualBytesPerRow = CVPixelBufferGetBytesPerRow(visualBuffer)
            
            // Calculate items per row (accounting for different types)
            let depthItemsPerRow = depthBytesPerRow / MemoryLayout<Float32>.size
            let visualItemsPerRow = visualBytesPerRow / MemoryLayout<UInt32>.size
            
            // Get stride value from detail level, increased for performance
            let pixelStride = detailLevel.rawValue * scaleFactor
            
            // Initialize the visual buffer with a dark transparent color
            // Use memset instead of nested loops for better performance
            memset(visualBaseAddress, 0x44, rotatedHeight * visualBytesPerRow)
            
            // Precompute colors for better performance
            let colorLookup = precomputeDepthColors()
            
            // Process depth map with 90-degree clockwise rotation
            for y in stride(from: 0, to: height, by: pixelStride) {
                guard y < height else { continue }
                
                for x in stride(from: 0, to: width, by: pixelStride) {
                    guard x < width else { continue }
                    
                    // Get depth and confidence values
                    let depthOffset = y * depthItemsPerRow + x
                    let confidenceOffset = y * confidenceBytesPerRow + x
                    
                    guard depthOffset < height * depthItemsPerRow,
                          confidenceOffset < height * confidenceBytesPerRow else {
                        continue
                    }
                    
                    let depth = depthDataPtr[depthOffset]
                    let confidence = confidenceDataPtr[confidenceOffset]
                    
                    // Skip invalid values
                    if depth.isNaN || depth <= 0 || confidence < 2 {
                        continue
                    }
                    
                    // Calculate rotated coordinates for 90 degrees clockwise
                    let rotatedX = (height - 1 - y) / scaleFactor
                    let rotatedY = x / scaleFactor
                    
                    // Safety check
                    guard rotatedX >= 0, rotatedX < rotatedWidth,
                          rotatedY >= 0, rotatedY < rotatedHeight else {
                        continue
                    }
                    
                    let visualOffset = rotatedY * visualItemsPerRow + rotatedX
                    guard visualOffset < rotatedHeight * visualItemsPerRow else {
                        continue
                    }
                    
                    // Look up color from precomputed array
                    let colorIndex = min(Int(depth * 10), colorLookup.count - 1)
                    let argb = colorLookup[colorIndex]
                    
                    // Set pixel color
                    visualDataPtr[visualOffset] = argb
                }
            }
            
            // Create UIImage from the visualization buffer
            let ciImage = CIImage(cvPixelBuffer: visualBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            
            return UIImage(cgImage: cgImage)
        }
    }
    
    // Precompute colors for different depth values to improve performance
    private func precomputeDepthColors() -> [UInt32] {
        let colorCount = 101 // 0.0 to 10.0 meters in 0.1m increments
        var colors = [UInt32](repeating: 0, count: colorCount)
        
        for i in 0..<colorCount {
            let depth = Float(i) / 10.0 // Convert to meters
            
            var red: UInt8 = 0
            var green: UInt8 = 0
            var blue: UInt8 = 0
            
            // Simplified color mapping for better performance
            if depth < 0.5 {
                // Very close (< 0.5m) - red
                red = 255
            } else if depth < 1.0 {
                // Close (0.5-1m) - yellow
                red = 255
                green = 255
            } else if depth < 2.0 {
                // Near (1-2m) - green
                green = 255
            } else {
                // Far (> 2m) - blue
                blue = 255
            }
            
            // Fixed opacity for better visibility
            let alpha: UInt8 = 230
            
            // ARGB format
            colors[i] = (UInt32(alpha) << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
        }
        
        return colors
    }
    
    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}
