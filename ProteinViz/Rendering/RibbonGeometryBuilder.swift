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
    static func build(protein: Protein, colorMode: ColorMode) throws -> (vertices: [RibbonVertex], indices: [UInt32]) {
        guard protein.backboneAtoms.count >= 2 else {
            throw RibbonGeometryError.insufficientBackbone
        }

        let splineSubdivisions = 8
        let chainGroups = Dictionary(grouping: protein.backboneAtoms, by: { $0.chainID })
        var vertices: [RibbonVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(protein.backboneAtoms.count * splineSubdivisions * 8)

        var vertexBase: UInt32 = 0
        for chainID in chainGroups.keys.sorted() {
            let chainAtoms = chainGroups[chainID]!.sorted { $0.residueSeq < $1.residueSeq }
            guard chainAtoms.count >= 2 else { continue }

            let controlPoints = chainAtoms.map(\.position)
            let chainSegments = buildPolylinePoints(controlPoints: controlPoints, subdivisions: splineSubdivisions)
            guard chainSegments.count >= 2 else { continue }

            for index in 0..<(chainSegments.count - 1) {
                let current = chainSegments[index]
                let next = chainSegments[index + 1]
                let tangent = simd_normalize(next - current)
                let referenceUp = abs(tangent.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
                let binormal = simd_normalize(simd_cross(tangent, referenceUp))
                let normal = simd_normalize(simd_cross(binormal, tangent))

                let sectionType = structureType(for: chainID, residueSeq: chainAtoms[min(index / splineSubdivisions, chainAtoms.count - 1)].residueSeq, structures: protein.secondaryStructure)
                let sectionColor = color(for: sectionType, chainID: chainID, protein: protein, mode: colorMode)
                let profile = profilePoints(for: sectionType)
                let sectionWidth = sectionWidth(for: sectionType)
                let sectionHeight = sectionHeight(for: sectionType)

                let ringStart = vertexBase
                for point in profile {
                    let offset = normal * (point.x * sectionWidth) + binormal * (point.y * sectionHeight)
                    vertices.append(RibbonVertex(position: current + offset, normal: simd_normalize(offset == .zero ? normal : offset), color: sectionColor))
                    vertexBase += 1
                }

                // connect rings as degenerate quads in a simple strip-like layout
                if index > 0 {
                    let previousStart = ringStart - UInt32(profile.count)
                    for i in 0..<profile.count {
                        let nextIndex = (i + 1) % profile.count
                        indices.append(previousStart + UInt32(i))
                        indices.append(ringStart + UInt32(i))
                        indices.append(ringStart + UInt32(nextIndex))

                        indices.append(previousStart + UInt32(i))
                        indices.append(ringStart + UInt32(nextIndex))
                        indices.append(previousStart + UInt32(nextIndex))
                    }
                }
            }
        }

        return (vertices, indices)
    }

    // MARK: - Helpers

    private static func buildPolylinePoints(controlPoints: [SIMD3<Float>], subdivisions: Int) -> [SIMD3<Float>] {
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

    private static func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, t: Float) -> SIMD3<Float> {
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

    private static func structureType(for chainID: Character, residueSeq: Int, structures: [SecondaryStructureElement]) -> SecondaryStructureType {
        if let match = structures.first(where: { $0.chainID == chainID && residueSeq >= $0.startResidueSeq && residueSeq <= $0.endResidueSeq }) {
            return match.type
        }
        return .loop
    }

    private static func color(for type: SecondaryStructureType, chainID: Character, protein: Protein, mode: ColorMode) -> SIMD4<Float> {
        switch mode {
        case .cpk:
            return SIMD4<Float>(0.7, 0.7, 0.7, 1)
        case .chain:
            return protein.chainColors[chainID] ?? SIMD4<Float>(0.7, 0.7, 0.7, 1)
        case .secondary:
            switch type {
            case .helix: return SIMD4<Float>(1.0, 0.4, 0.4, 1)
            case .sheet: return SIMD4<Float>(0.4, 0.6, 1.0, 1)
            case .loop: return SIMD4<Float>(0.8, 0.8, 0.8, 1)
            }
        }
    }

    private static func profilePoints(for type: SecondaryStructureType) -> [SIMD2<Float>] {
        let sides = 8
        return (0..<sides).map { i in
            let angle = (Float(i) / Float(sides)) * 2 * .pi
            return SIMD2<Float>(cos(angle), sin(angle))
        }
    }

    private static func sectionWidth(for type: SecondaryStructureType) -> Float {
        switch type {
        case .helix: return 1.5
        case .sheet: return 2.0
        case .loop: return 0.3
        }
    }

    private static func sectionHeight(for type: SecondaryStructureType) -> Float {
        switch type {
        case .helix: return 0.4
        case .sheet: return 0.3
        case .loop: return 0.3
        }
    }
}
