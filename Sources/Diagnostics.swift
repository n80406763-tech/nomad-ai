import SwiftUI

struct DiagnosticMessage: Identifiable {
    let id = UUID()
    let title: String
    let details: String
}

@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published private(set) var latest: DiagnosticMessage?

    func report(title: String, details: String) {
        latest = DiagnosticMessage(title: title, details: details)
    }

    func clear() {
        latest = nil
    }
}

struct DiagnosticsBanner: View {
    @ObservedObject private var diagnostics = DiagnosticsStore.shared

    var body: some View {
        if let issue = diagnostics.latest {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(issue.title)
                        .font(.headline)
                    Spacer()
                    Button {
                        diagnostics.clear()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                Text(issue.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}