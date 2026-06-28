//
//  Protein.swift
//  ProteinViz
//

import Foundation
import simd

// MARK: - Bounding Box

struct ProteinBoundingBox: Hashable, Sendable {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    nonisolated var center: SIMD3<Float> {
        (minimum + maximum) * 0.5
    }

    nonisolated var size: SIMD3<Float> {
        maximum - minimum
    }

    nonisolated var radius: Float {
        max(size.x, max(size.y, size.z)) * 0.5
    }
}

// MARK: - Ligand Instance

/// One discrete ligand residue (e.g. a heme group, an ATP molecule, a magnesium ion).
/// Groups all atoms with the same chain / residueSeq / residueName and provides a centroid
/// suitable for anchoring a floating label.
struct LigandInstance: Identifiable, Hashable {
    let residueName: String
    let chainID: Character
    let residueSeq: Int
    let centroid: SIMD3<Float>

    var id: String { "\(String(chainID))|\(residueSeq)|\(residueName)" }
}

// MARK: - Protein

struct Protein: Hashable {
    let name: String
    let pdbID: String?
    let atoms: [Atom]
    let backboneAtoms: [Atom]
    let secondaryStructure: [SecondaryStructureElement]
    let chainColors: [Character: SIMD4<Float>]
    let boundingBox: ProteinBoundingBox
    let center: SIMD3<Float>

    var atomCount: Int {
        atoms.count
    }

    /// Counts of distinct ligand (HETATM) residues in the structure, e.g. `["HEM": 4]`
    /// for hemoglobin. Each unique (chainID, residueSeq, residueName) triplet counts once.
    var ligandResidueCounts: [String: Int] {
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for atom in atoms where atom.isLigand {
            let key = "\(String(atom.chainID))|\(atom.residueSeq)|\(atom.residueName)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            counts[atom.residueName, default: 0] += 1
        }
        return counts
    }

    /// One LigandInstance per discrete ligand residue, with a centroid for label anchoring.
    var ligandInstances: [LigandInstance] {
        let grouped = Dictionary(grouping: atoms.filter { $0.isLigand }) { atom in
            "\(String(atom.chainID))|\(atom.residueSeq)|\(atom.residueName)"
        }
        let instances: [LigandInstance] = grouped.compactMap { _, residueAtoms in
            guard let first = residueAtoms.first else { return nil }
            let sum = residueAtoms.reduce(SIMD3<Float>.zero) { $0 + $1.position }
            let centroid = sum / Float(residueAtoms.count)
            return LigandInstance(
                residueName: first.residueName,
                chainID: first.chainID,
                residueSeq: first.residueSeq,
                centroid: centroid
            )
        }
        return instances.sorted { $0.id < $1.id }
    }

    static func empty(name: String = "Untitled Protein") -> Protein {
        Protein(
            name: name,
            pdbID: nil,
            atoms: [],
            backboneAtoms: [],
            secondaryStructure: [],
            chainColors: [:],
            boundingBox: ProteinBoundingBox(minimum: .zero, maximum: .zero),
            center: .zero
        )
    }
}

// MARK: - Protein Construction

extension Protein {
    nonisolated init(name: String, pdbID: String? = nil, atoms: [Atom], secondaryStructure: [SecondaryStructureElement] = []) {
        if let firstAtom = atoms.first {
            var minimum = firstAtom.position
            var maximum = firstAtom.position

            for atom in atoms.dropFirst() {
                minimum = SIMD3<Float>(Swift.min(minimum.x, atom.position.x), Swift.min(minimum.y, atom.position.y), Swift.min(minimum.z, atom.position.z))
                maximum = SIMD3<Float>(Swift.max(maximum.x, atom.position.x), Swift.max(maximum.y, atom.position.y), Swift.max(maximum.z, atom.position.z))
            }

            let bounds = ProteinBoundingBox(minimum: minimum, maximum: maximum)
            let backbone = atoms.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == "CA" }
                .sorted { lhs, rhs in
                    if lhs.chainID == rhs.chainID { return lhs.residueSeq < rhs.residueSeq }
                    return lhs.chainID < rhs.chainID
                }

            let chainIDs = Array(Set(atoms.map { $0.chainID })).sorted()
            let palette: [SIMD4<Float>] = [
                SIMD4<Float>(0.33, 0.66, 1.00, 1),
                SIMD4<Float>(1.00, 0.42, 0.42, 1),
                SIMD4<Float>(0.40, 0.85, 0.60, 1),
                SIMD4<Float>(1.00, 0.80, 0.20, 1),
                SIMD4<Float>(0.80, 0.50, 1.00, 1),
                SIMD4<Float>(1.00, 0.60, 0.20, 1),
                SIMD4<Float>(0.40, 0.90, 0.95, 1),
                SIMD4<Float>(1.00, 0.55, 0.75, 1)
            ]
            var colors: [Character: SIMD4<Float>] = [:]
            for (index, chainID) in chainIDs.enumerated() {
                colors[chainID] = palette[index % palette.count]
            }

            self.name = name
            self.pdbID = pdbID
            self.atoms = atoms
            self.backboneAtoms = backbone
            self.secondaryStructure = secondaryStructure.isEmpty ? [] : secondaryStructure
            self.chainColors = colors
            self.boundingBox = bounds
            self.center = bounds.center
        } else {
            self.name = name
            self.pdbID = pdbID
            self.atoms = []
            self.backboneAtoms = []
            self.secondaryStructure = secondaryStructure
            self.chainColors = [:]
            self.boundingBox = ProteinBoundingBox(minimum: .zero, maximum: .zero)
            self.center = .zero
        }
    }
}
