//
//  ARWrapper.swift
//  CreatingLidarModel
//
//  Created by SSW - Design Team  on 11/14/24.
//

import SwiftUI
import RealityKit
import ARKit

struct ARWrapper: UIViewRepresentable{
    @Binding var submittedExportRequest: Bool
    @Binding var exportedURL: URL?
    
    let arView = ARView(frame: .zero)
    func makeUIView(context: Context) -> ARView{
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context){
        let vm = ExportViewModel()
        
        setARViewOptions(arView)
        let configuration = buildConfigure()
        arView.session.run(configuration)
        
        if submittedExportRequest{
            guard let camera = arView.session.currentFrame?.camera else { return }
            if let meshAnchors = arView.session.currentFrame?.anchors.compactMap( {$0 as? ARMeshAnchor} ),
               let asset = vm.convertToAssest(meshAnchor: meshAnchors, camera: camera){
                do{
                    //try  saving to local directory
                    let url = try vm.export(asset: asset)
                    exportedURL = url
                }catch{
                    print("Export Failure")
                }
            }
        }
        
    }
    
    private func buildConfigure() -> ARWorldTrackingConfiguration{
        let configuration = ARWorldTrackingConfiguration()
        
        configuration.environmentTexturing = .automatic
        // This guesses the approximate shapes of objects, you can also select a raw reading insterad
        configuration.sceneReconstruction = .meshWithClassification
        
        arView.automaticallyConfigureSession = false
        
        // Read basic surroudnigns and using lidar to create deapth map
        if type(of: configuration).supportsFrameSemantics(.sceneDepth){
            configuration.frameSemantics = .sceneDepth
        }
        
        return configuration
    }
    
    private func setARViewOptions(_ arView: ARView){
        arView.debugOptions.insert(.showSceneUnderstanding)
    }
    
    
}

class ExportViewModel: NSObject, ObservableObject, ARSessionDelegate{
    
    func convertToAssest(meshAnchor: [ARMeshAnchor], camera: ARCamera) -> MDLAsset? {
        guard let device = MTLCreateSystemDefaultDevice() else {return nil}
        
        let asset = MDLAsset()
        
        for anchor in meshAnchor{
            let mdlMesh = anchor.geometry.toMDLMesh(device: device, camera: camera, modelMatrix: anchor.transform)
        }
        return asset
    }
    
    // File manager saves info on the clients device
    func export(asset: MDLAsset) throws -> URL{
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "com.original.CreatingLidarModel", code: 153)
        }
        
        // The augmented files will be saved to this folder
        let folderName = "OBJ_Files"
        let folderURL = directory.appendingPathComponent(folderName)
        
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        
        // Create unique file name using uuid to create unique ones
        let url = folderURL.appendingPathComponent("\(UUID().uuidString).obj")
        
        do{
            try asset.export(to: url)
            print("Object saved successfully at ", url)
            return url
        }catch{
            print(error)
            }
        return url
    }
}
