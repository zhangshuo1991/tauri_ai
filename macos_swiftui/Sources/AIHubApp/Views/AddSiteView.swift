import SwiftUI

struct AddSiteView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var isPresented: Bool
    let onSubmit: (String, String, String) -> Void

    @State private var name = ""
    @State private var url = ""
    @State private var icon = "custom"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(model.t("addSite.title"))
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 16)

            // Form Content
            VStack(alignment: .leading, spacing: 16) {
                // Name Field
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.t("siteSettings.name"), systemImage: "textformat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField(model.t("siteSettings.name"), text: $name)
                        .textFieldStyle(FormFieldStyle())
                }

                // URL Field
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.t("siteSettings.url"), systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField(model.t("siteSettings.url"), text: $url)
                        .textFieldStyle(FormFieldStyle())
                }

                // Icon Picker
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.t("siteSettings.icon"), systemImage: "photo")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    IconPickerView(icon: $icon)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

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

                Button(model.t("addSite.add")) {
                    onSubmit(name, url, icon)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 420)
    }
}
