import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IconPickerView: View {
    @Binding var icon: String

    @State private var errorMessage: String?
    @State private var hoveredOption: String?

    private let options: [IconOption] = [
        IconOption(key: "sf:chat.bubble.fill", label: "Chat", systemName: "chat.bubble.fill"),
        IconOption(key: "sf:globe", label: "Web", systemName: "globe"),
        IconOption(key: "sf:magnifyingglass", label: "Search", systemName: "magnifyingglass"),
        IconOption(key: "sf:bolt.fill", label: "Flash", systemName: "bolt.fill"),
        IconOption(key: "sf:terminal", label: "Terminal", systemName: "terminal"),
        IconOption(key: "sf:paintpalette", label: "Palette", systemName: "paintpalette"),
        IconOption(key: "sf:wand.and.stars", label: "Magic", systemName: "wand.and.stars"),
        IconOption(key: "sf:pencil", label: "Edit", systemName: "pencil"),
        IconOption(key: "sf:photo", label: "Image", systemName: "photo")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current Icon Preview and Upload
            HStack(spacing: 12) {
                SiteIconView(iconKey: icon)
                    .frame(width: 36, height: 36)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                Button {
                    uploadImage()
                } label: {
                    Label("Upload...", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Icon Grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(options) { option in
                    IconGridItem(
                        option: option,
                        isSelected: icon == option.key,
                        isHovered: hoveredOption == option.key,
                        onSelect: { icon = option.key },
                        onHover: { hovering in
                            hoveredOption = hovering ? option.key : nil
                        }
                    )
                }
            }
        }
        .alert(item: Binding(
            get: { errorMessage.map { AlertItem(message: $0) } },
            set: { _ in errorMessage = nil }
        )) { item in
            Alert(title: Text(item.message))
        }
    }

    private func uploadImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                icon = try LogoStore.shared.storeLogo(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}

// MARK: - Icon Option
struct IconOption: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let systemName: String
}

// MARK: - Icon Grid Item
private struct IconGridItem: View {
    let option: IconOption
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: option.systemName)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? .primary : .secondary))
                Text(option.label)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            onHover(hovering)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        if isHovered {
            return Color.primary.opacity(0.04)
        }
        return Color.primary.opacity(0.02)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.primary.opacity(0.2)
        }
        return Color.primary.opacity(0.08)
    }
}

struct SiteIconView: View {
    let iconKey: String
    var siteId: String? = nil
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let image = LogoStore.shared.image(for: iconKey, siteId: siteId) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if iconKey.hasPrefix("data:image/"), let image = ImageDataHelper.image(from: iconKey) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if iconKey.hasPrefix("sf:") {
                let symbol = iconKey.replacingOccurrences(of: "sf:", with: "")
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.15)
            } else {
                Image(systemName: builtinSymbol(for: iconKey))
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func builtinSymbol(for key: String) -> String {
        switch key {
        case "deepseek":
            return "sparkles"
        case "doubao":
            return "message.fill"
        case "openai":
            return "bubble.left.and.bubble.right.fill"
        case "qianwen":
            return "bolt.fill"
        case "custom":
            return "star"
        default:
            return "globe"
        }
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

enum ImageDataHelper {
    static func image(from dataURL: String) -> NSImage? {
        guard let range = dataURL.range(of: ",") else { return nil }
        let base64 = String(dataURL[range.upperBound...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
