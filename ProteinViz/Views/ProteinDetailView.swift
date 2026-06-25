//
//  ProteinDetailView.swift
//  ProteinViz
//

import SwiftUI

// MARK: - Protein Detail View

struct ProteinDetailView: View {
    let protein: Protein
    @ObservedObject var renderer: MetalRenderer
    @ObservedObject var gestureHandler: GestureHandler
    @State private var selectedRepresentation: RepresentationMode = .spheres

    var body: some View {
        MetalView(protein: protein, renderer: renderer, gestureHandler: gestureHandler)
            .ignoresSafeArea()
            .navigationTitle(protein.name)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(protein.name)
                            .font(.headline)
                        Text("\(protein.atomCount) atoms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        gestureHandler.resetCamera()
                    } label: {
                        Label("Reset Camera", systemImage: "goforward")
                    }

                    Picker("Representation", selection: $selectedRepresentation) {
                        ForEach(RepresentationMode.phaseOneCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .onAppear {
                renderer.protein = protein
                renderer.representation = selectedRepresentation
            }
            .onChange(of: selectedRepresentation) { _, newValue in
                renderer.representation = newValue
            }
    }
}
