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
    var sidebarIconSize: Double
    var sidebarTextSize: Double
    var toolbarAutoHide: Bool
    var autoSaveEnabled: Bool
    var autoSaveInterval: Double
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
        case sidebarIconSize = "sidebar_icon_size"
        case sidebarTextSize = "sidebar_text_size"
        case toolbarAutoHide = "toolbar_auto_hide"
        case autoSaveEnabled = "auto_save_enabled"
        case autoSaveInterval = "auto_save_interval"
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

    init(
        sites: [AiSite],
        siteOrder: [String],
        pinnedSiteIds: [String],
        recentSiteIds: [String],
        theme: String,
        sidebarWidth: Double,
        sidebarExpandedWidth: Double,
        sidebarIconSize: Double,
        sidebarTextSize: Double,
        toolbarAutoHide: Bool,
        autoSaveEnabled: Bool,
        autoSaveInterval: Double,
        language: String,
        summaryPromptTemplate: String,
        aiApiBaseUrl: String,
        aiApiModel: String,
        aiApiKey: String,
        searchMode: String,
        aiEmbeddingModel: String,
        activeProjectId: String,
        lastActiveTabId: String,
        lastActiveSiteId: String
    ) {
        self.sites = sites
        self.siteOrder = siteOrder
        self.pinnedSiteIds = pinnedSiteIds
        self.recentSiteIds = recentSiteIds
        self.theme = theme
        self.sidebarWidth = sidebarWidth
        self.sidebarExpandedWidth = sidebarExpandedWidth
        self.sidebarIconSize = sidebarIconSize
        self.sidebarTextSize = sidebarTextSize
        self.toolbarAutoHide = toolbarAutoHide
        self.autoSaveEnabled = autoSaveEnabled
        self.autoSaveInterval = autoSaveInterval
        self.language = language
        self.summaryPromptTemplate = summaryPromptTemplate
        self.aiApiBaseUrl = aiApiBaseUrl
        self.aiApiModel = aiApiModel
        self.aiApiKey = aiApiKey
        self.searchMode = searchMode
        self.aiEmbeddingModel = aiEmbeddingModel
        self.activeProjectId = activeProjectId
        self.lastActiveTabId = lastActiveTabId
        self.lastActiveSiteId = lastActiveSiteId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sites = try container.decode([AiSite].self, forKey: .sites)
        siteOrder = try container.decode([String].self, forKey: .siteOrder)
        pinnedSiteIds = try container.decode([String].self, forKey: .pinnedSiteIds)
        recentSiteIds = try container.decode([String].self, forKey: .recentSiteIds)
        theme = try container.decode(String.self, forKey: .theme)
        sidebarWidth = try container.decode(Double.self, forKey: .sidebarWidth)
        sidebarExpandedWidth = try container.decode(Double.self, forKey: .sidebarExpandedWidth)
        sidebarIconSize = try container.decodeIfPresent(Double.self, forKey: .sidebarIconSize) ?? 28
        sidebarTextSize = try container.decodeIfPresent(Double.self, forKey: .sidebarTextSize) ?? 15
        toolbarAutoHide = try container.decodeIfPresent(Bool.self, forKey: .toolbarAutoHide) ?? true
        autoSaveEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSaveEnabled) ?? true
        autoSaveInterval = try container.decodeIfPresent(Double.self, forKey: .autoSaveInterval) ?? 30
        language = try container.decode(String.self, forKey: .language)
        summaryPromptTemplate = try container.decode(String.self, forKey: .summaryPromptTemplate)
        aiApiBaseUrl = try container.decode(String.self, forKey: .aiApiBaseUrl)
        aiApiModel = try container.decode(String.self, forKey: .aiApiModel)
        aiApiKey = try container.decode(String.self, forKey: .aiApiKey)
        searchMode = try container.decode(String.self, forKey: .searchMode)
        aiEmbeddingModel = try container.decode(String.self, forKey: .aiEmbeddingModel)
        activeProjectId = try container.decode(String.self, forKey: .activeProjectId)
        lastActiveTabId = try container.decode(String.self, forKey: .lastActiveTabId)
        lastActiveSiteId = try container.decode(String.self, forKey: .lastActiveSiteId)
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

enum HistoryTimePreset: String, CaseIterable, Identifiable {
    case all = "all"
    case today = "today"
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"
    case custom = "custom"

    var id: String { rawValue }
}

struct HistoryFilter: Equatable {
    var keyword: String
    var siteName: String?
    var timePreset: HistoryTimePreset
    var customStart: Date?
    var customEnd: Date?
    var codeOnly: Bool
}

struct SavedConversation: Identifiable, Hashable {
    var id: Int64
    var siteName: String
    var url: String
    var content: String
    var markdown: String
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
