import AppKit
import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var isPresented: Bool
    @Binding var summary: String

    @State private var alertItem: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("summary.title"))
                .font(.headline)

            TextEditor(text: $summary)
                .frame(height: 280)

            HStack {
                Spacer()
                Button(model.t("common.close")) { isPresented = false }
                Button(model.t("common.copyToClipboard")) { copyToClipboard() }
                    .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 820)
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.message))
        }
    }

    private func copyToClipboard() {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let text = "\(model.t("summary.copyPrefix"))\n\(trimmed)\n\n\(model.t("summary.nextQuestion"))"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            alertItem = AlertItem(message: model.t("summary.copySuccess"))
        } else {
            alertItem = AlertItem(message: model.t("summary.copyFail"))
        }
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
