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
    let protein: Protein
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
                    if !protein.ligandResidueCounts.isEmpty {
                        ligandsSection
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

    private var ligandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bound ligands & cofactors")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                let entries = protein.ligandResidueCounts
                    .sorted { lhs, rhs in
                        if lhs.value != rhs.value { return lhs.value > rhs.value }
                        return lhs.key < rhs.key
                    }
                ForEach(entries, id: \.key) { residueCode, count in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(verbatim: ligandDisplayLabel(code: residueCode, count: count))
                            .font(.body)
                    }
                }
            }
            Text("In ribbon mode, ligand atoms are drawn as CPK spheres on top of the backbone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ligandDisplayLabel(code: String, count: Int) -> String {
        let friendly = LigandLibrary.commonName(for: code)
        let countSuffix = count > 1 ? " × \(count)" : ""
        if let friendly {
            return "\(code) — \(friendly)\(countSuffix)"
        }
        return "\(code)\(countSuffix)"
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
