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
        CameraPreview(session: scanner.session) { scale in
            scanner.zoom(by: scale)
        }
            .ignoresSafeArea()
            .background(.black)
            .task {
                ensureSettings()
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
                handleDetectedPlate(plate)
            }
            .onChange(of: scanner.completedCapture) { _, capture in
                handleCompletedCapture(capture)
            }
            .sheet(item: $scanner.detectedPlate, onDismiss: resumeCameraIfNeeded) { plate in
                PlateSheet(plate: plate.value)
                    .plateSheetPresentation()
            }
    }

    private var takePictures: Bool {
        settings.first?.takePictures ?? true
    }

    private var pauseCameraOnSheet: Bool {
        settings.first?.pauseCameraOnSheet ?? false
    }

    private func handleDetectedPlate(_ plate: RecognizedPlate?) {
        guard pauseCameraOnSheet, plate != nil, !takePictures else {
            return
        }

        scanner.stop()
    }

    private func handleCompletedCapture(_ capture: CapturedPlatePhoto?) {
        saveCaptureIfNeeded(capture)

        guard pauseCameraOnSheet, capture != nil else {
            return
        }

        scanner.stop()
    }

    private func saveCaptureIfNeeded(_ capture: CapturedPlatePhoto?) {
        guard takePictures, let capture, let imageData = capture.imageData else {
            return
        }

        modelContext.insert(
            PlateCapture(
                plateNumber: capture.value,
                imageData: imageData,
                capturedAt: Date()
            )
        )
        try? modelContext.save()
    }

    private func resumeCameraIfNeeded() {
        guard pauseCameraOnSheet else {
            return
        }

        Task {
            await scanner.start()
        }
    }

    private func ensureSettings() {
        guard settings.isEmpty else {
            return
        }

        modelContext.insert(ScannerSettings())
        try? modelContext.save()
    }
}

private struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlateCapture.capturedAt, order: .reverse) private var captures: [PlateCapture]
    @State private var selectedCapture: PlateCapture?
    @State private var capturePendingDeletion: PlateCapture?

    private let columns = [
        GridItem(.adaptive(minimum: 132), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(captures) { capture in
                        CaptureGridItem(
                            capture: capture,
                            select: {
                                selectedCapture = capture
                            },
                            delete: {
                                capturePendingDeletion = capture
                            }
                        )
                    }
                }
                .padding(12)
            }
            .navigationTitle("History")
            .sheet(item: $selectedCapture) { capture in
                PlateSheet(plate: capture.plateNumber)
                    .plateSheetPresentation()
            }
            .alert("Delete this picture?", isPresented: isConfirmingDelete) {
                Button("Cancel", role: .cancel) {
                    capturePendingDeletion = nil
                }

                Button("Delete", role: .destructive) {
                    if let capture = capturePendingDeletion {
                        modelContext.delete(capture)
                        try? modelContext.save()
                    }

                    capturePendingDeletion = nil
                }
            } message: {
                Text(capturePendingDeletion?.plateNumber ?? "")
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding {
            capturePendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                capturePendingDeletion = nil
            }
        }
    }
}

private struct CaptureGridItem: View {
    let capture: PlateCapture
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                CaptureThumbnail(capture: capture)
            }
            .buttonStyle(.plain)

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(7)
            .accessibilityLabel("Delete picture")
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
                if let settings = settings.first {
                    SettingsForm(settings: settings)
                }
            }
            .navigationTitle("Settings")
            .task {
                ensureSettings()
            }
        }
    }

    private func ensureSettings() {
        guard settings.isEmpty else {
            return
        }

        modelContext.insert(ScannerSettings())
        try? modelContext.save()
    }
}

private struct SettingsForm: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: ScannerSettings

    var body: some View {
        Toggle("Take pictures", isOn: $settings.takePictures)
            .onChange(of: settings.takePictures) { _, _ in
                try? modelContext.save()
            }

        Toggle("Pause camera while sheet is open", isOn: $settings.pauseCameraOnSheet)
            .onChange(of: settings.pauseCameraOnSheet) { _, _ in
                try? modelContext.save()
            }
    }
}

private struct PlateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plate: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                SwedishPlateView(plate: plate)

                Link("More info", destination: moreInfoURL)
                    .font(.headline)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .navigationTitle("Plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var moreInfoURL: URL {
        URL(string: "https://biluppgifter.se/fordon/\(plate.replacingOccurrences(of: " ", with: ""))")!
    }
}

private struct SwedishPlateView: View {
    let plate: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("S")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 50)
            .frame(maxHeight: .infinity)
            .background(Color(red: 0.0, green: 0.22, blue: 0.64))

            Text(plate)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospaced()
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
        }
        .frame(height: 88)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.black.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Registration plate \(plate)")
    }
}

private extension View {
    func plateSheetPresentation() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(18)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PlateCapture.self, ScannerSettings.self], inMemory: true)
}
