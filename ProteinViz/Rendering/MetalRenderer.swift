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
import CoreImage
import Metal
import MetalKit
import simd
import SwiftUI
import UIKit

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

    @Published var showLigands: Bool = true {
        didSet {
            rebuildGeometry()
        }
    }

    /// Residue currently selected from the sequence strip (or any future selection UI).
    /// Format matches `Atom.residueKey`: "<chainID>|<residueSeq>".
    @Published var selectedResidueKey: String? {
        didSet {
            if oldValue != selectedResidueKey {
                rebuildSelectionOverlay()
            }
        }
    }

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
    /// Ligand-only sphere buffer used as an overlay pass when the user is in ribbon mode.
    private var ligandInstanceBuffer: MTLBuffer?
    private var ligandInstanceCount: Int = 0
    /// Extra size multiplier so ligand atoms stand out against ribbon/spheres.
    private let ligandRadiusBoost: Float = 1.35
    /// Selected-residue overlay buffer (yellow highlight spheres rendered on top of the
    /// primary representation when a residue is selected from the sequence strip).
    private var selectedInstanceBuffer: MTLBuffer?
    private var selectedInstanceCount: Int = 0
    private let selectedRadiusBoost: Float = 1.55
    private var geometryTask: Task<Void, Never>?
    private var pendingScreenshot: (@Sendable (UIImage?) -> Void)?
    private var lastDrawableSize: CGSize = .zero
    private lazy var ciContext: CIContext = CIContext(mtlDevice: device)

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
            ligandInstanceBuffer = nil
            ligandInstanceCount = 0
            selectedInstanceBuffer = nil
            selectedInstanceCount = 0
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
        updateLigandBuffer(for: protein)
        rebuildSelectionOverlay()
    }

    /// Rebuilds only the highlight overlay — cheap, called whenever `selectedResidueKey`
    /// flips so toggling residues from the sequence strip doesn't trigger a full geometry rebuild.
    private func rebuildSelectionOverlay() {
        guard let protein else {
            selectedInstanceBuffer = nil
            selectedInstanceCount = 0
            return
        }
        updateSelectedBuffer(for: protein)
    }

    private func updateSphereBuffers(for protein: Protein) {
        let atomsToRender = showLigands ? protein.atoms : protein.atoms.filter { !$0.isLigand }
        instanceCount = atomsToRender.count

        let instanceData = atomsToRender.map { atom -> InstanceData in
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

    /// Builds a sphere instance buffer containing only ligand (HETATM) atoms with a small
    /// radius boost so they read clearly when overlaid on the ribbon representation.
    private func updateLigandBuffer(for protein: Protein) {
        let ligandAtoms = protein.atoms.filter { $0.isLigand }
        ligandInstanceCount = ligandAtoms.count

        guard !ligandAtoms.isEmpty else {
            ligandInstanceBuffer = nil
            return
        }

        let instanceData = ligandAtoms.map { atom -> InstanceData in
            let centered = (atom.position - proteinCenter) * proteinScale
            // CPK color always for ligand overlay so heme iron / metals are immediately readable.
            return InstanceData(
                position: centered,
                color: atom.cpkColor,
                radius: atom.vanDerWaalsRadius * proteinScale * radiusVisualBoost * ligandRadiusBoost
            )
        }

        let bufferLength = instanceData.count * MemoryLayout<InstanceData>.stride
        ligandInstanceBuffer = instanceData.withUnsafeBytes { rawBuffer in
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

    /// Builds the selected-residue overlay buffer. All atoms of the residue identified by
    /// `selectedResidueKey` get a bright tint and a radius boost. Drawn after every other
    /// pass so the selection sits on top of ribbon, spheres, and ligand labels alike.
    private func updateSelectedBuffer(for protein: Protein) {
        guard let key = selectedResidueKey else {
            selectedInstanceBuffer = nil
            selectedInstanceCount = 0
            return
        }
        let selectedAtoms = protein.atoms.filter { $0.residueKey == key }
        selectedInstanceCount = selectedAtoms.count

        guard !selectedAtoms.isEmpty else {
            selectedInstanceBuffer = nil
            return
        }

        let highlightColor = SIMD4<Float>(1.0, 0.86, 0.18, 1.0)
        let instanceData = selectedAtoms.map { atom -> InstanceData in
            let centered = (atom.position - proteinCenter) * proteinScale
            return InstanceData(
                position: centered,
                color: highlightColor,
                radius: atom.vanDerWaalsRadius * proteinScale * radiusVisualBoost * selectedRadiusBoost
            )
        }

        let bufferLength = instanceData.count * MemoryLayout<InstanceData>.stride
        selectedInstanceBuffer = instanceData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                return device.makeBuffer(length: bufferLength, options: .storageModeShared)
            }
            return device.makeBuffer(bytes: base, length: bufferLength, options: .storageModeShared)
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

    // MARK: - Picking

    /// The result of ray-picking an atom from a tap location.
    struct PickedAtom {
        let atom: Atom
        let normalizedPosition: SIMD3<Float>
    }

    /// Casts a ray from the given screen point and returns the nearest atom (if any).
    /// `viewSize` is in points; pixel/point distinction doesn't affect the aspect ratio used
    /// for projection, so this works for both SwiftUI overlays and UIKit hit-tests.
    func pickAtom(at screenPoint: CGPoint, viewSize: CGSize) -> PickedAtom? {
        guard let protein else { return nil }
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        let uniforms = makeFrameUniforms(drawableSize: viewSize)
        let mvp = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix
        let invMVP = mvp.inverse

        let ndcX = Float((screenPoint.x / viewSize.width) * 2.0 - 1.0)
        let ndcY = Float(1.0 - (screenPoint.y / viewSize.height) * 2.0)

        let nearH = invMVP * SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
        let farH  = invMVP * SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)
        guard nearH.w != 0, farH.w != 0 else { return nil }

        let nearW = SIMD3<Float>(nearH.x, nearH.y, nearH.z) / nearH.w
        let farW  = SIMD3<Float>(farH.x, farH.y, farH.z) / farH.w
        let rayOrigin = nearW
        let rayDir = simd_normalize(farW - nearW)
        let rayDirDot = simd_dot(rayDir, rayDir)
        guard rayDirDot > 0 else { return nil }

        let pickRadiusBoost: Float = 1.4
        var closestT: Float = .greatestFiniteMagnitude
        var picked: PickedAtom?

        for atom in protein.atoms {
            let p = (atom.position - proteinCenter) * proteinScale
            let r = atom.vanDerWaalsRadius * proteinScale * radiusVisualBoost * pickRadiusBoost

            let oc = rayOrigin - p
            let b = simd_dot(oc, rayDir)
            let c = simd_dot(oc, oc) - r * r
            let disc = b * b - rayDirDot * c
            guard disc >= 0 else { continue }
            let sqrtDisc = sqrt(disc)
            let t = (-b - sqrtDisc) / rayDirDot
            if t > 0, t < closestT {
                closestT = t
                picked = PickedAtom(atom: atom, normalizedPosition: p)
            }
        }
        return picked
    }

    /// Projects a position in the protein's original Ångström coordinate space (i.e. as it
    /// appears in the PDB file) to a screen point. Convenience over `projectToScreen` that
    /// applies the renderer's centering + normalization first.
    func projectProteinPointToScreen(_ proteinPosition: SIMD3<Float>, viewSize: CGSize) -> CGPoint? {
        let normalized = (proteinPosition - proteinCenter) * proteinScale
        return projectToScreen(normalizedWorldPosition: normalized, viewSize: viewSize)
    }

    /// Projects a position in normalized protein space to a screen point, or nil if behind the camera / off-screen in depth.
    func projectToScreen(normalizedWorldPosition: SIMD3<Float>, viewSize: CGSize) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let uniforms = makeFrameUniforms(drawableSize: viewSize)
        let mvp = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix
        let clip = mvp * SIMD4<Float>(normalizedWorldPosition.x, normalizedWorldPosition.y, normalizedWorldPosition.z, 1.0)
        guard clip.w > 0 else { return nil }

        let ndcX = clip.x / clip.w
        let ndcY = clip.y / clip.w
        let ndcZ = clip.z / clip.w
        guard ndcZ >= 0, ndcZ <= 1 else { return nil }

        let screenX = (CGFloat(ndcX) + 1.0) * 0.5 * viewSize.width
        let screenY = (1.0 - CGFloat(ndcY)) * 0.5 * viewSize.height
        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Screenshot Capture

    /// Captures the next rendered frame as a UIImage.
    /// Completion fires on the main queue. Only one screenshot may be in flight at a time.
    @MainActor
    func captureScreenshot(_ completion: @escaping @Sendable (UIImage?) -> Void) {
        pendingScreenshot = completion
    }

    private func makeUIImage(from texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height

        var raw = [UInt8](repeating: 0, count: totalBytes)
        raw.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // Drawable is BGRA8Unorm. The bitmap info below tells Core Graphics to read
        // the bytes as little-endian 32-bit ARGB, which matches in-memory BGRA byte order.
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            CGBitmapInfo.byteOrder32Little
        ]
        guard let provider = CGDataProvider(data: NSData(bytes: raw, length: totalBytes)) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cgImage)
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
            let uniforms = makeFrameUniforms(drawableSize: view.drawableSize)
            var uniformsCopy = uniforms
            if let ribbonVertexBuffer, let ribbonIndexBuffer, ribbonIndexCount > 0 {
                renderEncoder.setVertexBuffer(ribbonVertexBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: ribbonIndexCount, indexType: .uint32, indexBuffer: ribbonIndexBuffer, indexBufferOffset: 0)
            }
            // Ligand overlay pass: render HETATM atoms (heme, ATP, drug molecules, ions, etc.)
            // as CPK-colored spheres on top of the ribbon so they remain visible.
            if showLigands, let ligandInstanceBuffer, ligandInstanceCount > 0 {
                renderEncoder.setRenderPipelineState(spherePipelineState)
                renderEncoder.setVertexBuffer(ligandInstanceBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                renderEncoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: ligandInstanceCount)
            }
        }

        // Selection highlight pass: bright yellow boosted spheres for whichever residue
        // the sequence strip has selected. Renders on top of every other pass so it's
        // always visible, regardless of representation mode.
        if let selectedInstanceBuffer, selectedInstanceCount > 0 {
            let uniforms = makeFrameUniforms(drawableSize: view.drawableSize)
            var uniformsCopy = uniforms
            renderEncoder.setRenderPipelineState(spherePipelineState)
            renderEncoder.setVertexBuffer(selectedInstanceBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            renderEncoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: selectedInstanceCount)
        }

        renderEncoder.endEncoding()

        // Optional screenshot capture: blit the drawable into a CPU-readable texture
        // before presenting, then convert to UIImage on completion.
        if let completion = pendingScreenshot {
            pendingScreenshot = nil
            let drawableTexture = drawable.texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: drawableTexture.pixelFormat,
                width: drawableTexture.width,
                height: drawableTexture.height,
                mipmapped: false
            )
            descriptor.storageMode = .shared
            // Leave usage as default (.unknown) so the texture is valid as a blit destination
            // AND readable on the CPU.
            if let captureTexture = device.makeTexture(descriptor: descriptor),
               let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(
                    from: drawableTexture,
                    sourceSlice: 0,
                    sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: drawableTexture.width, height: drawableTexture.height, depth: 1),
                    to: captureTexture,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blit.endEncoding()
                commandBuffer.addCompletedHandler { [weak self] buffer in
                    // Always finish on the main actor: makeUIImage is MainActor-isolated and
                    // the SwiftUI completion expects to be invoked on main.
                    let status = buffer.status
                    let texture = captureTexture
                    Task { @MainActor [weak self] in
                        guard status == .completed else {
                            completion(nil)
                            return
                        }
                        let image = self?.makeUIImage(from: texture)
                        completion(image)
                    }
                }
            } else {
                Task { @MainActor in completion(nil) }
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
