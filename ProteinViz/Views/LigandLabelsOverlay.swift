//
//  LigandLabelsOverlay.swift
//  ProteinViz
//

import SwiftUI

// MARK: - Ligand Labels Overlay

/// Floats a small residue-code capsule (e.g. "HEM", "ATP", "FE") over each ligand cluster.
/// Re-projects on every gesture change so the labels track the structure during rotation.
struct LigandLabelsOverlay: View {
    let protein: Protein
    @ObservedObject var gestureHandler: GestureHandler
    let renderer: MetalRenderer

    var body: some View {
        GeometryReader { geo in
            ForEach(protein.ligandInstances) { ligand in
                if let position = renderer.projectProteinPointToScreen(ligand.centroid, viewSize: geo.size) {
                    LigandLabel(text: friendlyShortLabel(for: ligand))
                        .position(position)
                }
            }
        }
    }

    /// Single short token shown in the capsule. Single-atom ions (FE, MG, ZN, …) keep their
    /// symbol; everything else uses the PDB residue code.
    private func friendlyShortLabel(for ligand: LigandInstance) -> String {
        let trimmed = ligand.residueName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : trimmed
    }
}

// MARK: - Capsule Label

private struct LigandLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.orange.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
    }
}
