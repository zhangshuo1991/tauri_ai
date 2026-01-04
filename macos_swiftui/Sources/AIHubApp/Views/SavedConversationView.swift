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

            MarkdownTextView(markdown: displayMarkdown)
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
        let trimmed = displayMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var displayMarkdown: String {
        let markdown = conversation.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !markdown.isEmpty {
            return markdown
        }
        return conversation.content
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

private struct MarkdownTextView: NSViewRepresentable {
    let markdown: String

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
        textView.textStorage?.setAttributedString(MarkdownRenderer.render(markdown))

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
        let rendered = MarkdownRenderer.render(markdown)
        if textView.string != rendered.string {
            textView.textStorage?.setAttributedString(rendered)
        }
    }
}

private enum MarkdownRenderer {
    private static let markdownSoftLimit = 200_000

    static func render(_ markdown: String) -> NSAttributedString {
        if markdown.count > markdownSoftLimit {
            return NSAttributedString(string: markdown)
        }
        let parsed = parse(markdown)
        let baseFont = NSFont.systemFont(ofSize: 13)
        let attributed = NSMutableAttributedString(
            string: parsed.text,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ]
        )
        applyHighlights(parsed.highlights, to: attributed)
        applyCode(parsed.codeRanges, to: attributed)
        return attributed
    }

    private static func parse(_ markdown: String) -> ParsedMarkdown {
        var output = ""
        var highlights: [NSRange] = []
        var codeRanges: [NSRange] = []

        var index = markdown.startIndex
        var inCodeBlock = false
        var inInlineCode = false
        var inHighlight = false

        var codeBlockStart: Int?
        var inlineCodeStart: Int?
        var highlightStart: Int?

        func currentOffset() -> Int {
            output.utf16.count
        }

        while index < markdown.endIndex {
            if markdown[index...].hasPrefix("```") {
                if inCodeBlock {
                    if let start = codeBlockStart {
                        let length = currentOffset() - start
                        if length > 0 {
                            codeRanges.append(NSRange(location: start, length: length))
                        }
                    }
                    codeBlockStart = nil
                    inCodeBlock = false
                } else if !inInlineCode {
                    inCodeBlock = true
                    codeBlockStart = currentOffset()
                }
                index = markdown.index(index, offsetBy: 3)
                continue
            }

            if !inCodeBlock {
                if markdown[index...].hasPrefix("==") {
                    if inHighlight {
                        if let start = highlightStart {
                            let length = currentOffset() - start
                            if length > 0 {
                                highlights.append(NSRange(location: start, length: length))
                            }
                        }
                        highlightStart = nil
                        inHighlight = false
                    } else {
                        inHighlight = true
                        highlightStart = currentOffset()
                    }
                    index = markdown.index(index, offsetBy: 2)
                    continue
                }

                if markdown[index] == "`" {
                    if inInlineCode {
                        if let start = inlineCodeStart {
                            let length = currentOffset() - start
                            if length > 0 {
                                codeRanges.append(NSRange(location: start, length: length))
                            }
                        }
                        inlineCodeStart = nil
                        inInlineCode = false
                    } else {
                        inInlineCode = true
                        inlineCodeStart = currentOffset()
                    }
                    index = markdown.index(after: index)
                    continue
                }
            }

            output.append(markdown[index])
            index = markdown.index(after: index)
        }

        return ParsedMarkdown(text: output, highlights: highlights, codeRanges: codeRanges)
    }

    private static func applyHighlights(_ ranges: [NSRange], to attributed: NSMutableAttributedString) {
        for range in ranges where range.length > 0 && NSMaxRange(range) <= attributed.length {
            attributed.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25), range: range)
        }
    }

    private static func applyCode(_ ranges: [NSRange], to attributed: NSMutableAttributedString) {
        let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        for range in ranges where range.length > 0 && NSMaxRange(range) <= attributed.length {
            attributed.addAttribute(.font, value: codeFont, range: range)
            attributed.addAttribute(.backgroundColor, value: NSColor.textBackgroundColor.withAlphaComponent(0.6), range: range)
        }
    }
}

private struct ParsedMarkdown {
    let text: String
    let highlights: [NSRange]
    let codeRanges: [NSRange]
}
