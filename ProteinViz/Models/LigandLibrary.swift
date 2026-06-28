//
//  LigandLibrary.swift
//  ProteinViz
//

import Foundation

/// Friendly names for the most common ligands, cofactors, ions, and drug molecules
/// referenced by their 3-letter PDB residue code. Shared between the curated info sheet
/// and the Pencil-hover tooltip so labels match across the app.
enum LigandLibrary {
    /// Returns a human-readable name for the given PDB residue code, or nil when unknown.
    static func commonName(for residueCode: String) -> String? {
        commonNames[residueCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    static let commonNames: [String: String] = [
        // Heme and porphyrins
        "HEM": "Heme group (iron porphyrin)",
        "HEC": "Heme C",
        "HEA": "Heme A",

        // Nucleotides
        "ATP": "Adenosine triphosphate",
        "ADP": "Adenosine diphosphate",
        "AMP": "Adenosine monophosphate",
        "GTP": "Guanosine triphosphate",
        "GDP": "Guanosine diphosphate",

        // Coenzymes
        "NAD": "NAD+",
        "NAP": "NADP+",
        "FAD": "Flavin adenine dinucleotide",
        "FMN": "Flavin mononucleotide",
        "COA": "Coenzyme A",

        // Common ions
        "MG":  "Magnesium ion",
        "CA":  "Calcium ion",
        "ZN":  "Zinc ion",
        "FE":  "Iron ion",
        "MN":  "Manganese ion",
        "CU":  "Copper ion",
        "NA":  "Sodium ion",
        "K":   "Potassium ion",
        "CL":  "Chloride ion",
        "NI":  "Nickel ion",
        "CO":  "Cobalt ion",

        // Buffers and cryoprotectants
        "SO4": "Sulfate",
        "PO4": "Phosphate",
        "GOL": "Glycerol (cryoprotectant)",
        "EDO": "Ethylene glycol (cryoprotectant)",
        "PEG": "Polyethylene glycol",
        "MES": "MES buffer",
        "TRS": "TRIS buffer",
        "HEP": "HEPES buffer",

        // Anti-HIV drugs (for the 1RTD demo)
        "AZT": "Zidovudine (NRTI)",
        "EFZ": "Efavirenz (NNRTI)",
        "NVP": "Nevirapine (NNRTI)",
        "TFV": "Tenofovir (NRTI)"
    ]
}
