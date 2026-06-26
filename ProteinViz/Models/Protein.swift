//
//  Protein.swift
//  ProteinViz
//

import Foundation
import simd

// MARK: - Bounding Box

struct ProteinBoundingBox: Hashable {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    var center: SIMD3<Float> {
        (minimum + maximum) * 0.5
    }

    var size: SIMD3<Float> {
        maximum - minimum
    }

    var radius: Float {
        max(size.x, max(size.y, size.z)) * 0.5
    }
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
    init(name: String, pdbID: String? = nil, atoms: [Atom], secondaryStructure: [SecondaryStructureElement] = []) {
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
