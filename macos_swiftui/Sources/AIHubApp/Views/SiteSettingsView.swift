import SwiftUI

struct SiteSettingsView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var isPresented: Bool
    let site: AiSite?
    let onSubmit: (AiSite?) -> Void

    @State private var name = ""
    @State private var url = ""
    @State private var icon = "custom"
    @State private var summaryPromptOverride = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(siteTitle)
                .font(.headline)

            TextField(model.t("siteSettings.name"), text: $name)
            TextField(model.t("siteSettings.url"), text: $url)

            VStack(alignment: .leading, spacing: 8) {
                Text(model.t("siteSettings.icon"))
                    .font(.subheadline)
                IconPickerView(icon: $icon)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("siteSettings.summaryPromptOverride"))
                    .font(.subheadline)
                TextEditor(text: $summaryPromptOverride)
                    .frame(height: 120)
                HStack {
                    Text(model.t("settings.summaryPromptHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.t("siteSettings.useGlobalPrompt")) {
                        summaryPromptOverride = ""
                    }
                }
            }

            HStack {
                Spacer()
                Button(model.t("settings.cancel")) { isPresented = false }
                Button(model.t("settings.save")) {
                    guard var site = site else { return }
                    site.name = name
                    site.url = url
                    site.icon = icon
                    site.summaryPromptOverride = summaryPromptOverride
                    onSubmit(site)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { loadSite() }
    }

    private var siteTitle: String {
        if let site {
            return "\(model.t("siteSettings.title")) - \(site.name)"
        }
        return model.t("siteSettings.title")
    }

    private func loadSite() {
        guard let site else { return }
        name = site.name
        url = site.url
        icon = site.icon
        summaryPromptOverride = site.summaryPromptOverride
    }
}
