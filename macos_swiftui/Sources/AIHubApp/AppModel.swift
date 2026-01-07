import AppKit
import Combine
import Foundation
import NaturalLanguage
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var projects: [ProjectContext]
    @Published var tabs: [TabInfo] = []
    @Published var activeTabId: String = "" {
        didSet {
            guard !activeTabId.isEmpty, let siteId = siteIdForTab(activeTabId) else { return }
            currentSiteId = siteId
        }
    }
    @Published var currentSiteId: String = ""
    @Published var layoutMode: LayoutMode = .single
    @Published var splitRatio: Double = 0.5
    @Published var leftTabId: String?
    @Published var rightTabId: String?
    @Published var isSummarizing = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var loading = false
    @Published var savedSearchResults: [SavedConversationPreview] = []
    @Published private(set) var recentSavedConversations: [SavedConversationPreview] = []
    @Published private(set) var historyItems: [SavedConversationPreview] = []
    @Published private(set) var historyTotalCount: Int = 0
    @Published private(set) var historyLoading = false
    @Published private(set) var historyHasMore = false

    let webViewManager = WebViewManager()

    private var cancellables = Set<AnyCancellable>()
    private var autoSaveTask: Task<Void, Never>?
    private let storage = Storage.shared
    private let conversationStore = ConversationStore.shared
    private var historyOffset: Int = 0
    private let historyPageSize = 40

    init() {
        var loaded = storage.loadConfig()
        loaded = Self.sanitizeConfig(loaded, storage: storage)
        config = loaded
        projects = storage.loadContexts()

        if let restoredSite = siteById(loaded.lastActiveSiteId) {
            currentSiteId = restoredSite.id
            activeTabId = loaded.lastActiveTabId.isEmpty ? restoredSite.id : loaded.lastActiveTabId
            ensureTabExists(tabId: activeTabId, siteId: restoredSite.id)
        }

        webViewManager.$loadingTabs
            .combineLatest($activeTabId, $layoutMode, $leftTabId)
            .combineLatest($rightTabId)
            .sink { [weak self] combined, right in
                guard let self else { return }
                let (loadingTabs, active, mode, left) = combined
                if mode == .split {
                    let leftLoading = left.map { loadingTabs.contains($0) } ?? false
                    let rightLoading = right.map { loadingTabs.contains($0) } ?? false
                    self.loading = leftLoading || rightLoading
                } else {
                    self.loading = loadingTabs.contains(active)
                }
            }
            .store(in: &cancellables)

        webViewManager.$lastErrorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.errorMessage = message
                self?.webViewManager.setError(message: nil)
            }
            .store(in: &cancellables)

        Task {
            await loadRecentSavedConversations()
            configureAutoSave()
        }
    }

    func t(_ key: String) -> String {
        I18nCatalog.shared.t(key, language: SupportedLanguage.fromConfig(config.language))
    }

    var sidebarWidth: Double { config.sidebarWidth }
    var sidebarExpandedWidth: Double { config.sidebarExpandedWidth }
    var isDarkTheme: Bool { config.theme == "dark" }

    func supportedLanguages() -> [SupportedLanguage] {
        SupportedLanguage.allCases
    }

    func setTheme(_ value: String) {
        updateConfig { $0.theme = value }
    }

    func setLanguage(_ value: SupportedLanguage) {
        updateConfig { $0.language = value.rawValue }
    }

    func updateSidebarWidth(_ width: Double) {
        updateConfig {
            let safeWidth = max(64, width)
            $0.sidebarWidth = safeWidth
            if safeWidth > 64 {
                $0.sidebarExpandedWidth = safeWidth
            }
        }
    }

    func updateSidebarItemSizes(iconSize: Double, textSize: Double) {
        updateConfig {
            $0.sidebarIconSize = min(30, max(15, iconSize))
            $0.sidebarTextSize = min(30, max(15, textSize))
        }
    }

    func setToolbarAutoHide(_ enabled: Bool) {
        updateConfig { $0.toolbarAutoHide = enabled }
    }

    func updateAutoSaveSettings(enabled: Bool, interval: Double) {
        let clampedInterval = min(300, max(10, interval))
        updateConfig {
            $0.autoSaveEnabled = enabled
            $0.autoSaveInterval = clampedInterval
        }
        configureAutoSave()
    }

    func updateAiSettings(baseUrl: String, model: String, apiKey: String, clearKey: Bool, embeddingModel: String) {
        updateConfig { config in
            let trimmedBase = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            config.aiApiBaseUrl = trimmedBase.isEmpty ? "https://api.openai.com/v1" : trimmedBase
            config.aiApiModel = model
            config.aiEmbeddingModel = embeddingModel
            if clearKey {
                config.aiApiKey = ""
            } else if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.aiApiKey = apiKey
            }
        }
    }

    func updateSearchMode(_ mode: SearchMode) {
        updateConfig { $0.searchMode = mode.rawValue }
    }

    func updateSummaryPromptTemplate(_ template: String) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        updateConfig { $0.summaryPromptTemplate = trimmed.isEmpty ? Storage.defaultSummaryPromptTemplate() : template }
    }

    func resetNavigation() {
        updateConfig { config in
            var seen = Set<String>()
            config.sites = config.sites.filter { site in
                let inserted = seen.insert(site.id).inserted
                return inserted
            }
            config.pinnedSiteIds = []
            config.recentSiteIds = []

            let existing = Set(config.sites.map { $0.id })
            let builtinOrder = Storage.builtinSites().map { $0.id }.filter { existing.contains($0) }
            var order: [String] = []
            var orderSeen = Set<String>()
            for id in builtinOrder where orderSeen.insert(id).inserted {
                order.append(id)
            }
            for site in config.sites where orderSeen.insert(site.id).inserted {
                order.append(site.id)
            }
            config.siteOrder = order
        }
    }

    func sitesOrdered() -> [AiSite] {
        let existing = Dictionary(uniqueKeysWithValues: config.sites.map { ($0.id, $0) })
        var result: [AiSite] = []
        var seen = Set<String>()
        for id in config.siteOrder {
            if let site = existing[id], seen.insert(id).inserted {
                result.append(site)
            }
        }
        for site in config.sites where seen.insert(site.id).inserted {
            result.append(site)
        }
        return result
    }

    func pinnedSites() -> [AiSite] {
        let siteMap = Dictionary(uniqueKeysWithValues: config.sites.map { ($0.id, $0) })
        return config.pinnedSiteIds.compactMap { siteMap[$0] }
    }

    func recentSites() -> [AiSite] {
        let siteMap = Dictionary(uniqueKeysWithValues: config.sites.map { ($0.id, $0) })
        return config.recentSiteIds.compactMap { siteMap[$0] }
    }

    func unpinnedSites(excluding excluded: Set<String> = []) -> [AiSite] {
        let pinned = Set(config.pinnedSiteIds)
        return sitesOrdered().filter { !pinned.contains($0.id) && !excluded.contains($0.id) }
    }

    func togglePin(siteId: String, pinned: Bool) {
        updateConfig { config in
            config.pinnedSiteIds.removeAll { $0 == siteId }
            if pinned {
                config.pinnedSiteIds.insert(siteId, at: 0)
            }
        }
    }

    func updatePinnedOrder(_ order: [String]) {
        updateConfig { $0.pinnedSiteIds = order }
    }

    func updateSiteOrder(_ order: [String]) {
        updateConfig { $0.siteOrder = order }
    }

    func addSite(name: String, url: String, icon: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedUrl.isEmpty {
            throw AppError(message: t("common.fillNameUrl"))
        }

        let siteId = "custom_\(UUID().uuidString.split(separator: "-").first ?? "")"
        let normalized = normalizeUrl(trimmedUrl)
        let site = AiSite(
            id: siteId,
            name: trimmedName,
            url: normalized,
            icon: icon,
            builtin: false,
            summaryPromptOverride: ""
        )

        updateConfig { config in
            config.sites.append(site)
            config.siteOrder.append(site.id)
        }
    }

    func updateSite(siteId: String, name: String, url: String, icon: String, summaryPromptOverride: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedUrl.isEmpty {
            throw AppError(message: t("common.fillNameUrl"))
        }
        let normalized = normalizeUrl(trimmedUrl)
        var oldUrl: String?

        updateConfig { config in
            guard let index = config.sites.firstIndex(where: { $0.id == siteId }) else { return }
            oldUrl = config.sites[index].url
            config.sites[index].name = trimmedName
            config.sites[index].url = normalized
            config.sites[index].icon = icon
            config.sites[index].summaryPromptOverride = summaryPromptOverride
        }

        if let oldUrl, oldUrl != normalized {
            closeTabs(for: siteId)
        }
    }

    func removeSite(siteId: String) {
        updateConfig { config in
            config.sites.removeAll { $0.id == siteId }
            config.siteOrder.removeAll { $0 == siteId }
            config.pinnedSiteIds.removeAll { $0 == siteId }
            config.recentSiteIds.removeAll { $0 == siteId }
            if config.lastActiveSiteId == siteId {
                config.lastActiveSiteId = ""
                config.lastActiveTabId = ""
            }
        }

        closeTabs(for: siteId)
        if currentSiteId == siteId {
            currentSiteId = ""
            activeTabId = ""
        }
    }

    func createTab(for siteId: String) {
        guard let site = siteById(siteId) else { return }
        let tabId = "\(siteId)_\(UUID().uuidString.split(separator: "-").first ?? "")"
        tabs.append(TabInfo(id: tabId, siteId: siteId))
        if let url = URL(string: site.url) {
            _ = webViewManager.webView(for: tabId, url: url)
        }
        switchToTab(tabId)
    }

    func switchToTab(_ tabId: String) {
        guard let siteId = siteIdForTab(tabId) else { return }
        let previous = activeTabId
        let existed = webViewManager.hasWebView(tabId: tabId)
        layoutMode = .single
        leftTabId = nil
        rightTabId = nil
        activeTabId = tabId
        currentSiteId = siteId
        ensureTabExists(tabId: tabId, siteId: siteId)
        updateRecentSite(siteId)
        updateLastActive(tabId: tabId, siteId: siteId)
        if existed && previous != tabId {
            webViewManager.refreshIfReady(tabId: tabId)
        }
    }

    func switchView(_ siteId: String) {
        let previous = activeTabId
        let existed = webViewManager.hasWebView(tabId: siteId)
        layoutMode = .single
        leftTabId = nil
        rightTabId = nil
        activeTabId = siteId
        currentSiteId = siteId
        ensureTabExists(tabId: siteId, siteId: siteId)
        updateRecentSite(siteId)
        updateLastActive(tabId: siteId, siteId: siteId)
        if existed && previous != siteId {
            webViewManager.refreshIfReady(tabId: siteId)
        }
    }

    func refreshVisibleTabs() {
        let tabIds: [String]
        if layoutMode == .split {
            tabIds = [leftTabId, rightTabId].compactMap { $0 }
        } else {
            let active = activeTabId.isEmpty ? currentSiteId : activeTabId
            tabIds = active.isEmpty ? [] : [active]
        }
        for tabId in tabIds {
            webViewManager.refreshIfReady(tabId: tabId)
        }
    }

    func setSplitEnabled(_ enabled: Bool) throws {
        if !enabled {
            layoutMode = .single
            leftTabId = nil
            rightTabId = nil
            return
        }
        guard tabs.count >= 2 else {
            throw AppError(message: t("top.splitNeedTwoTabs"))
        }
        let active = activeTabId.isEmpty ? currentSiteId : activeTabId
        guard !active.isEmpty else {
            throw AppError(message: t("top.splitNeedTwoTabs"))
        }
        let left = leftTabId ?? active
        let right = rightTabId ?? tabs.first { $0.id != left }?.id
        guard let right else {
            throw AppError(message: t("top.splitNeedTwoTabs"))
        }
        layoutMode = .split
        leftTabId = left
        rightTabId = right
        splitRatio = max(0.2, min(0.8, splitRatio))
        activeTabId = left
        if let leftSite = siteIdForTab(left) {
            ensureTabExists(tabId: left, siteId: leftSite)
        }
        if let rightSite = siteIdForTab(right) {
            ensureTabExists(tabId: right, siteId: rightSite)
        }
    }

    func updateSplitRatio(_ ratio: Double) {
        splitRatio = max(0.2, min(0.8, ratio))
    }

    func updateSplitTabs(left: String?, right: String?) throws {
        let leftValue = left?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightValue = right?.trimmingCharacters(in: .whitespacesAndNewlines)
        let leftTrimmed = (leftValue?.isEmpty ?? true) ? nil : leftValue
        let rightTrimmed = (rightValue?.isEmpty ?? true) ? nil : rightValue
        if leftTrimmed == nil && rightTrimmed == nil {
            throw AppError(message: "至少需要选择一个 Tab")
        }
        if leftTrimmed == rightTrimmed {
            throw AppError(message: "左右 Tab 不能相同")
        }
        layoutMode = .split
        leftTabId = leftTrimmed
        rightTabId = rightTrimmed
        if let leftTrimmed {
            if let leftSite = siteIdForTab(leftTrimmed) {
                ensureTabExists(tabId: leftTrimmed, siteId: leftSite)
            }
        }
        if let rightTrimmed {
            if let rightSite = siteIdForTab(rightTrimmed) {
                ensureTabExists(tabId: rightTrimmed, siteId: rightSite)
            }
        }
    }

    func closeTab(_ tabId: String) {
        guard let closedSiteId = siteIdForTab(tabId) else { return }
        tabs.removeAll { $0.id == tabId }
        webViewManager.remove(tabId: tabId)

        if layoutMode == .split {
            if leftTabId == tabId { leftTabId = nil }
            if rightTabId == tabId { rightTabId = nil }
            if leftTabId == nil || rightTabId == nil {
                layoutMode = .single
                let remaining = leftTabId ?? rightTabId
                leftTabId = nil
                rightTabId = nil
                if let remaining {
                    switchToTab(remaining)
                }
            }
            return
        }

        if activeTabId == tabId {
            if let fallback = firstSiteId(excluding: closedSiteId) {
                switchView(fallback)
            } else {
                activeTabId = ""
                currentSiteId = ""
                clearLastActive()
            }
        }
    }

    func refreshSite(_ siteId: String) {
        let targets = tabs.filter { $0.siteId == siteId }.map { $0.id }
        for tabId in targets {
            webViewManager.reload(tabId: tabId)
        }
    }

    func clearCache(for siteId: String) async {
        let tabIds = tabs.filter { $0.siteId == siteId }.map { $0.id }
        tabs.removeAll { $0.siteId == siteId }
        webViewManager.removeAll(tabIds: tabIds)

        if let host = hostForSite(siteId) {
            await webViewManager.clearWebsiteData(for: [host])
        }

        if currentSiteId == siteId {
            currentSiteId = ""
            activeTabId = ""
            clearLastActive()
        }
    }

    func summarizeActiveTab() async throws -> String {
        if isSummarizing {
            throw AppError(message: "总结正在进行中，请稍候…")
        }
        let tabId = activeTabId.isEmpty ? currentSiteId : activeTabId
        guard !tabId.isEmpty else {
            throw AppError(message: "没有可总结的页面")
        }

        isSummarizing = true
        defer { isSummarizing = false }

        let extracted = try await extractText(from: tabId)
        if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppError(message: "未能提取到页面文本（可能被站点限制或页面未加载完成）")
        }

        let siteId = siteIdForTab(tabId) ?? tabId
        let summary = try await summarizeText(extracted, siteId: siteId)
        let projectId = ensureActiveProjectId()
        updateProject(projectId: projectId, notes: extracted, summary: summary)
        return summary
    }

    func summarizeNotes(_ notes: String) async throws -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppError(message: t("context.summarizeNeedsNotes"))
        }
        return try await summarizeText(trimmed, siteId: nil)
    }

    func listProjects() -> [ProjectContext] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadProject(projectId: String) -> ProjectContext? {
        projects.first { $0.id == projectId }
    }

    func createProject(title: String) -> String {
        let id = "proj_\(UUID().uuidString.split(separator: "-").first ?? "")"
        let ts = nowTs()
        let project = ProjectContext(id: id, title: title, notes: "", summary: "", createdAt: ts, updatedAt: ts)
        projects.append(project)
        persistProjects()
        updateConfig { $0.activeProjectId = id }
        return id
    }

    func deleteProject(projectId: String) {
        projects.removeAll { $0.id == projectId }
        persistProjects()
        if config.activeProjectId == projectId {
            updateConfig { $0.activeProjectId = "" }
        }
    }

    func updateProject(projectId: String, title: String? = nil, notes: String? = nil, summary: String? = nil) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var project = projects[index]
        if let title { project.title = title }
        if let notes { project.notes = notes }
        if let summary { project.summary = summary }
        project.updatedAt = nowTs()
        projects[index] = project
        persistProjects()
    }

    func setActiveProject(_ projectId: String) {
        updateConfig { $0.activeProjectId = projectId }
    }

    func ensureActiveProjectId() -> String {
        if !config.activeProjectId.isEmpty, projects.contains(where: { $0.id == config.activeProjectId }) {
            return config.activeProjectId
        }

        if let first = projects.first {
            updateConfig { $0.activeProjectId = first.id }
            return first.id
        }

        let id = createProject(title: "默认项目")
        return id
    }

    func setSummaryPromptTemplate(_ template: String) {
        updateConfig { $0.summaryPromptTemplate = template }
    }

    func updatePinnedOrder(fromOffsets: IndexSet, toOffset: Int) {
        var order = config.pinnedSiteIds
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        updatePinnedOrder(order)
    }

    func updateSiteOrder(fromOffsets: IndexSet, toOffset: Int, currentUnpinned: [AiSite]) {
        var unpinnedIds = currentUnpinned.map { $0.id }
        unpinnedIds.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let pinnedSet = Set(config.pinnedSiteIds)
        let next = config.pinnedSiteIds + unpinnedIds.filter { !pinnedSet.contains($0) }
        updateSiteOrder(next)
    }

    func ensureTabExists(tabId: String, siteId: String) {
        if tabs.contains(where: { $0.id == tabId }) {
            return
        }
        tabs.append(TabInfo(id: tabId, siteId: siteId))
        if let site = siteById(siteId), let url = URL(string: site.url) {
            _ = webViewManager.webView(for: tabId, url: url)
        }
    }

    func webViewForTab(_ tabId: String) -> WebViewContainer? {
        guard let siteId = siteIdForTab(tabId), let site = siteById(siteId), let url = URL(string: site.url) else {
            return nil
        }
        let webview = webViewManager.webView(for: tabId, url: url)
        return WebViewContainer(webView: webview)
    }

    private func updateConfig(_ mutate: (inout AppConfig) -> Void) {
        var next = config
        mutate(&next)
        config = next
        storage.saveConfig(next)
    }

    private static func sanitizeConfig(_ config: AppConfig, storage: Storage) -> AppConfig {
        var sanitized = config
        var seen = Set<String>()
        sanitized.sites = sanitized.sites.filter { seen.insert($0.id).inserted }

        let builtin = Storage.builtinSites()
        for site in builtin where !sanitized.sites.contains(where: { $0.id == site.id }) {
            sanitized.sites.append(site)
            sanitized.siteOrder.append(site.id)
        }

        let existing = Set(sanitized.sites.map { $0.id })
        var order: [String] = []
        var orderSeen = Set<String>()
        for id in sanitized.siteOrder where existing.contains(id) && orderSeen.insert(id).inserted {
            order.append(id)
        }
        for site in sanitized.sites where orderSeen.insert(site.id).inserted {
            order.append(site.id)
        }
        sanitized.siteOrder = order

        sanitized.pinnedSiteIds = sanitized.pinnedSiteIds.filter { existing.contains($0) }
        sanitized.recentSiteIds = sanitized.recentSiteIds.filter { existing.contains($0) }

        if sanitized.sidebarWidth < 64 {
            sanitized.sidebarWidth = 64
        }
        if sanitized.sidebarExpandedWidth < 64 {
            sanitized.sidebarExpandedWidth = 180
        }
        if sanitized.sidebarWidth > 64 && sanitized.sidebarExpandedWidth <= 64 {
            sanitized.sidebarExpandedWidth = sanitized.sidebarWidth
        }
        let iconSize = min(30, max(15, sanitized.sidebarIconSize))
        if sanitized.sidebarIconSize != iconSize {
            sanitized.sidebarIconSize = iconSize
        }
        let textSize = min(30, max(15, sanitized.sidebarTextSize))
        if sanitized.sidebarTextSize != textSize {
            sanitized.sidebarTextSize = textSize
        }
        let autoSaveInterval = min(300, max(10, sanitized.autoSaveInterval))
        if sanitized.autoSaveInterval != autoSaveInterval {
            sanitized.autoSaveInterval = autoSaveInterval
        }
        if sanitized.aiApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sanitized.aiApiBaseUrl = "https://api.openai.com/v1"
        }
        if SearchMode(rawValue: sanitized.searchMode) == nil {
            sanitized.searchMode = SearchMode.keyword.rawValue
        }
        if !existing.contains(sanitized.lastActiveSiteId) {
            sanitized.lastActiveSiteId = ""
            sanitized.lastActiveTabId = ""
        }

        storage.saveConfig(sanitized)
        return sanitized
    }

    private func updateRecentSite(_ siteId: String) {
        updateConfig { config in
            config.recentSiteIds.removeAll { $0 == siteId }
            config.recentSiteIds.insert(siteId, at: 0)
            config.recentSiteIds = Array(config.recentSiteIds.prefix(10))
        }
    }

    private func updateLastActive(tabId: String, siteId: String) {
        updateConfig {
            $0.lastActiveTabId = tabId
            $0.lastActiveSiteId = siteId
        }
    }

    private func clearLastActive() {
        updateConfig {
            $0.lastActiveTabId = ""
            $0.lastActiveSiteId = ""
        }
    }

    private func closeTabs(for siteId: String) {
        let tabIds = tabs.filter { $0.siteId == siteId }.map { $0.id }
        tabs.removeAll { $0.siteId == siteId }
        webViewManager.removeAll(tabIds: tabIds)
    }

    private func siteById(_ siteId: String) -> AiSite? {
        config.sites.first { $0.id == siteId }
    }

    private func siteIdForTab(_ tabId: String) -> String? {
        if let tab = tabs.first(where: { $0.id == tabId }) {
            return tab.siteId
        }
        if config.sites.contains(where: { $0.id == tabId }) {
            return tabId
        }
        return nil
    }

    private func hostForSite(_ siteId: String) -> String? {
        guard let site = siteById(siteId), let url = URL(string: site.url) else {
            return nil
        }
        return url.host
    }

    private func normalizeUrl(_ raw: String) -> String {
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return raw
        }
        return "https://" + raw
    }

    private func nowTs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970)
    }

    private func persistProjects() {
        storage.saveContexts(projects)
    }

    private func extractText(from tabId: String) async throws -> String {
        let script = "document?.body?.innerText || ''"
        return try await webViewManager.evaluateJavaScript(tabId: tabId, script: script)
    }

    private func extractMarkdown(from tabId: String) async throws -> String {
        let script = """
        (() => {
          const isHighlight = (el) => {
            const tag = el.tagName ? el.tagName.toLowerCase() : "";
            if (tag === "mark") return true;
            const cls = (el.getAttribute("class") || "").toLowerCase();
            if (cls.includes("highlight")) return true;
            const style = (el.getAttribute("style") || "").toLowerCase();
            if (style.includes("background") && style.includes("yellow")) return true;
            return false;
          };

          const walk = (node, listDepth = 0, listType = null) => {
            if (!node) return "";
            if (node.nodeType === Node.TEXT_NODE) {
              return node.nodeValue || "";
            }
            if (node.nodeType !== Node.ELEMENT_NODE) {
              return "";
            }
            const el = node;
            const tag = el.tagName.toLowerCase();

            // Skip hidden elements
            const style = window.getComputedStyle(el);
            if (style.display === "none" || style.visibility === "hidden") return "";

            // Line break
            if (tag === "br") return "\\n";

            // Horizontal rule
            if (tag === "hr") return "\\n\\n---\\n\\n";

            // Code blocks
            if (tag === "pre") {
              const codeEl = el.querySelector("code");
              const text = codeEl ? codeEl.innerText : el.innerText || "";
              const langClass = codeEl?.className.match(/language-(\\w+)/);
              const lang = langClass ? langClass[1] : "";
              return "\\n\\n```" + lang + "\\n" + text + "\\n```\\n\\n";
            }

            // Inline code (not inside pre)
            if (tag === "code") {
              if (el.closest("pre")) return "";
              const text = el.innerText || "";
              return "`" + text + "`";
            }

            // Links
            if (tag === "a") {
              const href = el.getAttribute("href") || "";
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              content = content.trim();
              if (href && content && !href.startsWith("javascript:")) {
                return "[" + content + "](" + href + ")";
              }
              return content;
            }

            // Images
            if (tag === "img") {
              const alt = el.getAttribute("alt") || "";
              const src = el.getAttribute("src") || "";
              if (src) {
                return "![" + alt + "](" + src + ")";
              }
              return "";
            }

            // Bold
            if (tag === "strong" || tag === "b") {
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              return "**" + content + "**";
            }

            // Italic
            if (tag === "em" || tag === "i") {
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              return "*" + content + "*";
            }

            // Strikethrough
            if (tag === "del" || tag === "s" || tag === "strike") {
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              return "~~" + content + "~~";
            }

            // Headings
            if (/^h[1-6]$/.test(tag)) {
              const level = parseInt(tag[1]);
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              return "\\n\\n" + "#".repeat(level) + " " + content.trim() + "\\n\\n";
            }

            // Blockquote
            if (tag === "blockquote") {
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              const lines = content.trim().split("\\n");
              return "\\n\\n" + lines.map(l => "> " + l).join("\\n") + "\\n\\n";
            }

            // Unordered list
            if (tag === "ul") {
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth + 1, "ul");
              }
              return listDepth === 0 ? "\\n" + content + "\\n" : content;
            }

            // Ordered list
            if (tag === "ol") {
              let content = "";
              let index = 1;
              for (const child of el.childNodes) {
                if (child.nodeType === Node.ELEMENT_NODE && child.tagName.toLowerCase() === "li") {
                  content += walk(child, listDepth + 1, "ol", index);
                  index++;
                } else {
                  content += walk(child, listDepth + 1, "ol");
                }
              }
              return listDepth === 0 ? "\\n" + content + "\\n" : content;
            }

            // List item
            if (tag === "li") {
              const indent = "  ".repeat(Math.max(0, listDepth - 1));
              let content = "";
              for (const child of el.childNodes) {
                content += walk(child, listDepth, listType);
              }
              const prefix = listType === "ol" ? "1. " : "- ";
              return indent + prefix + content.trim() + "\\n";
            }

            // Table
            if (tag === "table") {
              let rows = [];
              const trs = el.querySelectorAll("tr");
              trs.forEach((tr, rowIndex) => {
                const cells = tr.querySelectorAll("th, td");
                const row = Array.from(cells).map(cell => {
                  let content = "";
                  for (const child of cell.childNodes) {
                    content += walk(child, listDepth, listType);
                  }
                  return content.trim().replace(/\\|/g, "\\\\|").replace(/\\n/g, " ");
                });
                rows.push("| " + row.join(" | ") + " |");
                if (rowIndex === 0) {
                  rows.push("| " + row.map(() => "---").join(" | ") + " |");
                }
              });
              return "\\n\\n" + rows.join("\\n") + "\\n\\n";
            }

            // Skip table internal elements (handled by table)
            if (["thead", "tbody", "tfoot", "tr", "th", "td"].includes(tag)) {
              return "";
            }

            // Paragraph and block elements
            let content = "";
            for (const child of el.childNodes) {
              content += walk(child, listDepth, listType);
            }

            if (isHighlight(el)) {
              content = "==" + content + "==";
            }

            const blockTags = new Set(["p", "div", "section", "article", "header", "footer", "main", "aside", "nav"]);
            if (blockTags.has(tag)) {
              return "\\n" + content.trim() + "\\n";
            }

            return content;
          };

          const body = document.body;
          if (!body) return "";
          return walk(body)
            .replace(/\\n{3,}/g, "\\n\\n")
            .replace(/^\\n+/, "")
            .replace(/\\n+$/, "")
            .trim();
        })();
        """
        return try await webViewManager.evaluateJavaScript(tabId: tabId, script: script)
    }

    func saveCurrentConversation() async {
        let tabId = activeTabId.isEmpty ? currentSiteId : activeTabId
        guard !tabId.isEmpty else {
            errorMessage = t("search.noActiveTab")
            return
        }
        await saveConversation(tabId: tabId, showToast: true)
    }

    private func saveConversation(tabId: String, showToast: Bool) async {
        do {
            let text = try await extractText(from: tabId)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if showToast {
                    errorMessage = t("search.noVisibleContent")
                }
                return
            }

            let markdown: String
            do {
                let extracted = try await extractMarkdown(from: tabId)
                let cleaned = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                markdown = cleaned.isEmpty ? trimmed : cleaned
            } catch {
                markdown = trimmed
            }

            let siteId = siteIdForTab(tabId)
            let siteName = siteId.flatMap { siteById($0)?.name } ?? tabId
            let siteUrl = siteId.flatMap { siteById($0)?.url } ?? ""
            let createdAt = nowTs()

            var embedding: [Float]? = nil
            if currentSearchMode != .keyword {
                do {
                    embedding = try await embeddingForText(trimmed, mode: currentSearchMode)
                } catch {
                    if showToast {
                        errorMessage = t("search.embeddingFailed")
                    }
                }
            }

            _ = try await conversationStore.saveConversation(
                tabId: tabId,
                content: trimmed,
                markdown: markdown,
                siteName: siteName,
                url: siteUrl,
                createdAt: createdAt,
                embedding: embedding
            )
            await loadRecentSavedConversations()
            if showToast {
                toastMessage = t("search.saveSuccess")
            }
        } catch {
            if showToast {
                errorMessage = errorText(error)
            }
        }
    }

    private func configureAutoSave() {
        autoSaveTask?.cancel()
        guard config.autoSaveEnabled else { return }
        let interval = min(300, max(10, config.autoSaveInterval))
        autoSaveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let tabId = self.activeTabId.isEmpty ? self.currentSiteId : self.activeTabId
                guard !tabId.isEmpty else { continue }
                await self.saveConversation(tabId: tabId, showToast: false)
            }
        }
    }

    func updateSavedSearchResults(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            savedSearchResults = []
            return
        }

        do {
            switch currentSearchMode {
            case .keyword:
                savedSearchResults = try await conversationStore.searchKeyword(query: trimmed)
            case .semanticOffline, .semanticOnline:
                do {
                    let embedding = try await embeddingForText(trimmed, mode: currentSearchMode)
                    let semantic = try await conversationStore.searchSemantic(queryEmbedding: embedding)
                    if semantic.isEmpty {
                        savedSearchResults = try await conversationStore.searchKeyword(query: trimmed)
                    } else {
                        savedSearchResults = semantic
                    }
                } catch {
                    errorMessage = t("search.embeddingFailed")
                    savedSearchResults = try await conversationStore.searchKeyword(query: trimmed)
                }
            }
        } catch {
            errorMessage = errorText(error)
        }
    }

    func loadRecentSavedConversations() async {
        do {
            recentSavedConversations = try await conversationStore.listRecent(limit: 6)
        } catch {
            errorMessage = errorText(error)
        }
    }

    func fetchSavedConversation(id: Int64) async throws -> SavedConversation? {
        try await conversationStore.fetchConversation(id: id)
    }

    func clearSavedHistory() async throws {
        try await conversationStore.clearHistory()
        savedSearchResults = []
        recentSavedConversations = []
    }

    func refreshHistory(filter: HistoryFilter) async {
        historyLoading = true
        historyOffset = 0
        historyItems = []
        historyTotalCount = 0
        historyHasMore = false
        do {
            let range = historyTimeRange(for: filter)
            historyTotalCount = try await conversationStore.countHistory(
                keyword: filter.keyword,
                siteName: filter.siteName,
                startTime: range.start,
                endTime: range.end,
                codeOnly: filter.codeOnly
            )
            let page = try await conversationStore.listHistory(
                keyword: filter.keyword,
                siteName: filter.siteName,
                startTime: range.start,
                endTime: range.end,
                codeOnly: filter.codeOnly,
                limit: historyPageSize,
                offset: 0
            )
            historyItems = page
            historyOffset = page.count
            historyHasMore = historyOffset < historyTotalCount
        } catch {
            errorMessage = errorText(error)
        }
        historyLoading = false
    }

    func loadMoreHistory(filter: HistoryFilter) async {
        guard !historyLoading, historyHasMore else { return }
        historyLoading = true
        do {
            let range = historyTimeRange(for: filter)
            let page = try await conversationStore.listHistory(
                keyword: filter.keyword,
                siteName: filter.siteName,
                startTime: range.start,
                endTime: range.end,
                codeOnly: filter.codeOnly,
                limit: historyPageSize,
                offset: historyOffset
            )
            historyItems.append(contentsOf: page)
            historyOffset += page.count
            historyHasMore = historyOffset < historyTotalCount
        } catch {
            errorMessage = errorText(error)
        }
        historyLoading = false
    }

    func fetchHistoryConversation(id: Int64) async throws -> SavedConversation? {
        try await conversationStore.fetchConversation(id: id)
    }

    func copyHistory(ids: [Int64]) async {
        do {
            let conversations = try await conversationStore.fetchConversations(ids: ids)
            let body = conversations.map { exportBody(for: $0) }.joined(separator: "\n\n---\n\n")
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if pasteboard.setString(body, forType: .string) {
                toastMessage = t("history.copySuccess")
            } else {
                errorMessage = t("history.copyFail")
            }
        } catch {
            errorMessage = errorText(error)
        }
    }

    func exportHistory(ids: [Int64]) async {
        do {
            let conversations = try await conversationStore.fetchConversations(ids: ids)
            guard !conversations.isEmpty else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = t("history.exportConfirm")
            if panel.runModal() != .OK {
                return
            }
            guard let folder = panel.url else { return }
            for conversation in conversations {
                let fileName = exportFileName(for: conversation)
                let fileURL = folder.appendingPathComponent(fileName)
                let content = exportBody(for: conversation)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            toastMessage = t("history.exportSuccess")
        } catch {
            errorMessage = errorText(error)
        }
    }

    func deleteHistory(ids: [Int64], filter: HistoryFilter) async {
        do {
            try await conversationStore.deleteConversations(ids: ids)
            await loadRecentSavedConversations()
            await refreshHistory(filter: filter)
            toastMessage = t("history.deleteSuccess")
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func summarizeText(_ text: String, siteId: String?) async throws -> String {
        let trimmedKey = config.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = config.aiApiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            throw AppError(message: "未配置 API Key")
        }
        if trimmedModel.isEmpty {
            throw AppError(message: "未配置 Model")
        }

        let baseUrl = config.aiApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseUrl)/chat/completions")!

        var template = config.summaryPromptTemplate
        if let siteId, let site = siteById(siteId), !site.summaryPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            template = site.summaryPromptOverride
        }
        if template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            template = Storage.defaultSummaryPromptTemplate()
        }
        let languageLabel = I18nCatalog.shared.languageLabel(for: config.language)
        let prompt = buildSummaryPrompt(template: template, language: languageLabel, text: text)

        let body: [String: Any] = [
            "model": trimmedModel,
            "messages": [
                ["role": "system", "content": "你是一个擅长提炼上下文与约束的助手。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError(message: "请求失败")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: respData, encoding: .utf8) ?? ""
            throw AppError(message: "API 返回错误 \(http.statusCode): \(bodyText)")
        }

        let decoded = try JSONDecoder().decode(OpenAiChatResponse.self, from: respData)
        let content = decoded.choices.first?.message.content ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppError(message: "API 返回空内容")
        }
        return content
    }

    private var currentSearchMode: SearchMode {
        SearchMode(rawValue: config.searchMode) ?? .keyword
    }

    private func embeddingForText(_ text: String, mode: SearchMode) async throws -> [Float] {
        switch mode {
        case .semanticOffline:
            return try offlineEmbedding(for: text)
        case .semanticOnline:
            return try await onlineEmbedding(for: text)
        case .keyword:
            return []
        }
    }

    private func offlineEmbedding(for text: String) throws -> [Float] {
        let language = SupportedLanguage.fromConfig(config.language).nlLanguage
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            throw AppError(message: t("search.embeddingUnavailable"))
        }
        guard let vector = embedding.vector(for: text) else {
            throw AppError(message: t("search.embeddingFailed"))
        }
        return vector.map { Float($0) }
    }

    private func onlineEmbedding(for text: String) async throws -> [Float] {
        let trimmedKey = config.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = effectiveEmbeddingModel
        if trimmedKey.isEmpty {
            throw AppError(message: t("search.embeddingMissingKey"))
        }
        if trimmedModel.isEmpty {
            throw AppError(message: t("search.embeddingMissingModel"))
        }

        let baseUrl = config.aiApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseUrl)/embeddings")!
        let body: [String: Any] = [
            "model": trimmedModel,
            "input": text
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError(message: t("search.embeddingFailed"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: respData, encoding: .utf8) ?? ""
            throw AppError(message: "\(t("search.embeddingFailed")) (\(http.statusCode)): \(bodyText)")
        }

        let decoded = try JSONDecoder().decode(OpenAiEmbeddingResponse.self, from: respData)
        guard let embedding = decoded.data.first?.embedding else {
            throw AppError(message: t("search.embeddingFailed"))
        }
        return embedding.map { Float($0) }
    }

    private var effectiveEmbeddingModel: String {
        let embeddingModel = config.aiEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !embeddingModel.isEmpty {
            return embeddingModel
        }
        return config.aiApiModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildSummaryPrompt(template: String, language: String, text: String) -> String {
        var rendered = template.replacingOccurrences(of: "{language}", with: language)
        rendered = rendered.replacingOccurrences(of: "{text}", with: text)
        if !template.contains("{language}") {
            rendered += "\n\nLanguage: \(language)"
        }
        if !template.contains("{text}") {
            rendered += "\n\n\(text)"
        }
        return rendered
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func historyTimeRange(for filter: HistoryFilter) -> (start: UInt64?, end: UInt64?) {
        let calendar = Calendar.current
        let now = Date()
        var startDate: Date?
        var endDate: Date?

        switch filter.timePreset {
        case .all:
            break
        case .today:
            startDate = calendar.startOfDay(for: now)
            endDate = now
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)
            endDate = now
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now)
            endDate = now
        case .custom:
            if let start = filter.customStart {
                startDate = calendar.startOfDay(for: start)
            }
            if let end = filter.customEnd {
                if let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end)) {
                    endDate = endOfDay
                } else {
                    endDate = end
                }
            }
        }

        if let start = startDate, let end = endDate, end < start {
            startDate = end
            endDate = start
        }

        let startTime = startDate.map { UInt64($0.timeIntervalSince1970) }
        let endTime = endDate.map { UInt64($0.timeIntervalSince1970) }
        return (startTime, endTime)
    }

    private func exportBody(for conversation: SavedConversation) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(conversation.createdAt))
        let formatted = Self.historyDateFormatter.string(from: date)
        let markdown = conversation.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = markdown.isEmpty ? conversation.content : markdown
        let header = """
## \(conversation.siteName)
URL: \(conversation.url)
Time: \(formatted)

"""
        return header + body
    }

    private func exportFileName(for conversation: SavedConversation) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(conversation.createdAt))
        let formatted = Self.fileDateFormatter.string(from: date)
        let base = "\(conversation.siteName)_\(formatted)"
        let sanitized = base.replacingOccurrences(of: "[\\\\/:*?\\\"<>|]", with: "_", options: .regularExpression)
        return sanitized + ".md"
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private func firstSiteId(excluding siteId: String) -> String? {
        sitesOrdered().first { $0.id != siteId }?.id
    }
}

struct AppError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct OpenAiChatResponse: Codable {
    let choices: [OpenAiChoice]
}

private struct OpenAiChoice: Codable {
    let message: OpenAiMessage
}

private struct OpenAiMessage: Codable {
    let content: String
}

private struct OpenAiEmbeddingResponse: Codable {
    let data: [OpenAiEmbeddingItem]
}

private struct OpenAiEmbeddingItem: Codable {
    let embedding: [Double]
}
