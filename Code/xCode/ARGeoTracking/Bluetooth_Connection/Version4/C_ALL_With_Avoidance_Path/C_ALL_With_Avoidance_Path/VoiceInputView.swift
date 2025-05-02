import SwiftUI
import CoreLocation

struct VoiceInputView: View {
    @ObservedObject var voiceManager: VoiceInputManager
    @Binding var isPresented: Bool
    var onLocationSelected: (CLLocationCoordinate2D) -> Void
    
    @State private var showingPermissionAlert = false
    @State private var processingLocation = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Voice Destination Input")
                .font(.title)
                .fontWeight(.bold)
            
            if voiceManager.isListening {
                Text("Listening...")
                    .font(.title2)
                    .foregroundColor(.blue)
            } else if processingLocation {
                Text("Processing location...")
                    .font(.title2)
                    .foregroundColor(.orange)
            } else if !voiceManager.recognizedText.isEmpty {
                Text(voiceManager.recognizedText)
                    .font(.title3)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            } else {
                Text("Tap the microphone and say your destination")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            // Microphone button
            Button(action: {
                if !voiceManager.permissionGranted {
                    showingPermissionAlert = true
                    return
                }
                
                if !voiceManager.isListening {
                    voiceManager.startListening { recognizedText in
                        processingLocation = true
                        voiceManager.processRecognizedLocation(recognizedText) { coordinate in
                            processingLocation = false
                            if let coordinate = coordinate {
                                // Donate to Siri
                                if let address = UserDefaults.standard.string(forKey: "LastVoiceRecognizedDestination") {
                                    C_ALL_With_Avoidance_PathApp.donateNavigationIntent(to: coordinate, with: address)
                                }
                                
                                // Pass to parent
                                onLocationSelected(coordinate)
                                
                                // Store for app launch
                                UserDefaults.standard.set(true, forKey: "HasSiriDestination")
                                UserDefaults.standard.set(coordinate.latitude, forKey: "SiriRequestedLatitude")
                                UserDefaults.standard.set(coordinate.longitude, forKey: "SiriRequestedLongitude")
                                
                                // Dismiss the view
                                isPresented = false
                            }
                        }
                    }
                } else {
                    voiceManager.stopListening()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(voiceManager.isListening ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: voiceManager.isListening ? "stop.fill" : "mic.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                }
            }
            .padding()
            
            if let error = voiceManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            Button("Cancel") {
                voiceManager.stopListening()
                isPresented = false
            }
            .padding()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text("Please enable speech recognition permission in Settings to use voice input."),
                primaryButton: .default(Text("Open Settings"), action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }),
                secondaryButton: .cancel()
            )
        }
    }
} 