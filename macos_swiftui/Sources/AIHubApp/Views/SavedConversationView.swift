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
        return parseMarkdown(markdown)
    }

    private static func parseMarkdown(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLang = "" // Reserved for future syntax highlighting

        let baseFont = NSFont.systemFont(ofSize: 13)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let baseParagraphStyle = NSMutableParagraphStyle()
        baseParagraphStyle.lineSpacing = 4

        for (lineIndex, line) in lines.enumerated() {
            // Code block handling
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    let codeAttr = NSMutableAttributedString(
                        string: codeBlockContent,
                        attributes: [
                            .font: codeFont,
                            .foregroundColor: NSColor.labelColor,
                            .backgroundColor: NSColor.quaternaryLabelColor
                        ]
                    )
                    result.append(codeAttr)
                    result.append(NSAttributedString(string: "\n"))
                    codeBlockContent = ""
                    codeBlockLang = ""
                    inCodeBlock = false
                } else {
                    // Start code block
                    inCodeBlock = true
                    codeBlockLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty {
                    codeBlockContent += "\n"
                }
                codeBlockContent += line
                continue
            }

            // Process non-code-block lines
            let lineAttr = parseLine(line, baseFont: baseFont, codeFont: codeFont, paragraphStyle: baseParagraphStyle)
            result.append(lineAttr)

            // Add newline between lines (except for the last line)
            if lineIndex < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        // Handle unclosed code block
        if inCodeBlock && !codeBlockContent.isEmpty {
            let codeAttr = NSMutableAttributedString(
                string: codeBlockContent,
                attributes: [
                    .font: codeFont,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ]
            )
            result.append(codeAttr)
        }

        return result
    }

    private static func parseLine(_ line: String, baseFont: NSFont, codeFont: NSFont, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        // Headings
        if let headingMatch = line.range(of: "^#{1,6}\\s+", options: .regularExpression) {
            let level = line[headingMatch].filter { $0 == "#" }.count
            let content = String(line[headingMatch.upperBound...])
            let fontSize: CGFloat = [24, 20, 18, 16, 14, 13][min(level - 1, 5)]
            let headingFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let headingParagraph = NSMutableParagraphStyle()
            headingParagraph.paragraphSpacingBefore = 8
            headingParagraph.paragraphSpacing = 4
            return parseInlineElements(content, baseFont: headingFont, codeFont: codeFont, paragraphStyle: headingParagraph)
        }

        // Horizontal rule
        if line.trimmingCharacters(in: .whitespaces).range(of: "^-{3,}$|^\\*{3,}$|^_{3,}$", options: .regularExpression) != nil {
            let hrAttr = NSMutableAttributedString(string: "─────────────────────────────────────────\n")
            hrAttr.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: NSRange(location: 0, length: hrAttr.length))
            return hrAttr
        }

        // Blockquote
        if line.hasPrefix(">") {
            let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            let quoteAttr = parseInlineElements(content, baseFont: baseFont, codeFont: codeFont, paragraphStyle: paragraphStyle)
            let mutable = NSMutableAttributedString(string: "│ ", attributes: [
                .foregroundColor: NSColor.systemGray,
                .font: baseFont
            ])
            mutable.append(quoteAttr)
            mutable.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 2, length: mutable.length - 2))
            return mutable
        }

        // Unordered list
        if let listMatch = line.range(of: "^(\\s*)[-*+]\\s+", options: .regularExpression) {
            let indent = line[listMatch].filter { $0 == " " || $0 == "\t" }.count
            let content = String(line[listMatch.upperBound...])
            let bullet = String(repeating: "  ", count: indent / 2) + "• "
            let bulletAttr = NSMutableAttributedString(string: bullet, attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            bulletAttr.append(parseInlineElements(content, baseFont: baseFont, codeFont: codeFont, paragraphStyle: paragraphStyle))
            return bulletAttr
        }

        // Ordered list
        if let listMatch = line.range(of: "^(\\s*)\\d+\\.\\s+", options: .regularExpression) {
            let indent = line[listMatch].filter { $0 == " " || $0 == "\t" }.count
            let content = String(line[listMatch.upperBound...])
            let numberMatch = line[listMatch].filter { $0.isNumber }
            let prefix = String(repeating: "  ", count: indent / 2) + numberMatch + ". "
            let prefixAttr = NSMutableAttributedString(string: prefix, attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            prefixAttr.append(parseInlineElements(content, baseFont: baseFont, codeFont: codeFont, paragraphStyle: paragraphStyle))
            return prefixAttr
        }

        // Table row
        if line.hasPrefix("|") && line.hasSuffix("|") {
            let trimmed = line.dropFirst().dropLast()
            // Check if it's a separator row
            if trimmed.range(of: "^[\\s|:-]+$", options: .regularExpression) != nil {
                return NSAttributedString(string: "")
            }
            let cells = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let tableAttr = NSMutableAttributedString()
            for (index, cell) in cells.enumerated() {
                if index > 0 {
                    tableAttr.append(NSAttributedString(string: " │ ", attributes: [
                        .foregroundColor: NSColor.separatorColor,
                        .font: baseFont
                    ]))
                }
                tableAttr.append(parseInlineElements(cell, baseFont: baseFont, codeFont: codeFont, paragraphStyle: paragraphStyle))
            }
            return tableAttr
        }

        // Regular paragraph
        return parseInlineElements(line, baseFont: baseFont, codeFont: codeFont, paragraphStyle: paragraphStyle)
    }

    private static func parseInlineElements(_ text: String, baseFont: NSFont, codeFont: NSFont, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var currentIndex = text.startIndex

        // Regex patterns for inline elements
        let patterns: [(pattern: String, handler: (String, [String]) -> NSAttributedString)] = [
            // Image: ![alt](url)
            ("!\\[([^\\]]*)\\]\\(([^)]+)\\)", { _, groups in
                let alt = groups.count > 0 ? groups[0] : ""
                return NSAttributedString(string: "[Image: \(alt)]", attributes: [
                    .foregroundColor: NSColor.systemBlue,
                    .font: baseFont
                ])
            }),
            // Link: [text](url)
            ("\\[([^\\]]+)\\]\\(([^)]+)\\)", { _, groups in
                let linkText = groups.count > 0 ? groups[0] : ""
                let url = groups.count > 1 ? groups[1] : ""
                let attr = NSMutableAttributedString(string: linkText, attributes: [
                    .foregroundColor: NSColor.linkColor,
                    .font: baseFont,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ])
                if let linkURL = URL(string: url) {
                    attr.addAttribute(.link, value: linkURL, range: NSRange(location: 0, length: attr.length))
                }
                return attr
            }),
            // Bold + Italic: ***text*** or ___text___
            ("\\*{3}([^*]+)\\*{3}|_{3}([^_]+)_{3}", { _, groups in
                let content = groups.first { !$0.isEmpty } ?? ""
                return NSAttributedString(string: content, attributes: [
                    .font: NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits([.bold, .italic]), size: baseFont.pointSize) ?? baseFont,
                    .foregroundColor: NSColor.labelColor
                ])
            }),
            // Bold: **text** or __text__
            ("\\*{2}([^*]+)\\*{2}|_{2}([^_]+)_{2}", { _, groups in
                let content = groups.first { !$0.isEmpty } ?? ""
                return NSAttributedString(string: content, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: baseFont.pointSize),
                    .foregroundColor: NSColor.labelColor
                ])
            }),
            // Italic: *text* or _text_
            ("(?<![*_])\\*([^*]+)\\*(?![*_])|(?<![*_])_([^_]+)_(?![*_])", { _, groups in
                let content = groups.first { !$0.isEmpty } ?? ""
                return NSAttributedString(string: content, attributes: [
                    .font: NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic), size: baseFont.pointSize) ?? baseFont,
                    .foregroundColor: NSColor.labelColor
                ])
            }),
            // Strikethrough: ~~text~~
            ("~~([^~]+)~~", { _, groups in
                let content = groups.count > 0 ? groups[0] : ""
                return NSAttributedString(string: content, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ])
            }),
            // Highlight: ==text==
            ("==([^=]+)==", { _, groups in
                let content = groups.count > 0 ? groups[0] : ""
                return NSAttributedString(string: content, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.3)
                ])
            }),
            // Inline code: `text`
            ("`([^`]+)`", { _, groups in
                let content = groups.count > 0 ? groups[0] : ""
                return NSAttributedString(string: content, attributes: [
                    .font: codeFont,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ])
            })
        ]

        while currentIndex < text.endIndex {
            var foundMatch = false
            let remainingText = String(text[currentIndex...])

            for (pattern, handler) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                      let match = regex.firstMatch(in: remainingText, options: [], range: NSRange(remainingText.startIndex..., in: remainingText)),
                      match.range.location == 0 else {
                    continue
                }

                // Extract capture groups
                var groups: [String] = []
                for i in 1..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: remainingText) {
                        groups.append(String(remainingText[range]))
                    } else {
                        groups.append("")
                    }
                }

                let fullMatch = String(remainingText[Range(match.range, in: remainingText)!])
                result.append(handler(fullMatch, groups))

                currentIndex = text.index(currentIndex, offsetBy: fullMatch.count)
                foundMatch = true
                break
            }

            if !foundMatch {
                result.append(NSAttributedString(string: String(text[currentIndex]), attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor
                ]))
                currentIndex = text.index(after: currentIndex)
            }
        }

        if result.length > 0 {
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        }

        return result
    }
}
