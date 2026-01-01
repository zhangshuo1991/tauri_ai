import AppKit
import Foundation

@MainActor
final class Storage {
    static let shared = Storage()

    private let fileManager = FileManager.default

    private var baseURL: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("ai-hub", isDirectory: true)
    }

    private var configURL: URL {
        baseURL.appendingPathComponent("config.json")
    }

    private var contextsURL: URL {
        baseURL.appendingPathComponent("contexts.json")
    }

    private var logosURL: URL {
        baseURL.appendingPathComponent("logos", isDirectory: true)
    }

    func ensureBaseDirectory() {
        if !fileManager.fileExists(atPath: baseURL.path) {
            try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: logosURL.path) {
            try? fileManager.createDirectory(at: logosURL, withIntermediateDirectories: true)
        }
        seedBuiltinLogosIfNeeded()
    }

    func loadConfig() -> AppConfig {
        ensureBaseDirectory()
        guard fileManager.fileExists(atPath: configURL.path) else {
            var config = defaultConfig()
            if let bundled = loadBundledSiteConfig() {
                config = mergeBundledSites(bundled, into: config)
            }
            saveConfig(config)
            return config
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            return decoded
        } catch {
            let config = defaultConfig()
            saveConfig(config)
            return config
        }
    }

    func saveConfig(_ config: AppConfig) {
        ensureBaseDirectory()
        do {
            let data = try JSONEncoder.pretty.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            // ignore
        }
    }

    func loadContexts() -> [ProjectContext] {
        ensureBaseDirectory()
        guard fileManager.fileExists(atPath: contextsURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: contextsURL)
            return try JSONDecoder().decode([ProjectContext].self, from: data)
        } catch {
            return []
        }
    }

    func saveContexts(_ contexts: [ProjectContext]) {
        ensureBaseDirectory()
        do {
            let data = try JSONEncoder.pretty.encode(contexts)
            try data.write(to: contextsURL, options: .atomic)
        } catch {
            // ignore
        }
    }

    func logoURL(for key: String) -> URL {
        logosURL.appendingPathComponent("\(sanitizeLogoKey(key)).png")
    }

    func logoExists(for key: String) -> Bool {
        fileManager.fileExists(atPath: logoURL(for: key).path)
    }

    func defaultConfig() -> AppConfig {
        let builtin = Storage.builtinSites()
        let order = builtin.map { $0.id }
        return AppConfig(
            sites: builtin,
            siteOrder: order,
            pinnedSiteIds: [],
            recentSiteIds: [],
            theme: "dark",
            sidebarWidth: 64,
            sidebarExpandedWidth: 180,
            language: "zh-CN",
            summaryPromptTemplate: Storage.defaultSummaryPromptTemplate(),
            aiApiBaseUrl: "https://api.openai.com/v1",
            aiApiModel: "",
            aiApiKey: "",
            activeProjectId: "",
            lastActiveTabId: "",
            lastActiveSiteId: ""
        )
    }

    static func builtinSites() -> [AiSite] {
        [
            AiSite(
                id: "deepseek",
                name: "DeepSeek",
                url: "https://chat.deepseek.com",
                icon: "logo:deepseek",
                builtin: true,
                summaryPromptOverride: ""
            ),
            AiSite(
                id: "doubao",
                name: "豆包",
                url: "https://www.doubao.com/chat/",
                icon: "logo:doubao",
                builtin: true,
                summaryPromptOverride: ""
            ),
            AiSite(
                id: "openai",
                name: "ChatGPT",
                url: "https://chatgpt.com",
                icon: "logo:openai",
                builtin: true,
                summaryPromptOverride: ""
            ),
            AiSite(
                id: "qianwen",
                name: "通义千问",
                url: "https://tongyi.aliyun.com/qianwen/",
                icon: "logo:qianwen",
                builtin: true,
                summaryPromptOverride: ""
            )
        ]
    }

    static func defaultSummaryPromptTemplate() -> String {
        """
请把以下内容总结成可迁移的上下文（输出语言：{language}）：

要求：
1) 1段简短摘要（<=120字）
2) 5-10条要点列表
3) 关键约束/偏好（如有）

输出为纯文本，结构：
摘要: ...
要点: - ...
约束: - ...

内容：
{text}
"""
    }
}

private struct BundledSiteConfig: Codable {
    var sites: [BundledSite]
}

private struct BundledSite: Codable {
    var id: String?
    var name: String
    var url: String
    var icon: String
    var summaryPromptOverride: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case icon
        case summaryPromptOverride = "summary_prompt_override"
    }
}

