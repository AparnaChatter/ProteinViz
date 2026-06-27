//
//  PDBParser.swift
//  ProteinViz
//

import Foundation
import simd

// MARK: - Parser Errors

enum PDBParserError: LocalizedError {
    case unreadableFile
    case noAtomsFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected PDB file could not be read."
        case .noAtomsFound:
            return "No atom records were found in the PDB file."
        }
    }
}

// MARK: - PDB Parser

struct PDBParser {
    static func parse(from url: URL) async throws -> Protein {
        try await Task.detached(priority: .userInitiated) {
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw PDBParserError.unreadableFile
            }

            let lines = text.components(separatedBy: .newlines)
            let pdbID = Self.parsePDBID(from: lines) ?? url.deletingPathExtension().lastPathComponent.uppercased()
            var atoms: [Atom] = []
            atoms.reserveCapacity(min(lines.count, 5_000))
            var secondaryStructure: [SecondaryStructureElement] = []

            for line in lines {
                if line.hasPrefix("ATOM") {
                    guard let atom = Self.parseAtom(from: line, isLigand: false) else { continue }
                    if atom.element.uppercased() == "H" { continue }
                    atoms.append(atom)
                } else if line.hasPrefix("HETATM") {
                    guard let atom = Self.parseAtom(from: line, isLigand: true) else { continue }
                    if atom.element.uppercased() == "H" { continue }
                    if Self.isWaterResidue(atom.residueName) { continue }
                    atoms.append(atom)
                } else if line.hasPrefix("HELIX") {
                    if let element = Self.parseHelix(from: line) {
                        secondaryStructure.append(element)
                    }
                } else if line.hasPrefix("SHEET") {
                    if let element = Self.parseSheet(from: line) {
                        secondaryStructure.append(element)
                    }
                }
            }

            guard !atoms.isEmpty else {
                throw PDBParserError.noAtomsFound
            }

            let proteinName = pdbID
            return Protein(name: proteinName, pdbID: pdbID, atoms: atoms, secondaryStructure: secondaryStructure)
        }.value
    }

    // MARK: - Record Parsing

    nonisolated private static func parsePDBID(from lines: [String]) -> String? {
        for line in lines where line.hasPrefix("HEADER") {
            if let id = substring(in: line, start: 63, end: 66)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                return id.uppercased()
            }
        }
        return nil
    }

    nonisolated private static func parseHelix(from line: String) -> SecondaryStructureElement? {
        guard
            let chain = characterField(in: line, start: 20),
            let startSeq = intField(in: line, start: 22, end: 25),
            let endSeq = intField(in: line, start: 34, end: 37)
        else {
            return nil
        }
        return SecondaryStructureElement(type: .helix, chainID: chain, startResidueSeq: startSeq, endResidueSeq: endSeq)
    }

    nonisolated private static func parseSheet(from line: String) -> SecondaryStructureElement? {
        guard
            let chain = characterField(in: line, start: 22),
            let startSeq = intField(in: line, start: 23, end: 26),
            let endSeq = intField(in: line, start: 34, end: 37)
        else {
            return nil
        }
        return SecondaryStructureElement(type: .sheet, chainID: chain, startResidueSeq: startSeq, endResidueSeq: endSeq)
    }

    // MARK: - Water filtering

    nonisolated private static let waterResidueNames: Set<String> = ["HOH", "WAT", "H2O", "DOD", "TIP", "TIP3", "TP3"]

    nonisolated private static func isWaterResidue(_ residueName: String) -> Bool {
        waterResidueNames.contains(residueName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    // MARK: - Atom Parsing

    nonisolated private static func parseAtom(from line: String, isLigand: Bool) -> Atom? {
        guard
            let serial = intField(in: line, start: 7, end: 11),
            let name = stringField(in: line, start: 13, end: 16, preserveSpaces: false),
            let residueName = stringField(in: line, start: 18, end: 20, preserveSpaces: false),
            let chainChar = characterField(in: line, start: 22),
            let residueSeq = intField(in: line, start: 23, end: 26),
            let x = floatField(in: line, start: 31, end: 38),
            let y = floatField(in: line, start: 39, end: 46),
            let z = floatField(in: line, start: 47, end: 54)
        else {
            return nil
        }

        let elementField = stringField(in: line, start: 77, end: 78, preserveSpaces: false) ?? ""
        let element: String
        if !elementField.isEmpty {
            element = elementField.uppercased()
        } else {
            let fallback = name.trimmingCharacters(in: .whitespacesAndNewlines)
            element = fallback.isEmpty ? "" : String(fallback.prefix(1)).uppercased()
        }

        return Atom(
            serial: serial,
            name: name,
            residueName: residueName,
            chainID: chainChar,
            residueSeq: residueSeq,
            position: SIMD3<Float>(x, y, z),
            element: element,
            isLigand: isLigand
        )
    }

    // MARK: - Fixed Width Helpers

    nonisolated private static func stringField(in line: String, start: Int, end: Int, preserveSpaces: Bool) -> String? {
        guard let raw = substring(in: line, start: start, end: end) else {
            return nil
        }

        let trimmed = preserveSpaces ? raw : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func characterField(in line: String, start: Int) -> Character? {
        guard let raw = substring(in: line, start: start, end: start) else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first ?? Character(" ")
    }

    nonisolated private static func intField(in line: String, start: Int, end: Int) -> Int? {
        guard let raw = substring(in: line, start: start, end: end) else {
            return nil
        }

        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated private static func floatField(in line: String, start: Int, end: Int) -> Float? {
        guard let raw = substring(in: line, start: start, end: end) else {
            return nil
        }

        return Float(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated private static func substring(in line: String, start: Int, end: Int) -> String? {
        guard start > 0, end >= start else {
            return nil
        }

        let length = (line as NSString).length
        guard length >= start else {
            return nil
        }

        let startIndex = start - 1
        let actualLength = min(end, length) - startIndex
        return (line as NSString).substring(with: NSRange(location: startIndex, length: actualLength))
    }
}
