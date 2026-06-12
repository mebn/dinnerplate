import AVFoundation
import Foundation
import Vision

struct RecognizedPlate: Identifiable, Equatable {
    let id = UUID()
    let value: String
}

final class PlateScanner: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var detectedPlate: RecognizedPlate?

    private let cameraQueue = DispatchQueue(label: "dinnerplate.camera")
    private let visionQueue = DispatchQueue(label: "dinnerplate.vision")

    private var isConfigured = false
    private var isProcessingFrame = false
    private var lastScanDate = Date.distantPast
    private var lastPresentedValue: String?
    private var lastPresentedDate = Date.distantPast

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                startSession()
            }
        default:
            break
        }
    }

    func stop() {
        cameraQueue.async { [session] in
            guard session.isRunning else {
                return
            }

            session.stopRunning()
        }
    }

    private func startSession() {
        cameraQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.configureIfNeeded() else {
                return
            }

            guard !self.session.isRunning else {
                return
            }

            self.session.startRunning()
        }
    }

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else {
            return true
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        defer {
            session.commitConfiguration()
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return false
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: visionQueue)

        guard session.canAddOutput(output) else {
            return false
        }

        session.addOutput(output)

        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        isConfigured = true
        return true
    }
}

extension PlateScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastScanDate) >= 0.35, !isProcessingFrame else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        lastScanDate = now
        isProcessingFrame = true

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            defer {
                self?.isProcessingFrame = false
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            let textCandidates = observations.flatMap { observation in
                observation.topCandidates(3).map(\.string)
            }

            guard let plate = PlateParser.extractPlate(from: textCandidates) else {
                return
            }

            self?.present(plate)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.025

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)

        do {
            try handler.perform([request])
        } catch {
            isProcessingFrame = false
        }
    }

    private func present(_ plate: String) {
        let now = Date()
        guard plate != lastPresentedValue || now.timeIntervalSince(lastPresentedDate) > 8 else {
            return
        }

        lastPresentedValue = plate
        lastPresentedDate = now

        DispatchQueue.main.async { [weak self] in
            self?.detectedPlate = RecognizedPlate(value: plate)
        }
    }
}
