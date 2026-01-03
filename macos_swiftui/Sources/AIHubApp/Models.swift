import Foundation

struct AiSite: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var icon: String
    var builtin: Bool
    var summaryPromptOverride: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case icon
        case builtin
        case summaryPromptOverride = "summary_prompt_override"
    }
}

struct AppConfig: Codable {
    var sites: [AiSite]
    var siteOrder: [String]
    var pinnedSiteIds: [String]
    var recentSiteIds: [String]
    var theme: String
    var sidebarWidth: Double
    var sidebarExpandedWidth: Double
    var language: String
    var summaryPromptTemplate: String
    var aiApiBaseUrl: String
    var aiApiModel: String
    var aiApiKey: String
    var searchMode: String
    var aiEmbeddingModel: String
    var activeProjectId: String
    var lastActiveTabId: String
    var lastActiveSiteId: String

    enum CodingKeys: String, CodingKey {
        case sites
        case siteOrder = "site_order"
        case pinnedSiteIds = "pinned_site_ids"
        case recentSiteIds = "recent_site_ids"
        case theme
        case sidebarWidth = "sidebar_width"
        case sidebarExpandedWidth = "sidebar_expanded_width"
        case language
        case summaryPromptTemplate = "summary_prompt_template"
        case aiApiBaseUrl = "ai_api_base_url"
        case aiApiModel = "ai_api_model"
        case aiApiKey = "ai_api_key"
        case searchMode = "search_mode"
        case aiEmbeddingModel = "ai_embedding_model"
        case activeProjectId = "active_project_id"
        case lastActiveTabId = "last_active_tab_id"
        case lastActiveSiteId = "last_active_site_id"
    }
}

struct ProjectContext: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var notes: String
    var summary: String
    var createdAt: UInt64
    var updatedAt: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case summary
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TabInfo: Identifiable, Hashable {
    var id: String
    var siteId: String
}

enum LayoutMode: String {
    case single
    case split
}

enum SearchMode: String, CaseIterable, Identifiable {
    case keyword = "keyword"
    case semanticOffline = "semantic_offline"
    case semanticOnline = "semantic_online"

    var id: String { rawValue }
}

struct SavedConversation: Identifiable, Hashable {
    var id: Int64
    var siteName: String
    var url: String
    var content: String
    var createdAt: UInt64

    var snippet: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 80, limitedBy: trimmed.endIndex) else {
            return ""
        }
        if endIndex == trimmed.endIndex {
            return trimmed
        }
        return String(trimmed[..<endIndex]) + "…"
    }
}

struct SavedConversationPreview: Identifiable, Hashable {
    var id: Int64
    var siteName: String
    var url: String
    var snippet: String
    var createdAt: UInt64
}
