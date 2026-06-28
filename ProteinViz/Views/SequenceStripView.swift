//
//  SequenceStripView.swift
//  ProteinViz
//

import SwiftUI

// MARK: - Sequence Strip

/// Horizontal residue strip pinned to the bottom of the detail view. Shows one-letter
/// amino acid codes per chain. Tap a chip to highlight its atoms in the renderer. The
/// strip auto-scrolls to the currently-selected residue when the selection changes from
/// elsewhere (e.g. Pencil hover in a future iteration).
struct SequenceStripView: View {
    let protein: Protein
    @Binding var selectedResidueKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chains
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Sequence")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let selected = selectedResidue {
                Text("\(selected.residueName) \(selected.residueSeq) · Chain \(String(selected.chainID))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    selectedResidueKey = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("Tap a residue to highlight it")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var chains: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(protein.residuesByChain, id: \.chainID) { chainData in
                        chainRow(chainID: chainData.chainID, residues: chainData.residues)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 110)
            .onChange(of: selectedResidueKey) { _, newKey in
                guard let key = newKey else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
        }
    }

    private func chainRow(chainID: Character, residues: [Residue]) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text("\(String(chainID))")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
                .padding(.trailing, 4)
            ForEach(residues) { residue in
                ResidueChip(
                    residue: residue,
                    isSelected: residue.id == selectedResidueKey
                )
                .id(residue.id)
                .onTapGesture {
                    if selectedResidueKey == residue.id {
                        selectedResidueKey = nil
                    } else {
                        selectedResidueKey = residue.id
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var selectedResidue: Residue? {
        guard let key = selectedResidueKey else { return nil }
        return protein.residues.first(where: { $0.id == key })
    }
}

// MARK: - Residue Chip

private struct ResidueChip: View {
    let residue: Residue
    let isSelected: Bool

    private let chipWidth: CGFloat = 16
    private let chipHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 1) {
            Text(residue.oneLetterCode)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? Color.black : Color.primary)
            if residue.residueSeq % 10 == 0 {
                Text("\(residue.residueSeq)")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.7) : Color.secondary)
            } else if residue.residueSeq % 5 == 0 {
                Circle()
                    .fill(isSelected ? Color.black.opacity(0.45) : Color.secondary.opacity(0.6))
                    .frame(width: 3, height: 3)
            } else {
                Text(" ")
                    .font(.system(size: 7))
            }
        }
        .frame(width: chipWidth, height: chipHeight)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? Color.yellow : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(isSelected ? Color.yellow : Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}
