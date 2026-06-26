//
//  Annotation.swift
//  ProteinViz
//

import Combine
import Foundation
import simd

// MARK: - Protein Annotation

/// A label anchored to a position in the protein's normalized coordinate space
/// (post-centering and post-scaling, so the label tracks the structure under rotate/zoom/pan).
struct ProteinAnnotation: Identifiable, Hashable {
    let id: UUID
    var anchorWorld: SIMD3<Float>
    var text: String
    var atomSerial: Int?
    var residueName: String?
    var chainID: Character?
    var residueSeq: Int?

    init(id: UUID = UUID(),
         anchorWorld: SIMD3<Float>,
         text: String,
         atomSerial: Int? = nil,
         residueName: String? = nil,
         chainID: Character? = nil,
         residueSeq: Int? = nil) {
        self.id = id
        self.anchorWorld = anchorWorld
        self.text = text
        self.atomSerial = atomSerial
        self.residueName = residueName
        self.chainID = chainID
        self.residueSeq = residueSeq
    }

    var subtitle: String {
        var parts: [String] = []
        if let residueName, !residueName.isEmpty { parts.append(residueName) }
        if let chainID { parts.append("Chain \(chainID)") }
        if let residueSeq { parts.append("#\(residueSeq)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Annotation Store

@MainActor
final class AnnotationStore: ObservableObject {
    @Published private var annotationsByProtein: [String: [ProteinAnnotation]] = [:]

    func annotations(for protein: Protein) -> [ProteinAnnotation] {
        annotationsByProtein[Self.key(for: protein)] ?? []
    }

    func add(_ annotation: ProteinAnnotation, to protein: Protein) {
        var list = annotationsByProtein[Self.key(for: protein)] ?? []
        list.append(annotation)
        annotationsByProtein[Self.key(for: protein)] = list
    }

    func remove(_ id: UUID, from protein: Protein) {
        let k = Self.key(for: protein)
        var list = annotationsByProtein[k] ?? []
        list.removeAll(where: { $0.id == id })
        annotationsByProtein[k] = list
    }

    func update(_ id: UUID, text: String, in protein: Protein) {
        let k = Self.key(for: protein)
        var list = annotationsByProtein[k] ?? []
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].text = text
            annotationsByProtein[k] = list
        }
    }

    func clearAll(in protein: Protein) {
        annotationsByProtein[Self.key(for: protein)] = []
    }

    private static func key(for protein: Protein) -> String {
        protein.pdbID ?? protein.name
    }
}
