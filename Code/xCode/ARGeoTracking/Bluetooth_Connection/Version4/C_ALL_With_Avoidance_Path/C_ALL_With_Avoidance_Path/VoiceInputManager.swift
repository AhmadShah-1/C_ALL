import Foundation
import Speech
import SwiftUI
import CoreLocation

class VoiceInputManager: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var errorMessage: String?
    @Published var permissionGranted = false
    
    override init() {
        super.init()
        requestPermissions()
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.permissionGranted = true
                case .denied, .restricted, .notDetermined:
                    self?.permissionGranted = false
                    self?.errorMessage = "Speech recognition permission not granted"
                @unknown default:
                    self?.permissionGranted = false
                }
            }
        }
    }
    
    func startListening(completion: @escaping (String) -> Void) {
        // Reset variables
        recognizedText = ""
        errorMessage = nil
        
        // Check authorization status
        if !permissionGranted {
            errorMessage = "Speech recognition permission not granted"
            return
        }
        
        // Check if already listening
        if audioEngine.isRunning {
            stopListening()
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create speech recognition request"
            return
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to set up audio session: \(error.localizedDescription)"
            return
        }
        
        // Configure recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Recognition error: \(error.localizedDescription)"
                self.stopListening()
                return
            }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.recognizedText = text
                
                // If the speech has ended, process the result
                if result.isFinal {
                    completion(text)
                    self.stopListening()
                }
            }
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            return
        }
    }
    
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            isListening = false
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func processRecognizedLocation(_ text: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(text) { placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    self.errorMessage = "Could not find location for: \(text)"
                    completion(nil)
                    return
                }
                
                if let location = placemarks?.first?.location {
                    // Store the recognized address for donation to Siri
                    UserDefaults.standard.set(text, forKey: "LastVoiceRecognizedDestination")
                    
                    // Return the coordinate
                    completion(location.coordinate)
                } else {
                    self.errorMessage = "No location found for: \(text)"
                    completion(nil)
                }
            }
        }
    }
} 