//
//  CuratedProteinInfoSheet.swift
//  ProteinViz
//

import SwiftUI

// MARK: - Curated Protein Info Sheet

/// Tutorial-grade info panel for a curated protein. Shows the manifest's category, summary,
/// detailed function paragraph, key domains, a "Try this" feature hint, and an RCSB link.
struct CuratedProteinInfoSheet: View {
    let entry: CuratedProteinEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    summarySection
                    functionSection
                    if !entry.keyDomains.isEmpty {
                        keyDomainsSection
                    }
                    if let tryThis = entry.tryThis, !tryThis.isEmpty {
                        tryThisSection(text: tryThis)
                    }
                    rcsbFooter
                }
                .padding(20)
            }
            .navigationTitle(entry.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.category.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(entry.summary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("PDB \(entry.pdbID)", systemImage: "atom")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var functionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Function")
                .font(.headline)
            Text(entry.function)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyDomainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key domains")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.keyDomains, id: \.self) { domain in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(domain)
                            .font(.body)
                    }
                }
            }
        }
    }

    private func tryThisSection(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Try this")
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.45), lineWidth: 1)
        )
    }

    private var rcsbFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let url = entry.rcsbStructureURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open on RCSB PDB", systemImage: "safari")
                        .font(.callout)
                }
            }
        }
    }
}
