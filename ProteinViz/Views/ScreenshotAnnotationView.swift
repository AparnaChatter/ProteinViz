//
//  ScreenshotAnnotationView.swift
//  ProteinViz
//

import PencilKit
import SwiftUI
import UIKit

// MARK: - Screenshot Item

/// Identifiable wrapper so `UIImage` can drive a `.sheet(item:)` modal.
struct ScreenshotItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Screenshot Annotation View

struct ScreenshotAnnotationView: View {
    let baseImage: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @State private var didSave = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { geo in
                    let fitted = aspectFitFrame(imageSize: baseImage.size, in: geo.size)
                    ZStack {
                        Image(uiImage: baseImage)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        PencilCanvas(canvas: $canvasView)
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
            }
            .navigationTitle("Annotate Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                // One group keeps Clear / Share / Save in a single, predictable trailing row
                // instead of competing for the same toolbar slot and collapsing into a menu.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        canvasView.drawing = PKDrawing()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }

                    ShareLink(
                        item: shareImage,
                        preview: SharePreview("ProteinViz Capture", image: shareImage)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        saveToPhotos()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .alert("Saved to Photos", isPresented: $didSave) {
                Button("OK", role: .cancel) {}
            }
            .alert("Couldn't Save", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    // MARK: - Sharing

    /// SwiftUI Image conforms to `Transferable`, so wrapping the annotated composite
    /// (or the original capture when the canvas is blank) gives ShareLink everything
    /// it needs for AirDrop, Mail, Messages, etc.
    private var shareImage: Image {
        Image(uiImage: composite() ?? baseImage)
    }

    // MARK: - Composition

    private func composite() -> UIImage? {
        let size = baseImage.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = baseImage.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            let bounds = canvasView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            let drawingImage = canvasView.drawing.image(from: bounds, scale: baseImage.scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func saveToPhotos() {
        guard let image = composite() else {
            saveErrorMessage = "Could not render the annotated image."
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        didSave = true
    }

    private func aspectFitFrame(imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else {
            return container
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            let width = container.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = container.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }
}

// MARK: - Pencil Canvas

private struct PencilCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .systemYellow, width: 6)
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false

        let picker = context.coordinator.toolPicker
        DispatchQueue.main.async {
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator {
        let toolPicker = PKToolPicker()
    }
}
