// ProteinViz — Metal Rendering Engine
// Architectural reference: BioViewer by Raúl Montón Pinillos
// https://github.com/Androp0v/BioViewer
// Licensed under GPL-3.0. ProteinViz is also released under GPL-3.0.
// Sphere impostor technique adapted from BioViewer's Metal implementation.
//
//  MetalRenderer.swift
//  ProteinViz
//

import Foundation
import Combine
import Metal
import MetalKit
import simd
import SwiftUI

// MARK: - Representation Mode

enum RepresentationMode: String, CaseIterable, Identifiable {
    case spheres
    case ballAndStick
    case ribbon

    var id: String { rawValue }

    static var phaseOneCases: [RepresentationMode] {
        [.spheres]
    }
}

// MARK: - Metal Renderer

final class MetalRenderer: NSObject, ObservableObject {
    @Published var protein: Protein? {
        didSet {
            updateProteinBuffers()
        }
    }

    @Published var representation: RepresentationMode = .spheres

    weak var gestureHandler: GestureHandler?

    var metalDevice: MTLDevice { device }
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private let rasterState: MTLRenderPipelineState?
    private var instanceBuffer: MTLBuffer?
    private var instanceCount: Int = 0
    private var cameraFitDistance: Float = 10.0
    private var proteinCenter: SIMD3<Float> = .zero
    private var proteinScale: Float = 1.0
    private let radiusVisualBoost: Float = 4.0

    // MARK: - Lifecycle

    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required for ProteinViz on iPadOS.")
        }

        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create a Metal command queue.")
        }
        self.commandQueue = commandQueue

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            fatalError("Failed to load the default Metal library: \(error.localizedDescription)")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "ProteinViz Sphere Impostor Pipeline"
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexSphereImpostor")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentSphereImpostor")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to build the Metal render pipeline: \(error.localizedDescription)")
        }

        let rasterDescriptor = MTLRenderPipelineDescriptor()
        rasterDescriptor.label = "ProteinViz Raster State Placeholder"
        rasterDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        rasterDescriptor.depthAttachmentPixelFormat = .depth32Float
        rasterDescriptor.vertexFunction = library.makeFunction(name: "vertexSphereImpostor")
        rasterDescriptor.fragmentFunction = library.makeFunction(name: "fragmentSphereImpostor")
        rasterDescriptor.inputPrimitiveTopology = .triangle
        rasterDescriptor.rasterSampleCount = 1
        rasterState = nil

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            fatalError("Failed to create the Metal depth stencil state.")
        }
        self.depthStencilState = depthStencilState

        super.init()
    }

    // MARK: - Protein Updates

    private func updateProteinBuffers() {
        guard let protein else {
            instanceBuffer = nil
            instanceCount = 0
            cameraFitDistance = 10.0
            proteinCenter = .zero
            proteinScale = 1.0
            return
        }

        proteinCenter = protein.center
        let radius = max(protein.boundingBox.radius, 1.0)
        proteinScale = 1.0 / radius
        cameraFitDistance = 2.25
        instanceCount = protein.atoms.count

        let instanceData = protein.atoms.map { atom -> InstanceData in
            let centeredPosition = (atom.position - proteinCenter) * proteinScale
            return InstanceData(position: centeredPosition, color: atom.cpkColor, radius: atom.vanDerWaalsRadius * proteinScale * radiusVisualBoost)
        }

        let bufferLength = max(1, instanceData.count) * MemoryLayout<InstanceData>.stride
        instanceBuffer = instanceData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return device.makeBuffer(length: bufferLength, options: .storageModeShared)
            }
            return device.makeBuffer(bytes: baseAddress, length: bufferLength, options: .storageModeShared)
        }
    }

    // MARK: - Camera / Uniforms

    private func makeFrameUniforms(drawableSize: CGSize) -> FrameUniforms {
        let safeZoom = max(gestureHandler?.zoom ?? 1.0, 0.1)
        let safeAspect = max(Float(drawableSize.width / max(drawableSize.height, 1.0)), 0.01)
        let cameraDistance = cameraFitDistance / safeZoom
        let panOffset = gestureHandler?.panOffset ?? .zero
        let rotation = gestureHandler?.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

        let modelMatrix =
            float4x4.translation(SIMD3<Float>(panOffset.x, panOffset.y, 0)) *
            float4x4.rotation(rotation)

        let viewMatrix = float4x4.lookAt(
            eye: SIMD3<Float>(0, 0, cameraDistance),
            center: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )

        let projectionMatrix = float4x4.perspective(
            fovYRadians: 45.0 * (.pi / 180.0),
            aspectRatio: safeAspect,
            nearZ: 0.1,
            farZ: 10_000.0
        )

        let modelViewMatrix = viewMatrix * modelMatrix
        let normalMatrix = float3x3(modelViewMatrix)

        return FrameUniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            normalMatrix: normalMatrix
        )
    }
}

// MARK: - MTKViewDelegate

extension MetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Camera projection is rebuilt per-frame from the current drawable size.
    }

    func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.label = "ProteinViz Render Encoder"
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setCullMode(.none)

        if protein != nil, let instanceBuffer, instanceCount > 0 {
            let uniforms = makeFrameUniforms(drawableSize: view.drawableSize)
            var uniformsCopy = uniforms
            renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            renderEncoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
