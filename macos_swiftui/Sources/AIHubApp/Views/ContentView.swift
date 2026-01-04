import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    @State private var searchQuery = ""
    @State private var showSettings = false
    @State private var showAddSite = false
    @State private var showSiteSettings = false
    @State private var showSavedConversation = false
    @State private var isLoadingSavedConversation = false
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var toastHideWorkItem: DispatchWorkItem?
    @State private var siteForSettings: AiSite?
    @State private var alertItem: AlertItem?
    @State private var selectedConversation: SavedConversation?
    @State private var showTopBar = true
    @State private var isHoveringTopBar = false
    @State private var isHoveringTopBarReveal = false
    @State private var topBarHideWorkItem: DispatchWorkItem?
    @State private var showHome = false

    private let topBarRevealHeight: CGFloat = 6
    private let topBarHideDelay: TimeInterval = 1.2

    var body: some View {
        let overlayOpen = showSettings || showAddSite || showSiteSettings || showSavedConversation
        let homeVisible = showHome || model.currentSiteId.isEmpty
        let toolbarVisible = !model.config.toolbarAutoHide || showTopBar

        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                SidebarView(
                    searchQuery: $searchQuery,
                    savedResults: model.savedSearchResults,
                    showSettings: { showSettings = true },
                    showAddSite: { showAddSite = true },
                    showSiteSettings: { site in
                        siteForSettings = site
                        showSiteSettings = true
                    },
                    onSwitchSite: { siteId in
                        showHome = false
                        model.switchView(siteId)
                    },
                    onTogglePin: { siteId, pinned in
                        model.togglePin(siteId: siteId, pinned: pinned)
                    },
                    onRefreshSite: { siteId in
                        model.refreshSite(siteId)
                    },
                    onOpenSavedConversation: { preview in
                        openSavedConversation(preview)
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

                        if toolbarVisible {
                            TopBarView(
                                webViewManager: model.webViewManager,
                                onShowHome: {
                            showHome = true
                        },
                        onSaveConversation: {
                            Task { await model.saveCurrentConversation() }
                        },
                        onSwitchTab: { tabId in
                            showHome = false
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
                        if model.loading && !homeVisible {
                            ProgressView()
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.top, 6)
                        }

                        if homeVisible {
                            HomeView(
                                recentConversations: model.recentSavedConversations,
                                onAddSite: { showAddSite = true },
                                onOpenSettings: { showSettings = true },
                                onOpenConversation: { preview in
                                    openSavedConversation(preview)
                                }
                            )
                        } else {
                            webviewArea(opacity: overlayOpen ? 0 : 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if showToast, let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showToast)
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.message))
        }
        .onChange(of: searchQuery) { _, newValue in
            Task { await model.updateSavedSearchResults(query: newValue) }
        }
        .onChange(of: model.errorMessage) { _, newValue in
            guard let message = newValue else { return }
            alertItem = AlertItem(message: message)
            model.errorMessage = nil
        }
        .onChange(of: model.toastMessage) { _, newValue in
            guard let message = newValue else { return }
            toastMessage = message
            showToast = true
            model.toastMessage = nil
            toastHideWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showToast = false
                }
            }
            toastHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
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
        .sheet(isPresented: $showSavedConversation) {
            if isLoadingSavedConversation {
                SavedConversationLoadingView()
                    .environmentObject(model)
            } else if let conversation = selectedConversation {
                SavedConversationView(isPresented: $showSavedConversation, conversation: conversation)
                    .environmentObject(model)
            }
        }
    }

    private func updateTopBarVisibility() {
        guard model.config.toolbarAutoHide else {
            cancelTopBarHide()
            showTopBar = true
            return
        }
        if isHoveringTopBar || isHoveringTopBarReveal {
            showTopBarIfNeeded()
        } else {
            scheduleTopBarHide()
        }
    }

    private func showTopBarIfNeeded() {
        guard model.config.toolbarAutoHide else {
            showTopBar = true
            return
        }
        cancelTopBarHide()
        if !showTopBar {
            withAnimation(.easeInOut(duration: 0.18)) {
                showTopBar = true
            }
        }
    }

    private func scheduleTopBarHide() {
        guard model.config.toolbarAutoHide else { return }
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

    private func openSavedConversation(_ preview: SavedConversationPreview) {
        isLoadingSavedConversation = true
        selectedConversation = nil
        showSavedConversation = true
        Task {
            do {
                let loaded = try await model.fetchSavedConversation(id: preview.id)
                if let loaded {
                    selectedConversation = loaded
                } else {
                    showSavedConversation = false
                    model.errorMessage = model.t("search.loadFailed")
                }
            } catch {
                showSavedConversation = false
                model.errorMessage = errorText(error)
            }
            isLoadingSavedConversation = false
        }
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

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

private struct SavedConversationLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
        }
        .frame(width: 360, height: 200)
        .padding(20)
    }
}
