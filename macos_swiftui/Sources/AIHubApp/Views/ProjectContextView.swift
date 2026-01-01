import AppKit
import SwiftUI

struct ProjectContextView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var isPresented: Bool

    @State private var selectedProjectId = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var summary = ""
    @State private var showCreate = false
    @State private var newProjectTitle = ""
    @State private var showDeleteAlert = false
    @State private var alertItem: AlertItem?
    @State private var isSaving = false
    @State private var isSummarizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("context.title"))
                .font(.headline)

            HStack(spacing: 10) {
                Picker(model.t("context.selectProject"), selection: $selectedProjectId) {
                    ForEach(model.listProjects()) { project in
                        Text(project.title).tag(project.id)
                    }
                }
                .frame(width: 220)

                Button(model.t("context.newProject")) {
                    showCreate = true
                }

                Button(model.t("context.deleteProject")) {
                    showDeleteAlert = true
                }
                .disabled(selectedProjectId.isEmpty)

                Spacer()

                Button(model.t("context.saveProject")) { saveProject() }
                    .disabled(selectedProjectId.isEmpty || isSaving)
                Button(model.t("context.autoSummarize")) { summarizeNotes() }
                    .disabled(selectedProjectId.isEmpty || isSummarizing)
                Button(model.t("context.copy")) { copyToClipboard() }
                    .disabled(selectedProjectId.isEmpty)
            }

            Divider()

            Form {
                TextField(model.t("context.projectName"), text: $title)
                TextEditor(text: $notes)
                    .frame(height: 140)
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text(model.t("context.notesPlaceholder"))
                                .foregroundStyle(.secondary)
                                .padding(6)
                        }
                    }
                TextEditor(text: $summary)
                    .frame(height: 120)
                    .overlay(alignment: .topLeading) {
                        if summary.isEmpty {
                            Text(model.t("context.summaryPlaceholder"))
                                .foregroundStyle(.secondary)
                                .padding(6)
                        }
                    }
            }

            HStack {
                Spacer()
                Button(model.t("common.close")) { isPresented = false }
            }
        }
        .padding(20)
        .frame(width: 860, height: 640)
        .onAppear { loadInitial() }
        .onChange(of: selectedProjectId) { _, newValue in
            loadProject(newValue)
        }
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.message))
        }
        .alert(model.t("context.deleteConfirmTitle"), isPresented: $showDeleteAlert) {
            Button(model.t("context.deleteProject"), role: .destructive) {
                deleteProject()
            }
            Button(model.t("settings.cancel"), role: .cancel) {}
        } message: {
            Text(model.t("context.deleteConfirmBody"))
        }
        .sheet(isPresented: $showCreate) {
            VStack(spacing: 12) {
                Text(model.t("context.createProject"))
                    .font(.headline)
                TextField(model.t("context.projectName"), text: $newProjectTitle)
                HStack {
                    Spacer()
                    Button(model.t("settings.cancel")) { showCreate = false }
                    Button(model.t("context.create")) { confirmCreate() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private func loadInitial() {
        let ensured = model.ensureActiveProjectId()
        selectedProjectId = ensured
        loadProject(ensured)
    }

    private func loadProject(_ projectId: String) {
        guard let project = model.loadProject(projectId: projectId) else { return }
        model.setActiveProject(projectId)
        title = project.title
        notes = project.notes
        summary = project.summary
    }

    private func confirmCreate() {
        let trimmed = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "默认项目" : trimmed
        let id = model.createProject(title: title)
        selectedProjectId = id
        loadProject(id)
        showCreate = false
        alertItem = AlertItem(message: model.t("context.created"))
    }

    private func deleteProject() {
        let id = selectedProjectId
        guard !id.isEmpty else { return }
        model.deleteProject(projectId: id)
        selectedProjectId = model.listProjects().first?.id ?? ""
        if !selectedProjectId.isEmpty {
            loadProject(selectedProjectId)
        } else {
            title = ""
            notes = ""
            summary = ""
        }
        alertItem = AlertItem(message: model.t("context.deleted"))
    }

    private func saveProject() {
        guard !selectedProjectId.isEmpty else { return }
        isSaving = true
        model.updateProject(projectId: selectedProjectId, title: title, notes: notes, summary: summary)
        isSaving = false
        alertItem = AlertItem(message: model.t("context.saved"))
    }

    private func summarizeNotes() {
        guard !selectedProjectId.isEmpty else { return }
        isSummarizing = true
        Task {
            defer { isSummarizing = false }
            do {
                let result = try await model.summarizeNotes(notes)
                summary = result
                saveProject()
            } catch {
                alertItem = AlertItem(message: error.localizedDescription)
            }
        }
    }

    private func copyToClipboard() {
        let text = buildCarryPrompt()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            alertItem = AlertItem(message: model.t("context.copySuccess"))
        }
    }

    private func buildCarryPrompt() -> String {
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = titleText.isEmpty ? "" : "\(model.t("context.projectName")): \(titleText)\n\n"
        let base = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(header)\(model.t("summary.copyPrefix"))\n\(base)\n\n\(model.t("summary.nextQuestion"))"
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
