// ARViewController.swift

import UIKit
import AVFoundation
import Network

class ARViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var nwConnection: NWConnection?
    let videoOutput = AVCaptureVideoDataOutput()
    let videoQueue = DispatchQueue(label: "VideoQueue")
    var lastTimestamp: Double = 0  // Used to throttle frame rate

    var imageView: UIImageView!  // Added to display captured frames

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNetworkConnection()
        setupCameraCapture()
        setupImageView()  // Set up the image view
    }

    func setupNetworkConnection() {
        let host = NWEndpoint.Host("192.168.1.151") // Replace with your Mac's IP address
        let port = NWEndpoint.Port(integerLiteral: 12345)

        nwConnection = NWConnection(host: host, port: port, using: .tcp)

        nwConnection?.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                print("Connected to server")
                self?.sendTestMessage()
            case .failed(let error):
                print("Failed to connect: \(error)")
            case .waiting(let error):
                print("Connection waiting: \(error)")
            default:
                print("Connection state: \(newState)")
            }
        }
        nwConnection?.start(queue: .main)
    }

    func sendTestMessage() {
        let testMessage = "Hello, Server!".data(using: .utf8)
        sendData(testMessage)
    }

    func setupCameraCapture() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high // Adjusted for higher quality

        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("Failed to access camera")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            videoOutput.alwaysDiscardsLateVideoFrames = true  // Optional: Reduce latency
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }

            captureSession.startRunning()
        } catch {
            print("Error setting up camera input: \(error)")
        }
    }

    func setupImageView() {
        imageView = UIImageView(frame: view.bounds)
        imageView.contentMode = .scaleAspectFill
        view.addSubview(imageView)
    }

    func sendData(_ data: Data?) {
        guard let data = data else { return }

        // Implement a simple framing protocol by prefixing data with its length
        var length = UInt32(data.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        let packet = header + data

        nwConnection?.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send data: \(error)")
            } else {
                print("Data sent successfully. Packet size: \(packet.count) bytes.")
            }
        }))
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ARViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        // Throttle the frame rate to reduce bandwidth usage
        // Send one frame every 0.1 seconds (adjust as needed)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if timestamp - lastTimestamp < 0.1 {
            return
        }
        lastTimestamp = timestamp

        // Convert sampleBuffer to imageBuffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        print("Successfully obtained image buffer.")

        // Lock the base address
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        // Create CIImage
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        print("Created CIImage with extent: \(ciImage.extent).")

        // Create CGImage from CIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage.")
            return
        }
        print("Successfully created CGImage.")

        // Create UIImage from CGImage
        let uiImage = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .right)
        print("Successfully created UIImage.")

        // Display the image on the screen
        DispatchQueue.main.async {
            self.imageView.image = uiImage
        }

        // Convert UIImage to JPEG data
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            print("Failed to create JPEG data from UIImage.")
            return
        }
        print("Successfully created JPEG data. Size: \(jpegData.count) bytes.")

        // Send the JPEG data
        sendData(jpegData)
    }
}
