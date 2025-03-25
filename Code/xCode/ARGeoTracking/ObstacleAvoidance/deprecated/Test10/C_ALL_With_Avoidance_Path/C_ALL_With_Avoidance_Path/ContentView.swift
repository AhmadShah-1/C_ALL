import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import Combine

struct ContentView: View {
    @ObservedObject var navigationManager = GeoObstacleNavigationManager()
    @State private var depthImage: UIImage?
    @State private var showDepthOverlay = true
    @State private var shouldResetARSession = false
    @State private var maxDepthDistance: Float = 5.0
    @State private var detailLevelIndex = 1 // Medium detail by default
    @State private var showControls = false
    @State private var useFullScreenDepth = false
    @State private var performanceMode = true // Default to performance mode ON
    
    // Detail level options
    private let detailLevels = ARWrapper.DetailLevel.allCases
    
    var body: some View {
        ZStack {
            // AR View container
            ARViewContainer(
                navigationManager: navigationManager, 
                depthImage: $depthImage,
                shouldResetARSession: $shouldResetARSession,
                maxDepthDistance: $maxDepthDistance,
                detailLevel: detailLevels[detailLevelIndex],
                performanceMode: performanceMode
            )
            .edgesIgnoringSafeArea(.all)
            
            // Depth map visualization overlay
            if showDepthOverlay, let image = depthImage {
                GeometryReader { geometry in
                    ZStack {
                        // Semi-transparent background for full-screen mode
                        if useFullScreenDepth {
                            Color.black.opacity(0.3)
                                .edgesIgnoringSafeArea(.all)
                        }
                        
                        // Depth image - either full screen or small preview
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: useFullScreenDepth ? geometry.size.width * 0.8 : geometry.size.width * 0.4, 
                                   height: useFullScreenDepth ? geometry.size.height * 0.8 : geometry.size.height * 0.3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                            .overlay(
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DEPTH VISUALIZATION")
                                        .font(.system(size: 12, weight: .bold))
                                    
                                    Text("RED = < 0.5m | YELLOW = 1m | GREEN = 2m | BLUE = FAR")
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(5),
                                alignment: .bottom
                            )
                            .position(
                                x: useFullScreenDepth ? geometry.size.width / 2 : geometry.size.width * 0.75, 
                                y: useFullScreenDepth ? geometry.size.height / 2 : geometry.size.height * 0.2
                            )
                    }
                }
            }
            
            // Control panel
            VStack {
                Spacer()
                
                if showControls {
                    // Control panel for adjusting settings
                    VStack(spacing: 10) {
                        Text("Depth Settings")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        // Performance mode toggle
                        Toggle("Performance Mode", isOn: $performanceMode)
                            .padding(.horizontal)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .onChange(of: performanceMode) { newValue in
                                // When enabling performance mode, auto-set safest options
                                if newValue {
                                    detailLevelIndex = min(1, detailLevelIndex) // Medium or lower
                                    useFullScreenDepth = false
                                }
                            }
                        
                        // View size toggle
                        Toggle("Full Screen Depth", isOn: $useFullScreenDepth)
                            .padding(.horizontal)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .disabled(performanceMode) // Disable in performance mode
                            .opacity(performanceMode ? 0.5 : 1.0)
                        
                        // Max depth distance slider
                        HStack {
                            Text("Max Distance:")
                                .font(.system(size: 14))
                            Slider(value: $maxDepthDistance, in: 2.0...10.0, step: 1.0)
                            Text("\(Int(maxDepthDistance))m")
                                .font(.system(size: 14))
                                .frame(width: 30, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        
                        // Detail level picker
                        HStack {
                            Text("Detail Level:")
                                .font(.system(size: 14))
                            Picker("", selection: $detailLevelIndex) {
                                ForEach(0..<detailLevels.count, id: \.self) { index in
                                    Text(detailLevels[index].description)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 200)
                            .disabled(performanceMode && detailLevelIndex > 1) // Restrict in performance mode
                            .onChange(of: detailLevelIndex) { newValue in
                                // When in performance mode, don't allow high/ultra
                                if performanceMode && newValue > 1 {
                                    detailLevelIndex = 1 // Force medium
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Memory usage warning if needed
                        if !performanceMode || useFullScreenDepth || detailLevelIndex > 1 {
                            Text("⚠️ Current settings may cause high CPU usage.")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                                .padding(.bottom, 4)
                        }
                    }
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
                
                // Bottom control buttons
                HStack(spacing: 15) {
                    // Depth toggle button
                    Button(action: {
                        showDepthOverlay.toggle()
                    }) {
                        HStack {
                            Image(systemName: showDepthOverlay ? "eye.fill" : "eye.slash.fill")
                            Text(showDepthOverlay ? "Hide Depth" : "Show Depth")
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 15)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                    }
                    
                    // Controls toggle button
                    Button(action: {
                        showControls.toggle()
                    }) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text(showControls ? "Hide Controls" : "Settings")
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 15)
                        .background(Color.purple)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                    }
                    
                    // Reset button
                    Button(action: {
                        shouldResetARSession = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reset")
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 15)
                        .background(Color.gray)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                    }
                }
                .padding(.bottom, 30)
            }
        }
    }
}

// ARViewContainer implemented outside ContentView
struct ARViewContainer: UIViewRepresentable {
    var navigationManager: GeoObstacleNavigationManager
    @Binding var depthImage: UIImage?
    @Binding var shouldResetARSession: Bool
    @Binding var maxDepthDistance: Float
    var detailLevel: ARWrapper.DetailLevel
    var performanceMode: Bool
    
    func makeUIView(context: Context) -> ARView {
        // Create AR view
        let arView = ARView(frame: .zero)
        
        // Create AR wrapper and store it in the coordinator
        let wrapper = ARWrapper(arView: arView, navigationManager: navigationManager)
        context.coordinator.arWrapper = wrapper
        
        // Set initial settings
        wrapper.maxDepthDistance = maxDepthDistance
        wrapper.detailLevel = detailLevel
        
        // Subscribe to depth image updates
        let binding = $depthImage
        wrapper.$depthImage.sink { newImage in
            binding.wrappedValue = newImage
        }.store(in: &context.coordinator.cancellables)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR wrapper configuration
        if let wrapper = context.coordinator.arWrapper {
            wrapper.showDepthOverlay = true
            
            // Update settings if they changed
            if wrapper.maxDepthDistance != maxDepthDistance {
                wrapper.maxDepthDistance = maxDepthDistance
            }
            
            if wrapper.detailLevel != detailLevel {
                wrapper.detailLevel = detailLevel
            }
            
            // Check if we need to reset the AR session
            if shouldResetARSession {
                wrapper.resetARSession()
                // Reset the flag after handling
                DispatchQueue.main.async {
                    shouldResetARSession = false
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var arWrapper: ARWrapper?
        var cancellables = Set<AnyCancellable>()
    }
}

#Preview {
    ContentView()
}



