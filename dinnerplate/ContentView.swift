import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [ScannerSettings]
    @State private var selectedTab: AppTab = .camera

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera.viewfinder")
                }
                .tag(AppTab.camera)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "photo.on.rectangle")
                }
                .tag(AppTab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .task {
            guard settings.isEmpty else {
                return
            }

            modelContext.insert(ScannerSettings())
        }
    }
}

private enum AppTab {
    case camera
    case history
    case settings
}

private struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [ScannerSettings]
    @StateObject private var scanner = PlateScanner()

    var body: some View {
        CameraPreview(session: scanner.session)
            .ignoresSafeArea()
            .background(.black)
            .statusBarHidden(true)
            .task {
                scanner.setPhotoCaptureEnabled(takePictures)
                await scanner.start()
            }
            .onDisappear {
                scanner.stop()
            }
            .onChange(of: takePictures) { _, isEnabled in
                scanner.setPhotoCaptureEnabled(isEnabled)
            }
            .onChange(of: scanner.detectedPlate) { _, plate in
                saveCaptureIfNeeded(plate)
            }
            .sheet(item: $scanner.detectedPlate) { plate in
                PlateSheet(plate: plate.value)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(18)
            }
    }

    private var takePictures: Bool {
        settings.first?.takePictures ?? true
    }

    private func saveCaptureIfNeeded(_ plate: RecognizedPlate?) {
        guard takePictures, let plate, let imageData = plate.imageData else {
            return
        }

        modelContext.insert(
            PlateCapture(
                plateNumber: plate.value,
                imageData: imageData,
                capturedAt: Date()
            )
        )
    }
}

private struct HistoryView: View {
    @Query(sort: \PlateCapture.capturedAt, order: .reverse) private var captures: [PlateCapture]
    @State private var selectedCapture: PlateCapture?

    private let columns = [
        GridItem(.adaptive(minimum: 132), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(captures) { capture in
                        Button {
                            selectedCapture = capture
                        } label: {
                            CaptureThumbnail(capture: capture)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .navigationTitle("History")
            .sheet(item: $selectedCapture) { capture in
                PlateSheet(plate: capture.plateNumber)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(18)
            }
        }
    }
}

private struct CaptureThumbnail: View {
    let capture: PlateCapture

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(data: capture.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
            }

            Text(capture.plateNumber)
                .font(.caption.weight(.semibold))
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(8)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [ScannerSettings]

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Take pictures", isOn: takePicturesBinding)
            }
            .navigationTitle("Settings")
        }
    }

    private var takePicturesBinding: Binding<Bool> {
        Binding {
            settings.first?.takePictures ?? true
        } set: { newValue in
            let settings = settings.first ?? createSettings()
            settings.takePictures = newValue
        }
    }

    private func createSettings() -> ScannerSettings {
        let settings = ScannerSettings()
        modelContext.insert(settings)
        return settings
    }
}

private struct PlateSheet: View {
    let plate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plate")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(plate)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityLabel("Registration plate \(plate)")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PlateCapture.self, ScannerSettings.self], inMemory: true)
}
