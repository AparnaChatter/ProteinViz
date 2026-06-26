//
//  AnnotationOverlay.swift
//  ProteinViz
//

import SwiftUI

// MARK: - Annotation Overlay

/// Renders 3D-anchored annotation labels as a SwiftUI overlay above the Metal view.
/// Each label re-projects from normalized world space to screen coordinates whenever the
/// gesture handler publishes a change (rotate / zoom / pan).
struct AnnotationOverlay: View {
    let protein: Protein
    @ObservedObject var annotationStore: AnnotationStore
    @ObservedObject var gestureHandler: GestureHandler
    let renderer: MetalRenderer

    @State private var editingAnnotationID: UUID?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(annotationStore.annotations(for: protein)) { annotation in
                    if let screenPosition = renderer.projectToScreen(
                        normalizedWorldPosition: annotation.anchorWorld,
                        viewSize: geometry.size
                    ) {
                        AnnotationLabel(
                            annotation: annotation,
                            onEdit: { editingAnnotationID = annotation.id },
                            onDelete: { annotationStore.remove(annotation.id, from: protein) }
                        )
                        .position(screenPosition)
                    }
                }
            }
        }
        .sheet(item: editingAnnotationBinding) { annotation in
            AnnotationEditSheet(annotation: annotation, store: annotationStore, protein: protein)
        }
    }

    private var editingAnnotationBinding: Binding<ProteinAnnotation?> {
        Binding(
            get: {
                guard let id = editingAnnotationID else { return nil }
                return annotationStore.annotations(for: protein).first(where: { $0.id == id })
            },
            set: { if $0 == nil { editingAnnotationID = nil } }
        )
    }
}

// MARK: - Annotation Label

private struct AnnotationLabel: View {
    let annotation: ProteinAnnotation
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isShowingActions = false

    var body: some View {
        Button {
            isShowingActions = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(annotation.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if !annotation.subtitle.isEmpty {
                    Text(annotation.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.yellow.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Annotation", isPresented: $isShowingActions, titleVisibility: .hidden) {
            Button("Edit Label") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Annotation Edit Sheet

private struct AnnotationEditSheet: View {
    let annotation: ProteinAnnotation
    @ObservedObject var store: AnnotationStore
    let protein: Protein
    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String

    init(annotation: ProteinAnnotation, store: AnnotationStore, protein: Protein) {
        self.annotation = annotation
        self.store = store
        self.protein = protein
        _editedText = State(initialValue: annotation.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Annotation text", text: $editedText, axis: .vertical)
                        .lineLimit(1...4)
                }
                if !annotation.subtitle.isEmpty {
                    Section("Anchor") {
                        Text(annotation.subtitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(annotation.id, text: editedText, in: protein)
                        dismiss()
                    }
                    .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
