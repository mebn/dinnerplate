import Foundation
import SwiftData

@Model
final class PlateCapture: Identifiable {
    @Attribute(.unique) var id: UUID
    var plateNumber: String
    @Attribute(.externalStorage) var imageData: Data
    var capturedAt: Date

    init(
        id: UUID = UUID(),
        plateNumber: String,
        imageData: Data,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.plateNumber = plateNumber
        self.imageData = imageData
        self.capturedAt = capturedAt
    }
}

@Model
final class ScannerSettings {
    @Attribute(.unique) var id: String = "scanner-settings"
    var takePictures: Bool = true
    var pauseCameraOnSheet: Bool = false

    init(
        id: String = "scanner-settings",
        takePictures: Bool = true,
        pauseCameraOnSheet: Bool = false
    ) {
        self.id = id
        self.takePictures = takePictures
        self.pauseCameraOnSheet = pauseCameraOnSheet
    }
}
