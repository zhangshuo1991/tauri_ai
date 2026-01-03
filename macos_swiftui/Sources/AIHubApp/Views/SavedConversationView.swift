import AppKit
import SwiftUI

struct SavedConversationView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var isPresented: Bool
    let conversation: SavedConversation

    @State private var alertItem: AlertItem?

    private let labelWidth: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("saved.title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                infoRow(title: model.t("saved.site"), value: Text(conversation.siteName))
                infoRow(title: model.t("saved.url"), value: urlView)
                infoRow(title: model.t("saved.savedAt"), value: Text(savedAtText))
            }

            SelectableTextView(text: conversation.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button(model.t("common.close")) { isPresented = false }
                Button(model.t("common.copyToClipboard")) { copyToClipboard() }
                    .disabled(conversation.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 860, height: 520)
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.message))
        }
    }

    private var urlView: Text {
        if conversation.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Text("-")
                .foregroundStyle(.secondary)
        }
        return Text(conversation.url)
    }

    private var savedAtText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(conversation.createdAt))
        return Self.dateFormatter.string(from: date)
    }

    private func infoRow(title: String, value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            value
                .font(.system(size: 12))
                .lineLimit(1)
        }
    }

    private func copyToClipboard() {
        let trimmed = conversation.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let body = "\(model.t("saved.site")): \(conversation.siteName)\n\(model.t("saved.url")): \(conversation.url)\n\(model.t("saved.savedAt")): \(savedAtText)\n\n\(trimmed)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(body, forType: .string) {
            alertItem = AlertItem(message: model.t("saved.copySuccess"))
        } else {
            alertItem = AlertItem(message: model.t("saved.copyFail"))
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let contentWidth = max(0, nsView.contentSize.width)
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.frame.size.width = contentWidth
        if textView.string != text {
            textView.string = text
        }
    }
}
