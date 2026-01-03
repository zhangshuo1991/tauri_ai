import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var searchQuery: String

    let savedResults: [SavedConversationPreview]
    let showSettings: () -> Void
    let showAddSite: () -> Void
    let showSiteSettings: (AiSite) -> Void
    let onSwitchSite: (String) -> Void
    let onTogglePin: (String, Bool) -> Void
    let onRefreshSite: (String) -> Void
    let onOpenSavedConversation: (SavedConversationPreview) -> Void
    let onClearCache: (String) -> Void
    let onRemoveSite: (String) -> Void
    let onMovePinned: (IndexSet, Int) -> Void
    let onMoveUnpinned: (IndexSet, Int, [AiSite]) -> Void

    private let minWidth: Double = 64
    private let compactThreshold: Double = 100

    private var isCompact: Bool {
        model.sidebarWidth <= compactThreshold
    }

    var body: some View {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pinned = model.pinnedSites().filter { matches($0, query: query) }
        let recents = model.recentSites().filter { matches($0, query: query) && !model.config.pinnedSiteIds.contains($0.id) }
        let showRecent = query.isEmpty && !recents.isEmpty
        let recentShown = Array(recents.prefix(5))
        let recentSet = Set(recentShown.map { $0.id })
        let unpinned = model.unpinnedSites(excluding: showRecent ? recentSet : []).filter { matches($0, query: query) }
        let showSaved = !query.isEmpty && !savedResults.isEmpty

        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                if isCompact {
                    // Compact mode: just an icon
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    HStack {
                        Text("AI Hub")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    TextField(model.t("sidebar.searchPlaceholder"), text: $searchQuery)
                        .textFieldStyle(SearchFieldStyle())
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }

                SubtleDivider()
                    .padding(.horizontal, isCompact ? 8 : 14)
            }

            // Site List
            ScrollView {
                VStack(spacing: 6) {
                    if showRecent {
                        SidebarSection(title: model.t("sidebar.sectionRecent"), isCompact: isCompact) {
                            ForEach(recentShown, id: \.id) { site in
                                SidebarRow(site: site, isActive: model.currentSiteId == site.id, isCompact: isCompact)
                                    .contextMenu { contextMenu(for: site) }
                                    .onTapGesture { onSwitchSite(site.id) }
                            }
                        }
                    }

                    if showSaved {
                        SidebarSection(title: model.t("sidebar.sectionSaved"), isCompact: isCompact) {
                            ForEach(savedResults, id: \.id) { item in
                                SavedConversationRow(item: item, isCompact: isCompact)
                                    .onTapGesture { onOpenSavedConversation(item) }
                            }
                        }
                    }

                    SidebarSection(title: "", isCompact: isCompact) {
                        ForEach(pinned, id: \.id) { site in
                            SidebarRow(site: site, isActive: model.currentSiteId == site.id, isCompact: isCompact)
                                .contextMenu { contextMenu(for: site) }
                                .onTapGesture { onSwitchSite(site.id) }
                        }
                    }

                    if !unpinned.isEmpty {
                        SidebarSection(title: "", isCompact: isCompact) {
                            ForEach(unpinned, id: \.id) { site in
                                SidebarRow(site: site, isActive: model.currentSiteId == site.id, isCompact: isCompact)
                                    .contextMenu { contextMenu(for: site) }
                                    .onTapGesture { onSwitchSite(site.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, isCompact ? 8 : 12)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            // Bottom Actions
            VStack(spacing: isCompact ? 6 : 4) {
                SubtleDivider()
                    .padding(.horizontal, isCompact ? 8 : 14)
                    .padding(.bottom, 10)

                if isCompact {
                    // Compact mode: icon only buttons
                    CompactActionButton(icon: "plus.circle", action: showAddSite)
                    CompactActionButton(icon: "gearshape", action: showSettings)
                    CompactActionButton(icon: model.isDarkTheme ? "sun.max" : "moon", action: toggleTheme)
                    CompactActionButton(icon: "sidebar.right", action: toggleSidebar)
                } else {
                    Button(action: showAddSite) {
                        Label(model.t("sidebar.addSite"), systemImage: "plus.circle")
                    }
                    .buttonStyle(SidebarActionButtonStyle())

                    Button(action: showSettings) {
                        Label(model.t("sidebar.settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(SidebarActionButtonStyle())

                    Button(action: toggleTheme) {
                        Label(model.isDarkTheme ? model.t("sidebar.light") : model.t("sidebar.dark"), systemImage: model.isDarkTheme ? "sun.max" : "moon")
                    }
                    .buttonStyle(SidebarActionButtonStyle())

                    Button(action: toggleSidebar) {
                        Label(model.t("sidebar.collapse"), systemImage: "sidebar.left")
                    }
                    .buttonStyle(SidebarActionButtonStyle())
                }
            }
            .labelStyle(SidebarLabelStyle())
            .padding(.horizontal, isCompact ? 6 : 8)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    private func toggleTheme() {
        model.setTheme(model.isDarkTheme ? "light" : "dark")
    }

    private func toggleSidebar() {
        let nextWidth = model.sidebarWidth <= minWidth ? model.sidebarExpandedWidth : minWidth
        model.updateSidebarWidth(nextWidth)
    }

    @ViewBuilder
    private func contextMenu(for site: AiSite) -> some View {
        Button(model.t("sidebar.menu.siteSettings")) { showSiteSettings(site) }
        Button(model.config.pinnedSiteIds.contains(site.id) ? model.t("sidebar.menu.unpin") : model.t("sidebar.menu.pin")) {
            let pinned = !model.config.pinnedSiteIds.contains(site.id)
            onTogglePin(site.id, pinned)
        }
        Divider()
        Button(model.t("sidebar.menu.refresh")) { onRefreshSite(site.id) }
        Button(model.t("sidebar.menu.clearCache")) { onClearCache(site.id) }
        if !site.builtin {
            Divider()
            Button(role: .destructive) { onRemoveSite(site.id) } label: {
                Text(model.t("sidebar.menu.removeSite"))
            }
        }
    }

    private func matches(_ site: AiSite, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return site.name.lowercased().contains(query) || site.url.lowercased().contains(query)
    }
}

// MARK: - Sidebar Section
private struct SidebarSection<Content: View>: View {
    let title: String
    let isCompact: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty && !isCompact {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            content()
        }
    }
}

// MARK: - Sidebar Row
private struct SidebarRow: View {
    let site: AiSite
    let isActive: Bool
    let isCompact: Bool
    @State private var isHovering = false

    var body: some View {
        if isCompact {
            // Compact mode: icon only, centered
            SiteIconView(iconKey: site.icon, siteId: site.id, size: 32, cornerRadius: 8)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(backgroundColor)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                }
                .help(site.name)
        } else {
            // Expanded mode: icon + name
            HStack(spacing: 12) {
                SiteIconView(iconKey: site.icon, siteId: site.id, size: 32, cornerRadius: 8)
                    .foregroundColor(isActive ? .accentColor : .primary.opacity(0.7))
                Text(site.name)
                    .font(.system(size: 14, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .primary : .primary.opacity(0.85))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.12)
        }
        if isHovering {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }
}

// MARK: - Saved Conversation Row
private struct SavedConversationRow: View {
    let item: SavedConversationPreview
    let isCompact: Bool
    @State private var isHovering = false

    var body: some View {
        if isCompact {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .help(item.siteName)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.siteName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(item.snippet.isEmpty ? "-" : item.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
}

// MARK: - Compact Action Button
private struct CompactActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.primary.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