private extension Storage {
    func seedBuiltinLogosIfNeeded() {
        let builtin = ["deepseek", "doubao", "openai", "qianwen"]
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        for key in builtin {
            let target = logoURL(for: key)
            if fileManager.fileExists(atPath: target.path) {
                continue
            }
            guard let resourceURL = bundle.url(forResource: key, withExtension: "png", subdirectory: "Logos")
                ?? bundle.url(forResource: key, withExtension: "png") else {
                continue
            }
            do {
                let data = try Data(contentsOf: resourceURL)
                try data.write(to: target, options: .atomic)
            } catch {
                // ignore
            }
        }
    }

    func sanitizeLogoKey(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

    func loadBundledSiteConfig() -> BundledSiteConfig? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "site-config", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(BundledSiteConfig.self, from: data)
        } catch {
            return nil
        }
    }

    func mergeBundledSites(_ bundled: BundledSiteConfig, into config: AppConfig) -> AppConfig {
        var updated = config
        var sites = updated.sites
        var siteOrder = updated.siteOrder

        var idIndex: [String: Int] = [:]
        var urlIndex: [String: Int] = [:]
        for (index, site) in sites.enumerated() {
            idIndex[site.id] = index
            urlIndex[normalizedUrlForMatch(site.url)] = index
        }

        for entry in bundled.sites {
            let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUrl = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedIcon = entry.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty || trimmedUrl.isEmpty {
                continue
            }

            let normalizedUrl = normalizeUrl(trimmedUrl)
            let matchIndex: Int?
            if let id = entry.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                matchIndex = idIndex[id]
            } else {
                matchIndex = urlIndex[normalizedUrlForMatch(normalizedUrl)]
            }

            let iconKey = resolveBundledIconKey(from: trimmedIcon)
            let summaryOverride = entry.summaryPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let index = matchIndex {
                sites[index].name = trimmedName
                sites[index].url = normalizedUrl
                sites[index].icon = iconKey
                if let summaryOverride {
                    sites[index].summaryPromptOverride = summaryOverride
                }
                idIndex[sites[index].id] = index
                urlIndex[normalizedUrlForMatch(normalizedUrl)] = index
                if !siteOrder.contains(sites[index].id) {
                    siteOrder.append(sites[index].id)
                }
                continue
            }

            let siteId: String
            if let id = entry.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                siteId = id
            } else {
                siteId = "custom_\(UUID().uuidString.split(separator: "-").first ?? "")"
            }

            let site = AiSite(
                id: siteId,
                name: trimmedName,
                url: normalizedUrl,
                icon: iconKey,
                builtin: false,
                summaryPromptOverride: summaryOverride ?? ""
            )
            sites.append(site)
            idIndex[siteId] = sites.count - 1
            urlIndex[normalizedUrlForMatch(normalizedUrl)] = sites.count - 1
            if !siteOrder.contains(siteId) {
                siteOrder.append(siteId)
            }
        }

        updated.sites = sites
        updated.siteOrder = siteOrder
        return updated
    }

    func resolveBundledIconKey(from fileName: String) -> String {
        guard let logoKey = importBundledLogo(named: fileName) else {
            return "sf:globe"
        }
        return "logo:\(logoKey)"
    }

    func importBundledLogo(named fileName: String) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        let lastComponent = (trimmed as NSString).lastPathComponent
        let stem = (lastComponent as NSString).deletingPathExtension
        let ext = (lastComponent as NSString).pathExtension
        if stem.isEmpty {
            return nil
        }

        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        let candidates: [(String, String)] = ext.isEmpty
            ? [(stem, "png"), (stem, "jpg"), (stem, "jpeg"), (stem, "webp"), (stem, "gif"), (stem, "heic"), (stem, "tiff")]
            : [(stem, ext)]

        let resourceURL: URL? = candidates.compactMap {
            bundle.url(forResource: $0.0, withExtension: $0.1, subdirectory: "Logos")
        }.first

        guard let resourceURL else {
            return nil
        }

        let encodedData: Data
        if resourceURL.pathExtension.lowercased() == "png" {
            do {
                encodedData = try Data(contentsOf: resourceURL)
            } catch {
                return nil
            }
        } else {
            guard let image = NSImage(contentsOf: resourceURL),
                  let encoded = pngData(from: image) else {
                return nil
            }
            encodedData = encoded
        }

        let target = logoURL(for: stem)
        do {
            try encodedData.write(to: target, options: .atomic)
        } catch {
            return nil
        }
        return stem
    }

    func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    func normalizeUrl(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }

    func normalizedUrlForMatch(_ raw: String) -> String {
        var normalized = normalizeUrl(raw).lowercased()
        // Remove protocol
        normalized = normalized.replacingOccurrences(of: "https://", with: "")
        normalized = normalized.replacingOccurrences(of: "http://", with: "")
        // Remove www prefix
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }
        // Remove trailing slashes and path for domain-level matching
        if let firstSlash = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<firstSlash])
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
