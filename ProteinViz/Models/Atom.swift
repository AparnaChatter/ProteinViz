//
//  Atom.swift
//  ProteinViz
//

import Foundation
import simd

// MARK: - Atom

/// Atom represents a single atom parsed from a PDB `ATOM` or `HETATM` record.
struct Atom: Identifiable, Hashable {
    let serial: Int
    let name: String
    let residueName: String
    let chainID: Character
    let residueSeq: Int
    let position: SIMD3<Float>
    let element: String
    /// True when this atom came from a `HETATM` record (heterogen / ligand / cofactor).
    /// Crystallographic waters are filtered out before construction, so this flag really
    /// means "interesting non-protein residue" — heme, ATP, metal ions, drug molecules, etc.
    let isLigand: Bool

    var id: Int { serial }

    // MARK: - Color + Radius

    private var normalizedElement: String {
        let trimmed = element.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "" : String(trimmed.prefix(2))
    }

    /// CPK color for the atom's element.
    var cpkColor: SIMD4<Float> {
        switch normalizedElement {
        case "C":
            return SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        case "N":
            return SIMD4<Float>(0.2, 0.4, 1.0, 1.0)
        case "O":
            return SIMD4<Float>(1.0, 0.2, 0.2, 1.0)
        case "S":
            return SIMD4<Float>(1.0, 0.9, 0.1, 1.0)
        case "H":
            return SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        case "P":
            return SIMD4<Float>(1.0, 0.5, 0.0, 1.0)
        default:
            return SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
        }
    }

    /// Approximate van der Waals radius in Angstroms.
    var vanDerWaalsRadius: Float {
        switch normalizedElement {
        case "H":
            return 1.20
        case "C":
            return 1.70
        case "N":
            return 1.55
        case "O":
            return 1.52
        case "F":
            return 1.47
        case "P":
            return 1.80
        case "S":
            return 1.80
        case "CL":
            return 1.75
        case "BR":
            return 1.85
        case "I":
            return 1.98
        default:
            return 1.60
        }
    }
}
