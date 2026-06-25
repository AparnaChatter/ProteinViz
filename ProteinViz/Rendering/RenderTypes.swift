//
//  RenderTypes.swift
//  ProteinViz
//

import simd

// MARK: - Shared Render Types

struct InstanceData {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var radius: Float
}

struct FrameUniforms {
    var modelMatrix: float4x4
    var viewMatrix: float4x4
    var projectionMatrix: float4x4
    var normalMatrix: float3x3
}

// MARK: - Matrix Helpers

extension float4x4 {
    static var identity: float4x4 {
        matrix_identity_float4x4
    }

    init(_ quaternion: simd_quatf) {
        let x = quaternion.vector.x
        let y = quaternion.vector.y
        let z = quaternion.vector.z
        let w = quaternion.vector.w

        let x2 = x + x
        let y2 = y + y
        let z2 = z + z

        let xx = x * x2
        let xy = x * y2
        let xz = x * z2
        let yy = y * y2
        let yz = y * z2
        let zz = z * z2
        let wx = w * x2
        let wy = w * y2
        let wz = w * z2

        self.init(columns: (
            SIMD4<Float>(1 - (yy + zz), xy + wz, xz - wy, 0),
            SIMD4<Float>(xy - wz, 1 - (xx + zz), yz + wx, 0),
            SIMD4<Float>(xz + wy, yz - wx, 1 - (xx + yy), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func translation(_ translation: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1.0)
        return matrix
    }

    static func rotation(_ quaternion: simd_quatf) -> float4x4 {
        float4x4(quaternion)
    }

    static func scale(_ scale: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = scale.x
        matrix.columns.1.y = scale.y
        matrix.columns.2.z = scale.z
        return matrix
    }

    static func perspective(fovYRadians: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> float4x4 {
        let yScale = 1.0 / tan(fovYRadians * 0.5)
        let xScale = yScale / aspectRatio
        let zRange = nearZ - farZ

        var matrix = float4x4()
        matrix.columns = (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, farZ / zRange, -1),
            SIMD4<Float>(0, 0, (nearZ * farZ) / zRange, 0)
        )
        return matrix
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let forward = simd_normalize(eye - center)
        let side = simd_normalize(simd_cross(simd_normalize(up), forward))
        let correctedUp = simd_cross(forward, side)

        var matrix = matrix_identity_float4x4
        matrix.columns = (
            SIMD4<Float>(side.x, correctedUp.x, forward.x, 0),
            SIMD4<Float>(side.y, correctedUp.y, forward.y, 0),
            SIMD4<Float>(side.z, correctedUp.z, forward.z, 0),
            SIMD4<Float>(-simd_dot(side, eye), -simd_dot(correctedUp, eye), -simd_dot(forward, eye), 1)
        )
        return matrix
    }
}

extension float3x3 {
    init(_ matrix: float4x4) {
        self.init(
            SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
    }
}
