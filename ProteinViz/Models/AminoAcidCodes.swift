//
//  AminoAcidCodes.swift
//  ProteinViz
//

import Foundation

/// Translation between 3-letter PDB residue codes and 1-letter amino acid codes for the
/// sequence strip. Unknown codes (modified residues, non-standard amino acids) fall back
/// to "X" which keeps the strip's grid alignment intact.
enum AminoAcidCodes {
    static let threeToOne: [String: String] = [
        "ALA": "A", "ARG": "R", "ASN": "N", "ASP": "D",
        "CYS": "C", "GLU": "E", "GLN": "Q", "GLY": "G",
        "HIS": "H", "ILE": "I", "LEU": "L", "LYS": "K",
        "MET": "M", "PHE": "F", "PRO": "P", "SER": "S",
        "THR": "T", "TRP": "W", "TYR": "Y", "VAL": "V",
        // Common alternates
        "SEC": "U", // Selenocysteine
        "PYL": "O", // Pyrrolysine
        "ASX": "B", // Asparagine or aspartic acid
        "GLX": "Z"  // Glutamine or glutamic acid
    ]

    static func oneLetter(for residueCode: String) -> String {
        let key = residueCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return threeToOne[key] ?? "X"
    }

    /// True only for the 20 standard residues plus selenocysteine / pyrrolysine.
    static func isStandardAminoAcid(_ residueCode: String) -> Bool {
        let key = residueCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return threeToOne[key] != nil
    }
}
