import SwiftUI

struct TopBarView: View {
    @EnvironmentObject private var model: AppModel

    @ObservedObject var webViewManager: WebViewManager

    let onShowHome: () -> Void
    let onSaveConversation: () -> Void
    let onSwitchTab: (String) -> Void
    let onCloseTab: (String) -> Void
    let onToggleSplit: (Bool) -> Void
    let onUpdateSplitRatio: (Double) -> Void
    let onUpdateLeftTab: (String?) -> Void
    let onUpdateRightTab: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // Action Buttons Group
                HStack(spacing: 4) {
                    Button(action: onShowHome) {
                        Label(model.t("top.home"), systemImage: "house")
                    }
                    .buttonStyle(ToolbarButtonStyle())

                    ToolbarDivider()

                    Button(action: onSaveConversation) {
                        Label(model.t("top.save"), systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .disabled(model.currentSiteId.isEmpty)

                    ToolbarDivider()

                    Toggle(isOn: Binding(
                        get: { model.layoutMode == .split },
                        set: { onToggleSplit($0) }
                    )) {
                        Label(model.t("top.split"), systemImage: "square.split.2x1")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(model.tabs.count < 2)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )

                Spacer()

                // Split View Controls
                if model.layoutMode == .split {
                    HStack(spacing: 8) {
                        let options = model.tabs.map { tab in
                            PickerItem(id: tab.id, label: tabTitle(tab))
                        }

                        Picker(selection: Binding(
                            get: { model.leftTabId ?? "" },
                            set: { onUpdateLeftTab($0.isEmpty ? nil : $0) }
                        )) {
                            ForEach(options) { item in
                                Text(item.label).tag(item.id)
                            }
                        } label: {
                            Text("")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .labelsHidden()

                        Picker(selection: Binding(
                            get: { model.rightTabId ?? "" },
                            set: { onUpdateRightTab($0.isEmpty ? nil : $0) }
                        )) {
                            ForEach(options) { item in
                                Text(item.label).tag(item.id)
                            }
                        } label: {
                            Text("")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .labelsHidden()

                        Slider(value: Binding(
                            get: { model.splitRatio },
                            set: { onUpdateSplitRatio($0) }
                        ), in: 0.2...0.8, step: 0.05)
                        .frame(width: 100)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Tab Bar
            if !model.tabs.isEmpty {
                SubtleDivider()
                    .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.tabs) { tab in
                            let progress = webViewManager.tabProgress[tab.id] ?? 0
                            let isLoading = webViewManager.loadingTabs.contains(tab.id)
                            let statusText = tabStatusLabel(for: tab.id)
                            TabItemView(
                                title: tabTitle(tab),
                                statusText: statusText,
                                isLoading: isLoading,
                                progress: progress,
                                isActive: visibleTabIds.contains(tab.id),
                                onSelect: { onSwitchTab(tab.id) },
                                onClose: { onCloseTab(tab.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            SubtleDivider()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var visibleTabIds: Set<String> {
        if model.layoutMode == .split {
            return Set([model.leftTabId, model.rightTabId].compactMap { $0 })
        }
        let active = model.activeTabId.isEmpty ? model.currentSiteId : model.activeTabId
        return active.isEmpty ? [] : [active]
    }

    private func tabTitle(_ tab: TabInfo) -> String {
        let siteName = model.config.sites.first(where: { $0.id == tab.siteId })?.name ?? tab.siteId
        let count = model.tabs.filter { $0.siteId == tab.siteId }.count
        if count <= 1 {
            return siteName
        }
        if tab.id == tab.siteId {
            return "\(siteName) (1)"
        }
        return "\(siteName) (\(model.t("top.multiSession")))"
    }

    private func tabStatusLabel(for tabId: String) -> String? {
        guard let issue = webViewManager.tabLoadIssues[tabId] else { return nil }
        switch issue {
        case .failed:
            return model.t("tab.loadFailed")
        case .timeout:
            return model.t("tab.loadTimeout")
        }
    }

    private struct PickerItem: Identifiable {
        let id: String
        let label: String
    }
}

// MARK: - Tab Item View
private struct TabItemView: View {
    let title: String
    let statusText: String?
    let isLoading: Bool
    let progress: Double
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if isLoading {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 30)
                            .frame(height: 2)
                    }
                }
            }
            .buttonStyle(.plain)

            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
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

// MARK: - Toolbar Divider
private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 16)
    }
}
