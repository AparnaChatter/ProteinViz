//
//  RibbonGeometryBuilder.swift
//  ProteinViz
//

import Foundation
import simd

// MARK: - Ribbon Geometry Error

enum RibbonGeometryError: LocalizedError {
    case insufficientBackbone

    var errorDescription: String? {
        switch self {
        case .insufficientBackbone:
            return "The protein does not contain enough backbone atoms to build a ribbon."
        }
    }
}

// MARK: - Ribbon Geometry Builder

struct RibbonGeometryBuilder {
    private struct ProfilePoint {
        let position: SIMD2<Float>
        let normal: SIMD2<Float>
    }

    nonisolated static func build(protein: Protein, colorMode: ColorMode) throws -> (vertices: [RibbonVertex], indices: [UInt32]) {
        guard protein.backboneAtoms.count >= 2 else {
            throw RibbonGeometryError.insufficientBackbone
        }

        let splineSubdivisions = 8
        let profileCount = 8
        let chainGroups = Dictionary(grouping: protein.backboneAtoms, by: { $0.chainID })
        var vertices: [RibbonVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(protein.backboneAtoms.count * splineSubdivisions * profileCount)

        var vertexBase: UInt32 = 0
        for chainID in chainGroups.keys.sorted() {
            guard let group = chainGroups[chainID] else { continue }
            let chainAtoms = group.sorted { $0.residueSeq < $1.residueSeq }
            guard chainAtoms.count >= 2 else { continue }

            let controlPoints = chainAtoms.map(\.position)
            let splinePoints = buildPolylinePoints(controlPoints: controlPoints, subdivisions: splineSubdivisions)
            guard splinePoints.count >= 2 else { continue }

            // Chain-local indices of residues that mark the C-terminal end of a sheet
            var sheetEndResidueIndices = Set<Int>()
            for element in protein.secondaryStructure where element.type == .sheet && element.chainID == chainID {
                if let endIdx = chainAtoms.firstIndex(where: { $0.residueSeq == element.endResidueSeq }) {
                    sheetEndResidueIndices.insert(endIdx)
                }
            }

            // Parallel-transport frame seed
            let seedTangent = simd_normalize(splinePoints[1] - splinePoints[0])
            var previousBinormal = initialBinormal(for: seedTangent)

            // Emit a ring at every spline point except the last (we need a forward tangent)
            let ringCount = splinePoints.count - 1
            for index in 0..<ringCount {
                let current = splinePoints[index]
                let tangent = simd_normalize(splinePoints[index + 1] - current)

                let binormal = parallelTransport(previousBinormal: previousBinormal, tangent: tangent)
                let normalAxis = simd_normalize(simd_cross(binormal, tangent))
                previousBinormal = binormal

                // Determine which residue (chain-local) and SS type this spline point belongs to
                let residueIndex = min(index / splineSubdivisions, chainAtoms.count - 1)
                let residueSeq = chainAtoms[residueIndex].residueSeq
                let sectionType = structureType(for: chainID, residueSeq: residueSeq, structures: protein.secondaryStructure)

                // Sheet arrow taper: at the last residue of each sheet, widen at the base
                // and taper to a point at the C-terminal end.
                var widthScale = sectionWidth(for: sectionType)
                let heightScale = sectionHeight(for: sectionType)
                if sectionType == .sheet, sheetEndResidueIndices.contains(residueIndex) {
                    let intraResidue = Float(index % splineSubdivisions) / Float(splineSubdivisions)
                    let arrowBaseFactor: Float = 1.8
                    widthScale = sectionWidth(for: .sheet) * arrowBaseFactor * (1.0 - intraResidue)
                }

                let sectionColor = color(for: sectionType, chainID: chainID, protein: protein, mode: colorMode)
                let profile = profilePoints(for: sectionType)
                let ringStart = vertexBase

                for sample in profile {
                    let offset = normalAxis * (sample.position.x * widthScale) + binormal * (sample.position.y * heightScale)
                    let rawNormal = normalAxis * sample.normal.x + binormal * sample.normal.y
                    let worldNormal: SIMD3<Float>
                    if simd_length(rawNormal) > 0.0001 {
                        worldNormal = simd_normalize(rawNormal)
                    } else {
                        worldNormal = normalAxis
                    }
                    vertices.append(RibbonVertex(position: current + offset, normal: worldNormal, color: sectionColor))
                }
                vertexBase += UInt32(profileCount)

                // Connect this ring to the previous ring (in the same chain only)
                if index > 0 {
                    let previousStart = ringStart - UInt32(profileCount)
                    for i in 0..<profileCount {
                        let nextI = (i + 1) % profileCount
                        indices.append(previousStart + UInt32(i))
                        indices.append(ringStart + UInt32(i))
                        indices.append(ringStart + UInt32(nextI))

                        indices.append(previousStart + UInt32(i))
                        indices.append(ringStart + UInt32(nextI))
                        indices.append(previousStart + UInt32(nextI))
                    }
                }
            }
        }

        return (vertices, indices)
    }

    // MARK: - Spline

    nonisolated private static func buildPolylinePoints(controlPoints: [SIMD3<Float>], subdivisions: Int) -> [SIMD3<Float>] {
        guard controlPoints.count >= 2 else { return controlPoints }
        var points: [SIMD3<Float>] = []

        for i in 0..<(controlPoints.count - 1) {
            let p0 = controlPoints[max(i - 1, 0)]
            let p1 = controlPoints[i]
            let p2 = controlPoints[i + 1]
            let p3 = controlPoints[min(i + 2, controlPoints.count - 1)]

            for step in 0..<subdivisions {
                let t = Float(step) / Float(subdivisions)
                points.append(catmullRom(p0, p1, p2, p3, t: t))
            }
        }

        if let last = controlPoints.last {
            points.append(last)
        }
        return points
    }

    nonisolated private static func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        let t2: Float = t * t
        let t3: Float = t2 * t

        let term1: SIMD3<Float> = Float(2.0) * p1

        let term2Base: SIMD3<Float> = p2 - p0
        let term2: SIMD3<Float> = term2Base * t

        let term3Base1: SIMD3<Float> = Float(2.0) * p0
        let term3Base2: SIMD3<Float> = Float(5.0) * p1
        let term3Base3: SIMD3<Float> = Float(4.0) * p2
        let term3Base: SIMD3<Float> = term3Base1 - term3Base2 + term3Base3 - p3
        let term3: SIMD3<Float> = term3Base * t2

        let term4Base1: SIMD3<Float> = Float(3.0) * p1
        let term4Base2: SIMD3<Float> = Float(3.0) * p2
        let term4Base: SIMD3<Float> = (p3 - p0) + term4Base1 - term4Base2
        let term4: SIMD3<Float> = term4Base * t3

        let sum: SIMD3<Float> = term1 + term2 + term3 + term4
        return Float(0.5) * sum
    }

