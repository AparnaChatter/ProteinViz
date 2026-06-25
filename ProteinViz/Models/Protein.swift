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
    let atoms: [Atom]
    let boundingBox: ProteinBoundingBox
    let center: SIMD3<Float>

    var atomCount: Int {
        atoms.count
    }

    static func empty(name: String = "Untitled Protein") -> Protein {
        Protein(
            name: name,
            atoms: [],
            boundingBox: ProteinBoundingBox(minimum: .zero, maximum: .zero),
            center: .zero
        )
    }
}

// MARK: - Protein Construction

extension Protein {
    init(name: String, atoms: [Atom]) {
        if let firstAtom = atoms.first {
            var minimum = firstAtom.position
            var maximum = firstAtom.position

            for atom in atoms.dropFirst() {
                minimum = SIMD3<Float>(Swift.min(minimum.x, atom.position.x), Swift.min(minimum.y, atom.position.y), Swift.min(minimum.z, atom.position.z))
                maximum = SIMD3<Float>(Swift.max(maximum.x, atom.position.x), Swift.max(maximum.y, atom.position.y), Swift.max(maximum.z, atom.position.z))
            }

            let bounds = ProteinBoundingBox(minimum: minimum, maximum: maximum)
            self.name = name
            self.atoms = atoms
            self.boundingBox = bounds
            self.center = bounds.center
        } else {
            self.name = name
            self.atoms = []
            self.boundingBox = ProteinBoundingBox(minimum: .zero, maximum: .zero)
            self.center = .zero
        }
    }
}
