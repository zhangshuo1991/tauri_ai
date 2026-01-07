import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    let onClose: () -> Void

    @State private var keyword = ""
    @State private var selectedSite = ""
    @State private var timePreset: HistoryTimePreset = .all
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var codeOnly = false
    @State private var selectedIds: Set<Int64> = []
    @State private var selectedConversation: SavedConversation?
    @State private var isLoadingPreview = false
    @State private var showDeleteConfirm = false
    @State private var searchWorkItem: DispatchWorkItem?
    @State private var previewTask: Task<Void, Never>?

    private let sidebarWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            header
            SubtleDivider()
                .padding(.horizontal, 16)

            filterBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            SubtleDivider()
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                listPanel
                    .frame(width: sidebarWidth)
                SubtleDivider()
                previewPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SubtleDivider()
                .padding(.horizontal, 16)

            footerActions
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await refreshHistory() }
        }
        .onChange(of: keyword) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: selectedSite) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: timePreset) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: customStart) { _, _ in
            if timePreset == .custom {
                scheduleRefresh()
            }
        }
        .onChange(of: customEnd) { _, _ in
            if timePreset == .custom {
                scheduleRefresh()
            }
        }
        .onChange(of: codeOnly) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: selectedIds) { _, _ in
            updatePreview()
        }
        .alert(model.t("history.deleteConfirm"), isPresented: $showDeleteConfirm) {
            Button(model.t("history.deleteConfirmAction"), role: .destructive) {
                Task {
                    await model.deleteHistory(ids: Array(selectedIds), filter: currentFilter)
                    selectedIds.removeAll()
                    selectedConversation = nil
                }
            }
            Button(model.t("common.cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Text(model.t("history.title"))
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(model.t("history.close")) {
                onClose()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField(model.t("history.searchPlaceholder"), text: $keyword)
                    .textFieldStyle(SearchFieldStyle())
                    .frame(minWidth: 200)

                Picker(model.t("history.siteFilter"), selection: $selectedSite) {
                    Text(model.t("history.siteAll")).tag("")
                    ForEach(siteOptions, id: \.self) { site in
                        Text(site).tag(site)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Picker(model.t("history.timeFilter"), selection: $timePreset) {
                    ForEach(HistoryTimePreset.allCases) { preset in
                        Text(timePresetLabel(preset)).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Toggle(model.t("history.codeOnly"), isOn: $codeOnly)
                    .toggleStyle(.checkbox)

                Spacer()

                Text(String(format: model.t("history.totalCount"), model.historyTotalCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if timePreset == .custom {
                HStack(spacing: 12) {
                    DatePicker(model.t("history.customStart"), selection: $customStart, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker(model.t("history.customEnd"), selection: $customEnd, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    Spacer()
                }
            }
        }
    }

    private var listPanel: some View {
        List(selection: $selectedIds) {
            ForEach(model.historyItems, id: \.id) { item in
                HistoryRow(item: item)
                    .tag(item.id)
                    .onAppear {
                        if item.id == model.historyItems.last?.id {
                            Task { await model.loadMoreHistory(filter: currentFilter) }
                        }
                    }
            }
            if model.historyLoading && model.historyItems.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if model.historyHasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("history.previewTitle"))
                .font(.system(size: 14, weight: .semibold))

            if isLoadingPreview {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            } else if let conversation = selectedConversation {
                VStack(alignment: .leading, spacing: 8) {
                    previewInfoRow(title: model.t("history.previewSite"), value: conversation.siteName)
                    previewInfoRow(title: model.t("history.previewTime"), value: formattedDate(conversation.createdAt))
                    previewInfoRow(title: model.t("history.previewUrl"), value: conversation.url.isEmpty ? "-" : conversation.url)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                SubtleDivider()

                MarkdownTextView(markdown: displayMarkdown(for: conversation))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            } else {
                Spacer()
                Text(model.t("history.previewPlaceholder"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerActions: some View {
        HStack {
            Button(model.t("history.copy")) {
                Task { await model.copyHistory(ids: Array(selectedIds)) }
            }
            .buttonStyle(.bordered)
            .disabled(selectedIds.isEmpty)

            Button(model.t("history.export")) {
                Task { await model.exportHistory(ids: Array(selectedIds)) }
            }
            .buttonStyle(.bordered)
            .disabled(selectedIds.isEmpty)

            Button(model.t("history.delete")) {
                showDeleteConfirm = true
            }
            .buttonStyle(.bordered)
            .disabled(selectedIds.isEmpty)

            Spacer()
        }
    }

    private var siteOptions: [String] {
        let names = model.config.sites.map { $0.name }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private var currentFilter: HistoryFilter {
        HistoryFilter(
            keyword: keyword,
            siteName: selectedSite.isEmpty ? nil : selectedSite,
            timePreset: timePreset,
            customStart: timePreset == .custom ? customStart : nil,
            customEnd: timePreset == .custom ? customEnd : nil,
            codeOnly: codeOnly
        )
    }

    private func refreshHistory() async {
        selectedIds.removeAll()
        selectedConversation = nil
        await model.refreshHistory(filter: currentFilter)
    }

    private func scheduleRefresh() {
        searchWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task { await refreshHistory() }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func updatePreview() {
        previewTask?.cancel()
        guard let selectedId = model.historyItems.first(where: { selectedIds.contains($0.id) })?.id else {
            selectedConversation = nil
            return
        }
        isLoadingPreview = true
        previewTask = Task {
            defer { isLoadingPreview = false }
            do {
                selectedConversation = try await model.fetchHistoryConversation(id: selectedId)
            } catch {
                model.errorMessage = errorText(error)
            }
        }
    }

    private func displayMarkdown(for conversation: SavedConversation) -> String {
        let markdown = conversation.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !markdown.isEmpty {
            return markdown
        }
        return conversation.content
    }

    private func previewInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .lineLimit(1)
        }
    }

    private func formattedDate(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return Self.dateFormatter.string(from: date)
    }

    private func timePresetLabel(_ preset: HistoryTimePreset) -> String {
        switch preset {
        case .all:
            return model.t("history.timeAll")
        case .today:
            return model.t("history.timeToday")
        case .last7Days:
            return model.t("history.timeLast7")
        case .last30Days:
            return model.t("history.timeLast30")
        case .custom:
            return model.t("history.timeCustom")
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct HistoryRow: View {
    let item: SavedConversationPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(item.siteName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.createdAt))))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(item.snippet)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
