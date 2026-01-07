import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
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
