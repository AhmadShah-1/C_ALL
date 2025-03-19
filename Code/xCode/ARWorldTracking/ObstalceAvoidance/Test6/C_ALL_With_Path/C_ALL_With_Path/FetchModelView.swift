//
//  FetchModelView.swift
//  CreatingLidarModel
//
//  Created by SSW - Design Team on 11/17/24.
//

import SwiftUI
import SceneKit

/// A class to track the file currently being displayed in the app.
class CurrentlyDisplaying: ObservableObject {
    @Published var fileName = "" // Publishes changes to `fileName` so the SwiftUI view updates accordingly.
}

/// A SwiftUI view to fetch, display, and manage 3D models saved as `.obj` files.
struct FetchModelView: View {
    // Observes which file is currently displayed.
    @StateObject private var currentlyDisplaying = CurrentlyDisplaying()
    
    // Holds a list of file names available for display.
    @State private var fileNames: [String] = []
    
    // Tracks whether the full-screen model viewer is currently presented.
    @State private var fullScreen = false
    
    /// The body of the view, containing the UI layout and functionality.
    var body: some View {
        VStack {
            // Displays the list of available files.
            List(self.fileNames, id: \.self) { fileName in
                // Button to select a file for viewing.
                Button(action: {
                    self.currentlyDisplaying.fileName = fileName // Set the selected file.
                    self.fullScreen.toggle()                     // Present the full-screen view.
                }) {
                    HStack {
                        Text(fileName)             // Display the file name.
                        Spacer()                   // Add space between the text and the image.
                        Image(systemName: "eye.fill") // Icon indicating a view action.
                    }
                }
                // Add swipe actions for file deletion.
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: {
                        removeFile(fileName: fileName) // Delete the selected file.
                        withAnimation {
                            fetchFiles() // Refresh the file list after deletion.
                        }
                    }) {
                        Label("Delete", systemImage: "trash") // Label for the delete action.
                    }
                }
            }
            // Allows refreshing the file list by pulling down.
            .refreshable {
                fetchFiles() // Re-fetch the file list.
            }
            // Presents a full-screen view when `fullScreen` is true.
            .fullScreenCover(isPresented: $fullScreen) {
                ZStack(alignment: Alignment(horizontal: .leading, vertical: .top)) {
                    // Displays the selected 3D model if a file is selected.
                    if !self.currentlyDisplaying.fileName.isEmpty {
                        SceneViewWrapper(scene: displayFile(fileName: currentlyDisplaying.fileName))
                    }
                    // Adds a "Back" button to exit the full-screen view.
                    Button(action: {
                        self.fullScreen = false
                    }) {
                        Text("Back").padding()
                    }
                }
            }
        }
        // Fetch the list of files when the view appears.
        .onAppear {
            fetchFiles()
        }
    }
    
    /// Fetches a list of `.obj` files from the app's document directory.
    func fetchFiles() {
        // Get the URL for the app's document directory.
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        // Subdirectory containing the `.obj` files.
        let folderName = "OBJ_FILES"
        let folderURL = documentsDirectory.appendingPathComponent(folderName)
        
        do {
            // Get a list of all files in the folder.
            let fileURLs = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            // Filter files to include only those with the `.obj` extension.
            let filteredURLs = fileURLs.filter { (url) -> Bool in
                return url.pathExtension == "obj"
            }
            // Extract the file names from the URLs and update `fileNames`.
            self.fileNames = filteredURLs.map { $0.lastPathComponent }
        } catch {
            print("Error fetching files: \(error)") // Handle errors during file fetching.
        }
    }
    
    /// Loads and returns a 3D scene from the specified file.
    /// - Parameter fileName: The name of the `.obj` file to load.
    /// - Returns: An `SCNScene` representing the 3D model, or an empty scene if loading fails.
    func displayFile(fileName: String) -> SCNScene {
        // Get the URL for the app's document directory.
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Failed to access documents directory.")
        }
        
        // Construct the full path to the file.
        let folderName = "OBJ_FILES"
        let folderURL = directory.appendingPathComponent(folderName)
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        // Attempt to load the 3D scene from the file.
        let sceneView = try? SCNScene(url: fileURL)
        // Return the loaded scene, or an empty scene if loading failed.
        return sceneView ?? SCNScene()
    }
    
    /// Deletes the specified file from the app's document directory.
    /// - Parameter fileName: The name of the file to delete.
    func removeFile(fileName: String) {
        // Get the URL for the app's document directory.
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Failed to access documents directory.")
        }
        
        // Construct the full path to the file.
        let folderName = "OBJ_FILES"
        let folderURL = directory.appendingPathComponent(folderName)
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        do {
            // Attempt to delete the file.
            try FileManager.default.removeItem(at: fileURL)
            print("File removed successfully: \(fileURL)")
        } catch {
            print("Error removing file: \(error)") // Handle errors during file deletion.
        }
    }
}

/// A preview for `FetchModelView`, useful during development.
struct FetchModelView_Previews: PreviewProvider {
    static var previews: some View {
        FetchModelView()
    }
}

/// A wrapper to integrate `SCNScene` with SwiftUI using `UIViewRepresentable`.
struct SceneViewWrapper: UIViewRepresentable {
    let scene: SCNScene? // The 3D scene to display.

    /// Creates and configures the `SCNView` for displaying the 3D scene.
    func makeUIView(context: Context) -> some UIView {
        let scnView = SCNView()                  // Create an instance of `SCNView`.
        scnView.allowsCameraControl = true      // Enable camera control for user interaction.
        scnView.autoenablesDefaultLighting = true // Automatically add default lighting to the scene.
        scnView.antialiasingMode = .multisampling4X // Enable anti-aliasing for better visuals.
        
        // Add an ambient light to the scene.
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .ambient         // Use ambient light for uniform illumination.
        lightNode.light?.color = UIColor.white  // Set the light color to white.
        scene?.rootNode.addChildNode(lightNode) // Add the light to the scene.
        
        scnView.scene = scene                   // Set the provided scene to the `SCNView`.
        scnView.backgroundColor = .clear        // Set the background color to transparent.
        return scnView                          // Return the configured `SCNView`.
    }

    /// Updates the `SCNView` when the SwiftUI view is redrawn. (Currently unused.)
    func updateUIView(_ uiView: UIViewType, context: Context) { }
}
