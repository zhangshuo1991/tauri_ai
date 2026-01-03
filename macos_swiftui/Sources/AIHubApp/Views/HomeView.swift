import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    let recentConversations: [SavedConversationPreview]
    let onAddSite: () -> Void
    let onOpenSettings: () -> Void
    let onOpenConversation: (SavedConversationPreview) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                actionRow
                recentSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("app.welcomeTitle"))
                    .font(.system(size: 22, weight: .bold))
                Text(model.t("app.welcomeSubtitle"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            HomeActionCard(
                title: model.t("home.action.addSite"),
                systemImage: "plus.circle",
                action: onAddSite
            )
            HomeActionCard(
                title: model.t("home.action.settings"),
                systemImage: "gearshape",
                action: onOpenSettings
            )
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("home.section.recent"))
                .font(.headline)

            if recentConversations.isEmpty {
                Text(model.t("home.section.empty"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(recentConversations) { item in
                        HomeRecentRow(item: item) {
                            onOpenConversation(item)
                        }
                    }
                }
            }
        }
    }
}

private struct HomeActionCard: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isHovering {
            return Color.primary.opacity(0.06)
        }
        return Color.primary.opacity(0.03)
    }
}

private struct HomeRecentRow: View {
    let item: SavedConversationPreview
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.siteName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer(minLength: 0)
                        Text(createdAtLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Text(item.snippet.isEmpty ? "-" : item.snippet)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var createdAtLabel: String {
        let date = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
