import AppKit
import SwiftUI

/// The capture history window: a searchable list of past captures with
/// per-row Re-copy / Show HUD / Delete. Captures-only and local-only.
struct HistoryView: View {
    let store: CaptureHistoryStore
    let onRecopy: (CaptureRecord, Representation) -> Void
    let onShowHUD: (CaptureRecord) -> Void

    @State private var records: [CaptureRecord] = []
    @State private var query = ""
    @State private var confirmingClear = false

    private var filtered: [CaptureRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return records }
        return records.filter {
            $0.searchableText.localizedCaseInsensitiveContains(trimmed)
                || ($0.source.appName ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { record in
                            HistoryRow(
                                record: record,
                                thumbnailURL: store.thumbnailURL(for: record.id),
                                representations: store.availableRepresentations(for: record),
                                onRecopy: { rep in onRecopy(record, rep) },
                                onShowHUD: { onShowHUD(record) },
                                onDelete: {
                                    store.delete(id: record.id)
                                    reload()
                                })
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 480)
        .onAppear(perform: reload)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search captured text, links, and entities", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(records.isEmpty ? "No captures yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if records.isEmpty {
                Text("Your last \(store.maxRecords) captures will appear here, stored locally.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(records.count) of \(store.maxRecords) captures · stored locally on this Mac")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Clear History") { confirmingClear = true }
                .controlSize(.small)
                .disabled(records.isEmpty)
                .confirmationDialog("Clear all capture history?",
                                    isPresented: $confirmingClear) {
                    Button("Clear \(records.count) Captures", role: .destructive) {
                        store.clear()
                        reload()
                    }
                } message: {
                    Text("Deletes all locally stored captures. This cannot be undone.")
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func reload() {
        records = store.records()
    }
}

private struct HistoryRow: View {
    let record: CaptureRecord
    let thumbnailURL: URL
    let representations: [Representation]
    let onRecopy: (Representation) -> Void
    let onShowHUD: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var previewLine: String {
        let canonical = record.axText.isEmpty ? record.ocrText : record.axText
        let firstLine = canonical
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return firstLine ?? "Image only"
    }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: previewLine)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(record.source.appName ?? "Unknown app")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(record.timestamp, format: .relative(presentation: .named))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    if !record.axText.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text("AX")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            Spacer(minLength: 12)
            if hovering {
                actionButtons
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering = $0 }
    }

    private var thumbnail: some View {
        Group {
            if let image = NSImage(contentsOf: thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 64, height: 44)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(representations) { rep in
                    Button(rep.title) { onRecopy(rep) }
                }
            } label: {
                Label("Re-copy as…", systemImage: "doc.on.clipboard")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Re-copy this capture to the clipboard")

            Button(action: onShowHUD) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Show the action HUD for this capture")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Delete this capture")
        }
    }
}
