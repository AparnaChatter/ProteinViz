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

// MARK: - Metal Renderer

final class MetalRenderer: NSObject, ObservableObject {
    @Published var protein: Protein? {
        didSet {
            rebuildGeometry()
        }
    }

    @Published var representationMode: RepresentationMode = .spheres {
        didSet {
            rebuildGeometry()
        }
    }

    @Published var colorMode: ColorMode = .cpk {
        didSet {
            rebuildGeometry()
        }
    }

    @Published var geometryError: String?

    weak var gestureHandler: GestureHandler?

    var metalDevice: MTLDevice { device }
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let spherePipelineState: MTLRenderPipelineState
    private let ribbonPipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private var instanceBuffer: MTLBuffer?
    private var instanceCount: Int = 0
    private var cameraFitDistance: Float = 10.0
    private var proteinCenter: SIMD3<Float> = .zero
    private var proteinScale: Float = 1.0
    private let radiusVisualBoost: Float = 1.0
    private var ribbonVertexBuffer: MTLBuffer?
    private var ribbonIndexBuffer: MTLBuffer?
    private var ribbonIndexCount: Int = 0
    private var geometryTask: Task<Void, Never>?

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
            spherePipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to build the Metal render pipeline: \(error.localizedDescription)")
        }

        let ribbonPipelineDescriptor = MTLRenderPipelineDescriptor()
        ribbonPipelineDescriptor.label = "ProteinViz Ribbon Pipeline"
        ribbonPipelineDescriptor.vertexFunction = library.makeFunction(name: "ribbon_vertex")
        ribbonPipelineDescriptor.fragmentFunction = library.makeFunction(name: "ribbon_fragment")
        ribbonPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        ribbonPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            ribbonPipelineState = try device.makeRenderPipelineState(descriptor: ribbonPipelineDescriptor)
        } catch {
            fatalError("Failed to build the ribbon render pipeline: \(error.localizedDescription)")
        }

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

    private func rebuildGeometry() {
        geometryTask?.cancel()

        guard let protein else {
            instanceBuffer = nil
            instanceCount = 0
            cameraFitDistance = 10.0
            proteinCenter = .zero
            proteinScale = 1.0
            ribbonVertexBuffer = nil
            ribbonIndexBuffer = nil
            ribbonIndexCount = 0
            return
        }

        proteinCenter = protein.center
        let radius = max(protein.boundingBox.radius, 1.0)
        proteinScale = 1.0 / radius
        cameraFitDistance = 2.25
        switch representationMode {
        case .spheres:
            updateSphereBuffers(for: protein)
            ribbonVertexBuffer = nil
            ribbonIndexBuffer = nil
            ribbonIndexCount = 0
        case .ribbon:
            scheduleRibbonBuild(for: protein)
            instanceBuffer = nil
            instanceCount = 0
        }
    }

    private func updateSphereBuffers(for protein: Protein) {
        instanceCount = protein.atoms.count

        let instanceData = protein.atoms.map { atom -> InstanceData in
            let centeredPosition = (atom.position - proteinCenter) * proteinScale
            let color = sphereColor(for: atom, in: protein)
            return InstanceData(position: centeredPosition, color: color, radius: atom.vanDerWaalsRadius * proteinScale * radiusVisualBoost)
        }

        let bufferLength = max(1, instanceData.count) * MemoryLayout<InstanceData>.stride
        instanceBuffer = instanceData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return device.makeBuffer(length: bufferLength, options: .storageModeShared)
            }
            return device.makeBuffer(bytes: baseAddress, length: bufferLength, options: .storageModeShared)
        }
    }

    private func scheduleRibbonBuild(for protein: Protein) {
        geometryTask = Task.detached(priority: .userInitiated) { [protein, proteinCenter, proteinScale, colorMode, device] in
            do {
                let built = try RibbonGeometryBuilder.build(protein: protein, colorMode: colorMode)
                if Task.isCancelled { return }

                let normalizedVertices = built.vertices.map { vertex -> RibbonVertex in
                    var copy = vertex
                    copy.position = (copy.position - proteinCenter) * proteinScale
                    return copy
                }

                let vertexLength = max(1, normalizedVertices.count) * MemoryLayout<RibbonVertex>.stride
                let indexLength = max(1, built.indices.count) * MemoryLayout<UInt32>.stride

                let vertexBuffer = normalizedVertices.withUnsafeBytes { rawBuffer -> MTLBuffer? in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return device.makeBuffer(length: vertexLength, options: .storageModeShared)
                    }
                    return device.makeBuffer(bytes: baseAddress, length: vertexLength, options: .storageModeShared)
                }

                let indexBuffer = built.indices.withUnsafeBytes { rawBuffer -> MTLBuffer? in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return device.makeBuffer(length: indexLength, options: .storageModeShared)
                    }
                    return device.makeBuffer(bytes: baseAddress, length: indexLength, options: .storageModeShared)
                }

                await MainActor.run {
                    self.ribbonVertexBuffer = vertexBuffer
                    self.ribbonIndexBuffer = indexBuffer
                    self.ribbonIndexCount = built.indices.count
                    self.geometryError = nil
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.ribbonVertexBuffer = nil
                    self.ribbonIndexBuffer = nil
                    self.ribbonIndexCount = 0
                    self.geometryError = message
                }
            }
        }
    }

    private func sphereColor(for atom: Atom, in protein: Protein) -> SIMD4<Float> {
        switch colorMode {
        case .cpk:
            return atom.cpkColor
        case .chain:
            return protein.chainColors[atom.chainID] ?? atom.cpkColor
        case .secondary:
            return secondaryStructureColor(for: atom, in: protein)
        }
    }

    private func secondaryStructureColor(for atom: Atom, in protein: Protein) -> SIMD4<Float> {
        if let element = protein.secondaryStructure.first(where: {
            $0.chainID == atom.chainID && atom.residueSeq >= $0.startResidueSeq && atom.residueSeq <= $0.endResidueSeq
        }) {
            switch element.type {
            case .helix:
                return SIMD4<Float>(1.0, 0.4, 0.4, 1.0)
            case .sheet:
                return SIMD4<Float>(0.4, 0.6, 1.0, 1.0)
            case .loop:
                return SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
            }
        }

        return SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
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
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setCullMode(.none)

        switch representationMode {
        case .spheres:
            renderEncoder.setRenderPipelineState(spherePipelineState)
            if protein != nil, let instanceBuffer, instanceCount > 0 {
                let uniforms = makeFrameUniforms(drawableSize: view.drawableSize)
                var uniformsCopy = uniforms
                renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                renderEncoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
            }
        case .ribbon:
            renderEncoder.setRenderPipelineState(ribbonPipelineState)
            if let ribbonVertexBuffer, let ribbonIndexBuffer, ribbonIndexCount > 0 {
                let uniforms = makeFrameUniforms(drawableSize: view.drawableSize)
                var uniformsCopy = uniforms
                renderEncoder.setVertexBuffer(ribbonVertexBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: ribbonIndexCount, indexType: .uint32, indexBuffer: ribbonIndexBuffer, indexBufferOffset: 0)
            }
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
