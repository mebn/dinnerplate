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
    @Attribute(.unique) var id: String
    var takePictures: Bool

    init(id: String = "scanner-settings", takePictures: Bool = true) {
        self.id = id
        self.takePictures = takePictures
    }
}
