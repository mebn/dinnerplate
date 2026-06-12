import AVFoundation
import Foundation
import Vision

struct RecognizedPlate: Identifiable, Equatable {
    let id = UUID()
    let value: String
}

struct CapturedPlatePhoto: Identifiable, Equatable {
    let id = UUID()
    let value: String
    let imageData: Data?
}

final class PlateScanner: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var detectedPlate: RecognizedPlate?
    @Published var completedCapture: CapturedPlatePhoto?

    private let cameraQueue = DispatchQueue(label: "dinnerplate.camera")
    private let visionQueue = DispatchQueue(label: "dinnerplate.vision")
    private let photoOutput = AVCapturePhotoOutput()

    private var videoDevice: AVCaptureDevice?
    private var isConfigured = false
    private var isProcessingFrame = false
    private var isPhotoCaptureEnabled = true
    private var lastScanDate = Date.distantPast
    private var lastPresentedValue: String?
    private var lastPresentedDate = Date.distantPast
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]

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

    func setPhotoCaptureEnabled(_ isEnabled: Bool) {
        cameraQueue.async { [weak self] in
            self?.isPhotoCaptureEnabled = isEnabled
        }
    }

    func zoom(by scale: CGFloat) {
        cameraQueue.async { [weak self] in
            guard let device = self?.videoDevice else {
                return
            }

            do {
                try device.lockForConfiguration()
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8)
                let nextZoom = min(max(device.videoZoomFactor * scale, 1), maxZoom)
                device.videoZoomFactor = nextZoom
                device.unlockForConfiguration()
            } catch {
                return
            }
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
        videoDevice = device

        guard session.canAddOutput(photoOutput) else {
            return false
        }

        session.addOutput(photoOutput)

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

            self?.handleRecognizedPlate(plate)
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

    private func handleRecognizedPlate(_ plate: String) {
        let now = Date()
        guard plate != lastPresentedValue || now.timeIntervalSince(lastPresentedDate) > 8 else {
            return
        }

        lastPresentedValue = plate
        lastPresentedDate = now
        present(plate)

        cameraQueue.async { [weak self] in
            guard let self, self.isPhotoCaptureEnabled else {
                return
            }

            self.capturePhoto(for: plate)
        }
    }

    private func capturePhoto(for plate: String) {
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoCaptureDelegate { [weak self] imageData in
            guard let self else {
                return
            }

            self.publishCompletedCapture(plate, imageData: imageData)
            self.cameraQueue.async {
                self.photoDelegates[settings.uniqueID] = nil
            }
        }

        photoDelegates[settings.uniqueID] = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func present(_ plate: String) {
        DispatchQueue.main.async { [weak self] in
            self?.detectedPlate = RecognizedPlate(value: plate)
        }
    }

    private func publishCompletedCapture(_ plate: String, imageData: Data?) {
        DispatchQueue.main.async { [weak self] in
            self?.completedCapture = CapturedPlatePhoto(value: plate, imageData: imageData)
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}
