# Info_on_Version


## Overview




Try this swift code ig:

import SwiftUI
import ARKit
import RealityKit
import CoreLocation

struct ARWrapper: UIViewRepresentable {
    @Binding var routeCoordinates: [CLLocationCoordinate2D]
    @Binding var userLocation: CLLocation?
    @Binding var isGeoLocalized: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        
        // Debug visualization
        arView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        
        // Start ARGeoTracking
        startGeoTracking(in: arView, coordinator: context.coordinator)
        
        // Set session delegate
        arView.session.delegate = context.coordinator
        
        // Add coaching overlay to prompt scanning
        if #available(iOS 15.0, *) {
            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.delegate = context.coordinator
            coachingOverlay.goal = .geoTracking
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            arView.addSubview(coachingOverlay)
            
            NSLayoutConstraint.activate([
                coachingOverlay.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
                coachingOverlay.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
                coachingOverlay.widthAnchor.constraint(equalTo: arView.widthAnchor),
                coachingOverlay.heightAnchor.constraint(equalTo: arView.heightAnchor)
            ])
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateRoute(routeCoordinates)
    }
    
    private func startGeoTracking(in arView: ARView, coordinator: Coordinator) {
        guard #available(iOS 14.0, *) else {
            print("[ARWrapper] iOS 14+ required for ARGeoTracking.")
            return
        }
        
        let config = ARGeoTrackingConfiguration()
        config.environmentTexturing = .automatic
        
        print("[ARWrapper] Checking ARGeoTracking availability.")
        ARGeoTrackingConfiguration.checkAvailability { available, error in
            if let error = error {
                print("[ARWrapper] ARGeoTracking check error => \(error.localizedDescription)")
                return
            }
            if available {
                print("[ARWrapper] ARGeoTracking is available. Running session...")
                arView.session.run(config)
                coordinator.isGeoTrackingActive = true
            } else {
                print("[ARWrapper] ARGeoTracking not available.")
            }
        }
    }
    
    class Coordinator: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
        let parent: ARWrapper
        weak var arView: ARView?
        var isGeoTrackingActive = false
        private var placedCoords: Set<String> = []
        private var obstacleAnchors: [ARAnchor] = []
        
        init(_ parent: ARWrapper) {
            self.parent = parent
        }
        
        func updateRoute(_ newCoordinates: [CLLocationCoordinate2D]) {
            guard isGeoTrackingActive, let session = arView?.session else {
                print("[ARWrapper.Coordinator] ARGeoTracking not active yet.")
                return
            }
            
            for coord in newCoordinates {
                let idString = "\(coord.latitude),\(coord.longitude)"
                if !placedCoords.contains(idString) {
                    let alt = parent.userLocation?.altitude ?? 11.0
                    let anchor = ARGeoAnchor(coordinate: coord, altitude: alt)
                    session.add(anchor: anchor)
                    placedCoords.insert(idString)
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let depthData = frame.capturedDepthData else { return }
            detectObstacles(from: depthData, frame: frame)
        }
        
        private func detectObstacles(from depthData: AVDepthData, frame: ARFrame) {
            let threshold: Float = 0.15 // 15 cm
            let width = CVPixelBufferGetWidth(depthData.depthDataMap)
            let height = CVPixelBufferGetHeight(depthData.depthDataMap)
            
            CVPixelBufferLockBaseAddress(depthData.depthDataMap, .readOnly)
            let pointer = CVPixelBufferGetBaseAddress(depthData.depthDataMap)!.assumingMemoryBound(to: Float32.self)
            
            for y in 0..<height {
                for x in 0..<width {
                    let distance = pointer[y * width + x]
                    if distance < threshold {
                        placeObstacle(at: x, y: y, frame: frame)
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(depthData.depthDataMap, .readOnly)
        }
        
        private func placeObstacle(at x: Int, y: Int, frame: ARFrame) {
            let anchor = ARAnchor(transform: frame.camera.transform)
            arView?.session.add(anchor: anchor)
            obstacleAnchors.append(anchor)
            
            let sphere = MeshResource.generateSphere(radius: 0.2)
            let material = SimpleMaterial(color: .red, roughness: 0.2, isMetallic: false)
            let model = ModelEntity(mesh: sphere, materials: [material])
            
            let anchorEntity = AnchorEntity(anchor: anchor)
            anchorEntity.addChild(model)
            arView?.scene.addAnchor(anchorEntity)
            
            updateSecondaryPath()
        }

        private func updateSecondaryPath() {
            guard let userLocation = parent.userLocation else { return }
            let obstaclePositions = obstacleAnchors.map { $0.transform.columns.3 }
            let newPath = calculateAlternativePath(from: userLocation, avoiding: obstaclePositions)
            updateARPath(with: newPath)
        }

        private func calculateAlternativePath(from userLocation: CLLocation, avoiding obstacles: [SIMD4<Float>]) -> [CLLocationCoordinate2D] {
            var alternativePath: [CLLocationCoordinate2D] = []
            let mainPath = parent.routeCoordinates
            
            guard let nearestMainPathPoint = mainPath.min(by: {
                distanceBetween($0, userLocation.coordinate) < distanceBetween($1, userLocation.coordinate)
            }) else { return alternativePath }
            
            let detourOffset: Double = 0.0001
            for coord in mainPath {
                let isObstacleBlocking = obstacles.contains {
                    distanceBetween(coord, CLLocationCoordinate2D(latitude: Double($0.y), longitude: Double($0.x))) < 1.0
                }
                if isObstacleBlocking {
                    let detourPoint = CLLocationCoordinate2D(latitude: coord.latitude + detourOffset, longitude: coord.longitude + detourOffset)
                    alternativePath.append(detourPoint)
                } else {
                    alternativePath.append(coord)
                }
            }
            return alternativePath
        }
        
        private func distanceBetween(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
            let loc1 = CLLocation(latitude: c1.latitude, longitude: c1.longitude)
            let loc2 = CLLocation(latitude: c2.latitude, longitude: c2.longitude)
            return loc1.distance(from: loc2)
        }

        private func updateARPath(with newPath: [CLLocationCoordinate2D]) {
            guard let session = arView?.session else { return }
            for anchor in obstacleAnchors { session.remove(anchor: anchor) }
            obstacleAnchors.removeAll()
            for coord in newPath {
                let anchor = ARGeoAnchor(coordinate: coord, altitude: parent.userLocation?.altitude ?? 11.0)
                session.add(anchor: anchor)
            }
        }

        func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
            switch geoTrackingStatus.state {
            case .localized:
                parent.isGeoLocalized = true
            default:
                parent.isGeoLocalized = false
            }
        }

        @available(iOS 15.0, *)
        func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {}

        @available(iOS 15.0, *)
        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {}

        @available(iOS 15.0, *)
        func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
            guard let view = arView else { return }
            view.session.pause()
            if let config = view.session.configuration {
                view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            }
        }
    }
}
