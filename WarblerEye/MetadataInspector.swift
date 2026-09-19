//
//  MetadataInspector.swift
//  WarblerEye
//

import SwiftUI

/// The metadata panel, listing every property the current file declares.
///
/// The "Photo" group at the top gathers the fields usually wanted; below it
/// the file's own dictionaries appear as ImageIO reports them, so nothing is
/// hidden behind the friendlier rendering.
struct MetadataInspector: View {
    let info: ImageInfo?
    let filename: String?

    /// Groups the user has folded away this session, keyed by name so the
    /// state survives paging to another image.
    @State private var collapsed: Set<String> = []

    var body: some View {
        Group {
            if let groups = info?.metadata, !groups.isEmpty {
                list(groups)
            } else {
                ContentUnavailableView(
                    "No Metadata",
                    systemImage: "tag",
                    description: Text(
                        info == nil
                            ? "Open an image to see its metadata."
                            : "This file declares no metadata."
                    )
                )
            }
        }
        .inspectorColumnWidth(min: 260, ideal: 340, max: 600)
    }

    private func list(_ groups: [MetadataGroup]) -> some View {
        List {
            ForEach(groups) { group in
                Section(isExpanded: expansion(of: group)) {
                    ForEach(Array(group.fields.enumerated()), id: \.element.id) { position, field in
                        VStack(alignment: .leading, spacing: 0) {
                            row(field)
                            // A rule between rows, but not below the last one,
                            // where the section break already separates them.
                            if position < group.fields.count - 1 {
                                Divider().opacity(0.75)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    }
                } header: {
                    Text(group.name)
                }
            }
        }
        .listStyle(.sidebar)
        .textSelection(.enabled)
        .navigationTitle(filename ?? "Metadata")
    }

    /// Whether a group is open, defaulting to closed for the bulky ones.
    private func expansion(of group: MetadataGroup) -> Binding<Bool> {
        Binding(
            get: { group.isNoise ? collapsed.contains(group.name) : !collapsed.contains(group.name) },
            set: { open in
                let folded = group.isNoise ? !open : open
                if folded {
                    collapsed.remove(group.name)
                } else {
                    collapsed.insert(group.name)
                }
            }
        )
    }

    /// Name above value, rather than side by side: EXIF tag names are long
    /// enough that a two-column layout would truncate one side or the other in
    /// a panel this narrow.
    ///
    /// The name is the quieter of the two: it labels the row, while the value
    /// is what is actually being read.
    private func row(_ field: MetadataGroup.Field) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let reading = field.reading {
                // The meaning leads, with the file's own value kept beside it
                // so the panel stays a truthful record of what was written.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reading)
                        .font(.system(size: 13, weight: .semibold))
                    Text(field.value)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(field.value.isEmpty ? "—" : field.value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(field.isNoise ? .secondary : .primary)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
