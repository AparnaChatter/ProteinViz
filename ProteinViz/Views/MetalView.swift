//
//  MetalView.swift
//  ProteinViz
//

import MetalKit
import SwiftUI
import UIKit

// MARK: - Metal View

struct MetalView: UIViewRepresentable {
    let protein: Protein?
    let renderer: MetalRenderer
    let gestureHandler: GestureHandler

    func makeCoordinator() -> Coordinator {
        Coordinator(gestureHandler: gestureHandler)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.metalDevice)
        view.delegate = renderer
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.05, green: 0.08, blue: 0.05, alpha: 1.0)
        view.clearDepth = 1.0
        view.autoResizeDrawable = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true

        renderer.gestureHandler = gestureHandler

        let rotatePan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotate(_:)))
        rotatePan.minimumNumberOfTouches = 1
        rotatePan.maximumNumberOfTouches = 1
        rotatePan.delegate = context.coordinator

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = context.coordinator

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchGesture.delegate = context.coordinator

        view.addGestureRecognizer(rotatePan)
        view.addGestureRecognizer(panGesture)
        view.addGestureRecognizer(pinchGesture)

        renderer.protein = protein

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.delegate = renderer
        renderer.gestureHandler = gestureHandler
        renderer.protein = protein
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let gestureHandler: GestureHandler

        init(gestureHandler: GestureHandler) {
            self.gestureHandler = gestureHandler
        }

        @objc func handleRotate(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            guard translation != .zero else { return }
            gestureHandler.rotate(by: CGSize(width: translation.x, height: translation.y))
            recognizer.setTranslation(.zero, in: recognizer.view)
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            guard translation != .zero else { return }
            let panScale = 0.01 / max(gestureHandler.zoom, 0.1)
            gestureHandler.pan(by: CGSize(width: translation.x, height: translation.y), worldScale: panScale)
            recognizer.setTranslation(.zero, in: recognizer.view)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.scale != 1.0 else { return }
            gestureHandler.zoom(by: recognizer.scale)
            recognizer.scale = 1.0
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
