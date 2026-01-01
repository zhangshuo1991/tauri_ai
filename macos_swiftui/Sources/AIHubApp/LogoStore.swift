import AppKit
import Foundation

@MainActor
final class LogoStore {
    static let shared = LogoStore()

    private let storage = Storage.shared

    func storeLogo(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let maxBytes = 512 * 1024
        if data.count > maxBytes {
            throw AppError(message: "Image too large (max 512KB)")
        }
        if url.pathExtension.lowercased() == "svg" {
            throw AppError(message: "SVG is not supported. Please upload PNG/JPG/WebP/GIF.")
        }
        let encodedData: Data
        if url.pathExtension.lowercased() == "png" {
            encodedData = data
        } else {
            guard let image = NSImage(data: data) else {
                throw AppError(message: "Failed to read image")
            }
            guard let encoded = pngData(from: image) else {
                throw AppError(message: "Failed to encode image")
            }
            encodedData = encoded
        }

        storage.ensureBaseDirectory()
        let key = UUID().uuidString
        let target = storage.logoURL(for: key)
        try encodedData.write(to: target, options: .atomic)
        return "logo:\(key)"
    }

    func image(for iconKey: String, siteId: String? = nil) -> NSImage? {
        guard let key = resolveLogoKey(iconKey: iconKey, siteId: siteId) else {
            return nil
        }
        let url = storage.logoURL(for: key)
        return NSImage(contentsOf: url)
    }

    private func resolveLogoKey(iconKey: String, siteId: String?) -> String? {
        if iconKey.hasPrefix("logo:") {
            let key = String(iconKey.dropFirst("logo:".count))
            return storage.logoExists(for: key) ? key : nil
        }
        if storage.logoExists(for: iconKey) {
            return iconKey
        }
        if let siteId, storage.logoExists(for: siteId) {
            return siteId
        }
        return nil
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
