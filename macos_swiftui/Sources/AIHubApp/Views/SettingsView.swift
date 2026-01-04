import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var isPresented: Bool

    @State private var draft = SettingsDraft()
    @State private var showClearKeyAlert = false
    @State private var showResetAlert = false
    @State private var showClearHistoryAlert = false
    @State private var showClearHistoryDone = false

    private let minSidebarWidth: Double = 64
    private let fieldLabelWidth: CGFloat = 90
    private let fieldHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(model.t("settings.title"))
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Tab View
            TabView {
                appearanceTab
                    .tabItem {
                        Label(model.t("settings.tabs.appearance"), systemImage: "paintbrush")
                    }
                layoutTab
                    .tabItem {
                        Label(model.t("settings.tabs.layout"), systemImage: "sidebar.squares.left")
                    }
                languageTab
                    .tabItem {
                        Label(model.t("settings.tabs.language"), systemImage: "globe")
                    }
                aiTab
                    .tabItem {
                        Label(model.t("settings.tabs.ai"), systemImage: "sparkles")
                    }
                advancedTab
                    .tabItem {
                        Label(model.t("settings.tabs.advanced"), systemImage: "gearshape.2")
                    }
            }
            .frame(width: 520, height: 340)

            SubtleDivider()
                .padding(.horizontal, 16)

            // Footer Buttons
            HStack {
                Spacer()
                Button(model.t("settings.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(model.t("settings.save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!isDirty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
        .onAppear { syncDraft() }
        .alert(model.t("settings.clearApiKeyConfirm"), isPresented: $showClearKeyAlert) {
            Button(model.t("settings.clearKey"), role: .destructive) {
                draft.aiApiKey = ""
                draft.clearApiKey = true
            }
            Button(model.t("settings.cancel"), role: .cancel) {}
        }
        .alert(model.t("settings.resetNavTitle"), isPresented: $showResetAlert) {
            Button(model.t("settings.resetNavConfirm"), role: .destructive) {
                model.resetNavigation()
            }
            Button(model.t("settings.cancel"), role: .cancel) {}
        } message: {
            Text(model.t("settings.resetNavContent"))
        }
        .alert(model.t("settings.clearHistoryTitle"), isPresented: $showClearHistoryAlert) {
            Button(model.t("settings.clearHistoryConfirm"), role: .destructive) {
                Task {
                    do {
                        try await model.clearSavedHistory()
                        showClearHistoryDone = true
                    } catch {
                        model.errorMessage = errorText(error)
                    }
                }
            }
            Button(model.t("settings.cancel"), role: .cancel) {}
        } message: {
            Text(model.t("settings.clearHistoryContent"))
        }
        .alert(model.t("settings.clearHistorySuccess"), isPresented: $showClearHistoryDone) {
            Button(model.t("common.close"), role: .cancel) {}
        }
    }

    private var appearanceTab: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { draft.theme == "dark" },
                    set: { draft.theme = $0 ? "dark" : "light" }
                )) {
                    Label(model.t("settings.darkTheme"), systemImage: "moon.fill")
                }
            } header: {
                Text(model.t("settings.tabs.appearance"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var layoutTab: some View {
        Form {
            Section {
                Toggle(isOn: $draft.sidebarExpanded) {
                    Label(model.t("settings.sidebarExpand"), systemImage: "sidebar.left")
                }

                if draft.sidebarExpanded {
                    HStack {
                        Label(model.t("settings.sidebarWidth"), systemImage: "arrow.left.and.right")
                        Spacer()
                        Slider(value: $draft.sidebarWidth, in: minSidebarWidth...260, step: 4)
                            .frame(width: 160)
                        Text(String(format: "%.0f", draft.sidebarWidth))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                HStack {
                    Label(model.t("settings.sidebarIconSize"), systemImage: "square.grid.2x2")
                    Spacer()
                    Slider(value: $draft.sidebarIconSize, in: 15...30, step: 1)
                        .frame(width: 160)
                    Text(String(format: "%.0f", draft.sidebarIconSize))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Label(model.t("settings.sidebarTextSize"), systemImage: "textformat.size")
                    Spacer()
                    Slider(value: $draft.sidebarTextSize, in: 15...30, step: 1)
                        .frame(width: 160)
                    Text(String(format: "%.0f", draft.sidebarTextSize))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            } header: {
                Text(model.t("settings.tabs.layout"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var languageTab: some View {
        Form {
            Section {
                Picker(selection: $draft.language) {
                    ForEach(model.supportedLanguages()) { lang in
                        Text(languageLabel(lang)).tag(lang)
                    }
                } label: {
                    Label(model.t("settings.language"), systemImage: "character.bubble")
                }

                Text(model.t("settings.languageHint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(model.t("settings.tabs.language"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var aiTab: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    SettingsFieldRow(title: "Base URL", labelWidth: fieldLabelWidth) {
                        TextField("", text: $draft.aiApiBaseUrl)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: fieldHeight)
                    }

                    SettingsFieldRow(title: "Model", labelWidth: fieldLabelWidth) {
                        TextField("", text: $draft.aiApiModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: fieldHeight)
                    }

                    SettingsFieldRow(title: "API Key", labelWidth: fieldLabelWidth) {
                        SecureField("", text: $draft.aiApiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: fieldHeight)
                    }

                    SettingsFieldRow(title: model.t("settings.embeddingModel"), labelWidth: fieldLabelWidth) {
                        TextField("", text: $draft.aiEmbeddingModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: fieldHeight)
                    }

                    SettingsFieldRow(title: model.t("settings.searchMode"), labelWidth: fieldLabelWidth) {
                        Picker(selection: $draft.searchMode) {
                            Text(model.t("settings.searchMode.keyword")).tag(SearchMode.keyword.rawValue)
                            Text(model.t("settings.searchMode.semanticOffline")).tag(SearchMode.semanticOffline.rawValue)
                            Text(model.t("settings.searchMode.semanticOnline")).tag(SearchMode.semanticOnline.rawValue)
                        } label: {
                            Text("")
                        }
                        .pickerStyle(.menu)
                        .frame(height: fieldHeight)
                    }
                }

                Button(role: .destructive) {
                    showClearKeyAlert = true
                } label: {
                    Label(model.t("settings.clearKey"), systemImage: "key.slash")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("API")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t("settings.summaryPromptTemplate"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draft.summaryPromptTemplate)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 120)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                        )

                    HStack {
                        Text(model.t("settings.summaryPromptHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(model.t("settings.resetToDefault")) {
                            draft.summaryPromptTemplate = ""
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            } header: {
                Text("Prompt")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var advancedTab: some View {
        Form {
            Section {
                Toggle(isOn: $draft.toolbarAutoHide) {
                    Label(model.t("settings.toolbarAutoHide"), systemImage: "rectangle.topthird.inset.filled")
                }

                Toggle(isOn: $draft.autoSaveEnabled) {
                    Label(model.t("settings.autoSaveEnabled"), systemImage: "clock.arrow.circlepath")
                }

                HStack {
                    Label(model.t("settings.autoSaveInterval"), systemImage: "timer")
                    Spacer()
                    Slider(value: $draft.autoSaveInterval, in: 10...300, step: 5)
                        .frame(width: 160)
                    Text(String(format: model.t("settings.autoSaveIntervalValue"), Int(draft.autoSaveInterval)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!draft.autoSaveEnabled)
            } header: {
                Text(model.t("settings.section.behavior"))
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.t("settings.resetNavContent"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label(model.t("settings.resetNavButton"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text(model.t("settings.tabs.advanced"))
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.t("settings.clearHistoryContent"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showClearHistoryAlert = true
                    } label: {
                        Label(model.t("settings.clearHistoryButton"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text(model.t("settings.clearHistoryTitle"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func syncDraft() {
        draft.theme = model.config.theme
        draft.sidebarExpanded = model.config.sidebarWidth > minSidebarWidth
        draft.sidebarWidth = model.config.sidebarWidth > minSidebarWidth ? model.config.sidebarWidth : model.sidebarExpandedWidth
        draft.sidebarIconSize = model.config.sidebarIconSize
        draft.sidebarTextSize = model.config.sidebarTextSize
        draft.toolbarAutoHide = model.config.toolbarAutoHide
        draft.autoSaveEnabled = model.config.autoSaveEnabled
        draft.autoSaveInterval = model.config.autoSaveInterval
        draft.language = SupportedLanguage.fromConfig(model.config.language)
        draft.aiApiBaseUrl = model.config.aiApiBaseUrl
        draft.aiApiModel = model.config.aiApiModel
        draft.aiApiKey = ""
        draft.aiEmbeddingModel = model.config.aiEmbeddingModel
        draft.searchMode = model.config.searchMode
        draft.summaryPromptTemplate = model.config.summaryPromptTemplate
        draft.clearApiKey = false
    }

    private var isDirty: Bool {
        let nextWidth = draft.sidebarExpanded ? max(minSidebarWidth, draft.sidebarWidth) : minSidebarWidth
        return draft.theme != model.config.theme ||
            draft.language.rawValue != model.config.language ||
            nextWidth != model.config.sidebarWidth ||
            draft.sidebarIconSize != model.config.sidebarIconSize ||
            draft.sidebarTextSize != model.config.sidebarTextSize ||
            draft.toolbarAutoHide != model.config.toolbarAutoHide ||
            draft.autoSaveEnabled != model.config.autoSaveEnabled ||
            draft.autoSaveInterval != model.config.autoSaveInterval ||
            draft.aiApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines) != model.config.aiApiBaseUrl ||
            draft.aiApiModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.config.aiApiModel ||
            draft.aiEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.config.aiEmbeddingModel ||
            draft.searchMode != model.config.searchMode ||
            draft.summaryPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines) != model.config.summaryPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines) ||
            !draft.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draft.clearApiKey
    }

    private func save() {
        model.setTheme(draft.theme)

        let width = draft.sidebarExpanded ? max(minSidebarWidth, draft.sidebarWidth) : minSidebarWidth
        model.updateSidebarWidth(width)
        model.updateSidebarItemSizes(iconSize: draft.sidebarIconSize, textSize: draft.sidebarTextSize)

        model.setToolbarAutoHide(draft.toolbarAutoHide)
        model.updateAutoSaveSettings(enabled: draft.autoSaveEnabled, interval: draft.autoSaveInterval)

        model.setLanguage(draft.language)
        model.updateAiSettings(
            baseUrl: draft.aiApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            model: draft.aiApiModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: draft.aiApiKey,
            clearKey: draft.clearApiKey,
            embeddingModel: draft.aiEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        model.updateSearchMode(SearchMode(rawValue: draft.searchMode) ?? .keyword)
        model.updateSummaryPromptTemplate(draft.summaryPromptTemplate)
        syncDraft()
        isPresented = false
    }

    private func languageLabel(_ language: SupportedLanguage) -> String {
        switch language {
        case .zhCN:
            return "中文"
        case .en:
            return "English"
        case .ja:
            return "日本語"
        case .ko:
            return "한국어"
        case .es:
            return "Español"
        case .fr:
            return "Français"
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private struct SettingsFieldRow<Content: View>: View {
    let title: String
    let labelWidth: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: labelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsDraft {
    var theme = "dark"
    var sidebarExpanded = true
    var sidebarWidth: Double = 180
    var sidebarIconSize: Double = 28
    var sidebarTextSize: Double = 15
    var toolbarAutoHide = true
    var autoSaveEnabled = true
    var autoSaveInterval: Double = 30
    var language: SupportedLanguage = .zhCN
    var aiApiBaseUrl = ""
    var aiApiModel = ""
    var aiApiKey = ""
    var aiEmbeddingModel = ""
    var searchMode = SearchMode.keyword.rawValue
    var summaryPromptTemplate = ""
    var clearApiKey = false
}
