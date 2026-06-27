//
//  CuratedProtein.swift
//  ProteinViz
//

import Foundation
import simd

// MARK: - Manifest Schema

struct CuratedManifest: Codable, Hashable {
    let version: Int
    let proteins: [CuratedProteinEntry]
}

struct CuratedProteinEntry: Codable, Hashable, Identifiable {
    let pdbID: String
    let displayName: String
    let category: String
    let summary: String
    let function: String
    let keyDomains: [String]
    let fileName: String
    let initialRotationDegrees: [Float]?
    let initialZoom: Float?
    let tryThis: String?

    var id: String { pdbID }

    enum CodingKeys: String, CodingKey {
        case pdbID = "pdb_id"
        case displayName = "display_name"
        case category
        case summary
        case function
        case keyDomains = "key_domains"
        case fileName = "file_name"
        case initialRotationDegrees = "initial_rotation_degrees"
        case initialZoom = "initial_zoom"
        case tryThis = "try_this"
    }

    /// Public RCSB structure page URL for this entry.
    var rcsbStructureURL: URL? {
        URL(string: "https://www.rcsb.org/structure/\(pdbID)")
    }

    /// Direct download URL for the PDB file from RCSB.
    var rcsbDownloadURL: URL? {
        URL(string: "https://files.rcsb.org/download/\(pdbID).pdb")
    }
}

// MARK: - Errors

enum CuratedLibraryError: LocalizedError {
    case manifestMissing
    case manifestDecode(Error)
    case pdbMissing(String)

    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "curated.json was not found in the app bundle."
        case .manifestDecode(let error):
            return "Failed to decode curated.json: \(error.localizedDescription)"
        case .pdbMissing(let fileName):
            return "Missing bundled PDB file: \(fileName)."
        }
    }
}

// MARK: - Loader

struct CuratedLibraryLoader {
    static func loadManifest() throws -> CuratedManifest {
        guard let url = Bundle.main.url(forResource: "curated", withExtension: "json") else {
            throw CuratedLibraryError.manifestMissing
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CuratedManifest.self, from: data)
        } catch let decodeError {
            throw CuratedLibraryError.manifestDecode(decodeError)
        }
    }

    /// Looks up the bundled PDB URL for a curated entry, returning nil if the file
    /// hasn't been added to the project's Resources yet.
    static func bundleURL(for entry: CuratedProteinEntry) -> URL? {
        let baseName = (entry.fileName as NSString).deletingPathExtension
        let pathExt = (entry.fileName as NSString).pathExtension
        let ext = pathExt.isEmpty ? "pdb" : pathExt
        return Bundle.main.url(forResource: baseName, withExtension: ext)
    }

    static func loadProtein(for entry: CuratedProteinEntry) async throws -> Protein {
        guard let url = bundleURL(for: entry) else {
            throw CuratedLibraryError.pdbMissing(entry.fileName)
        }
        return try await PDBParser.parse(from: url)
    }
}

// MARK: - Camera Hint

extension CuratedProteinEntry {
    /// Returns a quaternion built from the manifest's optional Euler-degree triplet,
    /// or nil if no initial orientation was specified.
    var initialRotationQuaternion: simd_quatf? {
        guard let degrees = initialRotationDegrees, degrees.count == 3 else { return nil }
        let toRad: (Float) -> Float = { $0 * .pi / 180.0 }
        let qx = simd_quatf(angle: toRad(degrees[0]), axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: toRad(degrees[1]), axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: toRad(degrees[2]), axis: SIMD3<Float>(0, 0, 1))
        return simd_normalize(qz * qy * qx)
    }
}