    // MARK: - Frames

    nonisolated private static func initialBinormal(for tangent: SIMD3<Float>) -> SIMD3<Float> {
        let reference: SIMD3<Float> = abs(tangent.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        return simd_normalize(simd_cross(tangent, reference))
    }

    /// Rotates the previous binormal minimally so it remains perpendicular to the new tangent,
    /// eliminating the twist artifacts of recomputing the frame from scratch per segment.
    nonisolated private static func parallelTransport(previousBinormal: SIMD3<Float>, tangent: SIMD3<Float>) -> SIMD3<Float> {
        var candidate = previousBinormal - simd_dot(previousBinormal, tangent) * tangent
        let length = simd_length(candidate)
        if length < 0.0001 {
            candidate = initialBinormal(for: tangent)
        } else {
            candidate /= length
        }
        return candidate
    }

    // MARK: - Secondary Structure Lookup

    nonisolated private static func structureType(for chainID: Character, residueSeq: Int, structures: [SecondaryStructureElement]) -> SecondaryStructureType {
        if let match = structures.first(where: { $0.chainID == chainID && residueSeq >= $0.startResidueSeq && residueSeq <= $0.endResidueSeq }) {
            return match.type
        }
        return .loop
    }

    // MARK: - Color

    nonisolated private static func color(for type: SecondaryStructureType, chainID: Character, protein: Protein, mode: ColorMode) -> SIMD4<Float> {
        switch mode {
        case .cpk:
            // CPK is element-based and meaningless per-residue, so fall back to a neutral ribbon tint
            return SIMD4<Float>(0.78, 0.78, 0.82, 1)
        case .chain:
            return protein.chainColors[chainID] ?? SIMD4<Float>(0.7, 0.7, 0.7, 1)
        case .secondary:
            switch type {
            case .helix: return SIMD4<Float>(1.0, 0.4, 0.4, 1)
            case .sheet: return SIMD4<Float>(0.4, 0.6, 1.0, 1)
            case .loop: return SIMD4<Float>(0.85, 0.85, 0.85, 1)
            }
        }
    }

    // MARK: - Cross-section profiles

    /// Returns 8 vertices around a unit cross-section profile shaped for the given SS type.
    /// Positions are in [-1, 1] and get scaled by width/height when extruded.
    /// Sheets use duplicated corner vertices with face-aligned normals so the ribbon faces
    /// shade flat. Helices use a smooth ellipse; loops use a smooth circle.
    nonisolated private static func profilePoints(for type: SecondaryStructureType) -> [ProfilePoint] {
        switch type {
        case .helix:
            // Elliptical cross-section, smooth normals
            return (0..<8).map { i in
                let angle = Float(i) / Float(8) * 2.0 * .pi
                let c = cos(angle)
                let s = sin(angle)
                return ProfilePoint(position: SIMD2<Float>(c, s), normal: SIMD2<Float>(c, s))
            }
        case .sheet:
            // Rectangular cross-section with sharp, face-aligned normals
            return [
                // Top face (+binormal)
                ProfilePoint(position: SIMD2<Float>(1, 1),  normal: SIMD2<Float>(0, 1)),
                ProfilePoint(position: SIMD2<Float>(-1, 1), normal: SIMD2<Float>(0, 1)),
                // Left face (-normal)
                ProfilePoint(position: SIMD2<Float>(-1, 1), normal: SIMD2<Float>(-1, 0)),
                ProfilePoint(position: SIMD2<Float>(-1, -1), normal: SIMD2<Float>(-1, 0)),
                // Bottom face (-binormal)
                ProfilePoint(position: SIMD2<Float>(-1, -1), normal: SIMD2<Float>(0, -1)),
                ProfilePoint(position: SIMD2<Float>(1, -1),  normal: SIMD2<Float>(0, -1)),
                // Right face (+normal)
                ProfilePoint(position: SIMD2<Float>(1, -1), normal: SIMD2<Float>(1, 0)),
                ProfilePoint(position: SIMD2<Float>(1, 1),  normal: SIMD2<Float>(1, 0))
            ]
        case .loop:
            // Circular cross-section, smooth normals
            return (0..<8).map { i in
                let angle = Float(i) / Float(8) * 2.0 * .pi
                let c = cos(angle)
                let s = sin(angle)
                return ProfilePoint(position: SIMD2<Float>(c, s), normal: SIMD2<Float>(c, s))
            }
        }
    }

    // MARK: - Cross-section size

    /// Half-extent along the in-plane (normal) axis, in Angstroms.
    nonisolated private static func sectionWidth(for type: SecondaryStructureType) -> Float {
        switch type {
        case .helix: return 0.9
        case .sheet: return 1.1
        case .loop: return 0.22
        }
    }

    /// Half-extent along the out-of-plane (binormal) axis, in Angstroms.
    nonisolated private static func sectionHeight(for type: SecondaryStructureType) -> Float {
        switch type {
        case .helix: return 0.28
        case .sheet: return 0.18
        case .loop: return 0.22
        }
    }
}
