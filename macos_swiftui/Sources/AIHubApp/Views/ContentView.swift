import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    @State private var searchQuery = ""
    @State private var showSettings = false
    @State private var showAddSite = false
    @State private var showSiteSettings = false
    @State private var showSummary = false
    @State private var showProjects = false
    @State private var summaryText = ""
    @State private var siteForSettings: AiSite?
    @State private var alertItem: AlertItem?
    @State private var showTopBar = true
    @State private var isHoveringTopBar = false
    @State private var isHoveringTopBarReveal = false
    @State private var topBarHideWorkItem: DispatchWorkItem?

    private let topBarRevealHeight: CGFloat = 6
    private let topBarHideDelay: TimeInterval = 1.2

    var body: some View {
        let overlayOpen = showSettings || showAddSite || showSiteSettings || showSummary || showProjects

        HStack(spacing: 0) {
            SidebarView(
                searchQuery: $searchQuery,
                showSettings: { showSettings = true },
                showAddSite: { showAddSite = true },
                showSiteSettings: { site in
                    siteForSettings = site
                    showSiteSettings = true
                },
                onSwitchSite: { siteId in
                    model.switchView(siteId)
                },
                onTogglePin: { siteId, pinned in
                    model.togglePin(siteId: siteId, pinned: pinned)
                },
                onRefreshSite: { siteId in
                    model.refreshSite(siteId)
                },
                onClearCache: { siteId in
                    Task { await model.clearCache(for: siteId) }
                },
                onRemoveSite: { siteId in
                    model.removeSite(siteId: siteId)
                },
                onMovePinned: { offsets, destination in
                    model.updatePinnedOrder(fromOffsets: offsets, toOffset: destination)
                },
                onMoveUnpinned: { offsets, destination, current in
                    model.updateSiteOrder(fromOffsets: offsets, toOffset: destination, currentUnpinned: current)
                }
            )
            .frame(width: model.sidebarWidth)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Color.clear
                        .frame(height: topBarRevealHeight)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringTopBarReveal = hovering
                            updateTopBarVisibility()
                        }

                    if showTopBar {
                        TopBarView(
                            webViewManager: model.webViewManager,
                            showProjects: { showProjects = true },
                            onCreateTab: {
                                guard !model.currentSiteId.isEmpty else { return }
                                model.createTab(for: model.currentSiteId)
                            },
                            onSummarize: {
                                Task {
                                    do {
                                        let summary = try await model.summarizeActiveTab()
                                        summaryText = summary
                                        showSummary = true
                                    } catch {
                                        model.errorMessage = errorText(error)
                                    }
                                }
                            },
                            onSwitchTab: { tabId in
                                model.switchToTab(tabId)
                            },
                            onCloseTab: { tabId in
                                model.closeTab(tabId)
                            },
                            onToggleSplit: { enabled in
                                do {
                                    try model.setSplitEnabled(enabled)
                                } catch {
                                    model.errorMessage = errorText(error)
                                }
                            },
                            onUpdateSplitRatio: { ratio in
                                model.updateSplitRatio(ratio)
                            },
                            onUpdateLeftTab: { tabId in
                                do {
                                    try model.updateSplitTabs(left: tabId, right: model.rightTabId)
                                    model.activeTabId = tabId ?? model.activeTabId
                                } catch {
                                    model.errorMessage = errorText(error)
                                }
                            },
                            onUpdateRightTab: { tabId in
                                do {
                                    try model.updateSplitTabs(left: model.leftTabId, right: tabId)
                                    model.activeTabId = tabId ?? model.activeTabId
                                } catch {
                                    model.errorMessage = errorText(error)
                                }
                            }
                        )
                        .onHover { hovering in
                            isHoveringTopBar = hovering
                            updateTopBarVisibility()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: showTopBar)

                ZStack(alignment: .top) {
                    if model.loading {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }

                    if model.currentSiteId.isEmpty {
                        WelcomeView()
                    } else {
                        webviewArea(opacity: overlayOpen ? 0 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.message))
        }
        .onChange(of: model.errorMessage) { _, newValue in
            guard let message = newValue else { return }
            alertItem = AlertItem(message: message)
            model.errorMessage = nil
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
                .environmentObject(model)
        }
        .sheet(isPresented: $showAddSite) {
            AddSiteView(isPresented: $showAddSite) { name, url, icon in
                do {
                    try model.addSite(name: name, url: url, icon: icon)
                } catch {
                    model.errorMessage = errorText(error)
                }
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showSiteSettings) {
            SiteSettingsView(isPresented: $showSiteSettings, site: siteForSettings) { updated in
                guard let updated else { return }
                do {
                    try model.updateSite(
                        siteId: updated.id,
                        name: updated.name,
                        url: updated.url,
                        icon: updated.icon,
                        summaryPromptOverride: updated.summaryPromptOverride
                    )
                } catch {
                    model.errorMessage = errorText(error)
                }
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showSummary) {
            SummaryView(isPresented: $showSummary, summary: $summaryText)
                .environmentObject(model)
        }
        .sheet(isPresented: $showProjects) {
            ProjectContextView(isPresented: $showProjects)
                .environmentObject(model)
        }
    }

    private func updateTopBarVisibility() {
        if isHoveringTopBar || isHoveringTopBarReveal {
            showTopBarIfNeeded()
        } else {
            scheduleTopBarHide()
        }
    }

    private func showTopBarIfNeeded() {
        cancelTopBarHide()
        if !showTopBar {
            withAnimation(.easeInOut(duration: 0.18)) {
                showTopBar = true
            }
        }
    }

    private func scheduleTopBarHide() {
        guard showTopBar else { return }
        cancelTopBarHide()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                showTopBar = false
            }
        }
        topBarHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + topBarHideDelay, execute: workItem)
    }

    private func cancelTopBarHide() {
        topBarHideWorkItem?.cancel()
        topBarHideWorkItem = nil
    }

    @ViewBuilder
    private func webviewArea(opacity: Double) -> some View {
        if model.layoutMode == .split, let left = model.leftTabId, let right = model.rightTabId {
            GeometryReader { proxy in
                let leftWidth = max(100, proxy.size.width * model.splitRatio)
                HStack(spacing: 0) {
                    if let leftView = model.webViewForTab(left) {
                        leftView
                            .id(left)
                            .frame(width: leftWidth)
                    }
                    if let rightView = model.webViewForTab(right) {
                        rightView
                            .id(right)
                            .frame(width: max(100, proxy.size.width - leftWidth))
                    }
                }
            }
            .opacity(opacity)
        } else {
            if let activeView = model.webViewForTab(model.activeTabId.isEmpty ? model.currentSiteId : model.activeTabId) {
                activeView
                    .id(model.activeTabId.isEmpty ? model.currentSiteId : model.activeTabId)
                    .opacity(opacity)
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Text("🚀")
                .font(.system(size: 40))
            Text(model.t("app.welcomeTitle"))
                .font(.title2)
            Text(model.t("app.welcomeSubtitle"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
