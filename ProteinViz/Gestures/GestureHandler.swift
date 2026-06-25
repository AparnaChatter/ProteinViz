//
//  GestureHandler.swift
//  ProteinViz
//

import Foundation
import Combine
import simd
import SwiftUI

// MARK: - Gesture Handler

final class GestureHandler: ObservableObject {
    @Published var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    @Published var zoom: Float = 1.0
    @Published var panOffset: SIMD2<Float> = .zero

    // MARK: - Gesture Mutations

    func rotate(by delta: CGSize) {
        let yaw = simd_quatf(angle: Float(delta.width) * 0.01, axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: Float(delta.height) * 0.01, axis: SIMD3<Float>(1, 0, 0))
        rotation = simd_normalize(pitch * yaw * rotation)
    }

    func zoom(by magnification: CGFloat) {
        zoom = min(max(zoom * Float(magnification), 0.1), 10.0)
    }

    func pan(by delta: CGSize, worldScale: Float) {
        let translated = SIMD2<Float>(Float(delta.width) * worldScale, -Float(delta.height) * worldScale)
        panOffset += translated
    }

    func resetCamera() {
        rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        zoom = 1.0
        panOffset = .zero
    }
}
