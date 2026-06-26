//
//  SecondaryStructureElement.swift
//  ProteinViz
//

import Foundation

// MARK: - Secondary Structure Types

enum SecondaryStructureType: String, CaseIterable, Sendable {
    case helix
    case sheet
    case loop
}

// MARK: - Secondary Structure Element

struct SecondaryStructureElement: Hashable, Sendable {
    let type: SecondaryStructureType
    let chainID: Character
    let startResidueSeq: Int
    let endResidueSeq: Int
}
