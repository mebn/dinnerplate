import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = PlateScanner()

    var body: some View {
        CameraPreview(session: scanner.session)
            .ignoresSafeArea()
            .background(.black)
            .statusBarHidden(true)
            .task {
                await scanner.start()
            }
            .onDisappear {
                scanner.stop()
            }
            .sheet(item: $scanner.detectedPlate) { plate in
                PlateSheet(plate: plate.value)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(18)
            }
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
}
