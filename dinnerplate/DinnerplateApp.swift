import SwiftData
import SwiftUI

@main
struct DinnerplateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [PlateCapture.self, ScannerSettings.self])
    }
}
