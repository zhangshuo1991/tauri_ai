import Combine
import Foundation
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
    @Published var loading = false

    let webViewManager = WebViewManager()

    private var cancellables = Set<AnyCancellable>()
    private let storage = Storage.shared

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

    func updateAiSettings(baseUrl: String, model: String, apiKey: String, clearKey: Bool) {
        updateConfig { config in
            let trimmedBase = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            config.aiApiBaseUrl = trimmedBase.isEmpty ? "https://api.openai.com/v1" : trimmedBase
            config.aiApiModel = model
            if clearKey {
                config.aiApiKey = ""
            } else if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.aiApiKey = apiKey
            }
        }
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
        layoutMode = .single
        leftTabId = nil
        rightTabId = nil
        activeTabId = tabId
        currentSiteId = siteId
        ensureTabExists(tabId: tabId, siteId: siteId)
        updateRecentSite(siteId)
        updateLastActive(tabId: tabId, siteId: siteId)
    }

    func switchView(_ siteId: String) {
        layoutMode = .single
        leftTabId = nil
        rightTabId = nil
        activeTabId = siteId
        currentSiteId = siteId
        ensureTabExists(tabId: siteId, siteId: siteId)
        updateRecentSite(siteId)
        updateLastActive(tabId: siteId, siteId: siteId)
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
        if sanitized.aiApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sanitized.aiApiBaseUrl = "https://api.openai.com/v1"
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
