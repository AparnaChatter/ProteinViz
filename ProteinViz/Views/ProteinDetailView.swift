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
    @State private var representationMode: RepresentationMode = .spheres
    @State private var colorMode: ColorMode = .cpk
    @State private var isLegendExpanded = true
    @State private var geometryAlertMessage: String?

    var body: some View {
        MetalView(protein: protein, renderer: renderer, gestureHandler: gestureHandler)
            .clipped()
            .ignoresSafeArea()
            .navigationTitle(protein.name)
            .overlay(alignment: .bottomLeading) {
                if colorMode != .cpk {
                    legendOverlay
                        .padding()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        gestureHandler.resetCamera()
                    } label: {
                        Label("Reset Camera", systemImage: "goforward")
                    }

                    Picker("Representation", selection: $representationMode) {
                        ForEach(RepresentationMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Color", selection: $colorMode) {
                        ForEach(ColorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .onAppear {
                renderer.protein = protein
                renderer.representationMode = representationMode
                renderer.colorMode = colorMode
            }
            .onChange(of: representationMode) { _, newValue in
                renderer.representationMode = newValue
            }
            .onChange(of: colorMode) { _, newValue in
                renderer.colorMode = newValue
            }
            .onChange(of: renderer.geometryError) { _, newValue in
                geometryAlertMessage = newValue
            }
            .alert("Ribbon Geometry Error", isPresented: Binding(
                get: { geometryAlertMessage != nil },
                set: { if !$0 { geometryAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { geometryAlertMessage = nil }
            } message: {
                Text(geometryAlertMessage ?? "")
            }
    }

    // MARK: - Legend

    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(colorMode == .chain ? "Chains" : "Structure")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    isLegendExpanded.toggle()
                } label: {
                    Image(systemName: isLegendExpanded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)
            }

            if isLegendExpanded {
                if colorMode == .chain {
                    ForEach(protein.chainColors.keys.sorted(), id: \.self) { chainID in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(uiColor: UIColor(
                                    red: CGFloat(protein.chainColors[chainID]?.x ?? 0.7),
                                    green: CGFloat(protein.chainColors[chainID]?.y ?? 0.7),
                                    blue: CGFloat(protein.chainColors[chainID]?.z ?? 0.7),
                                    alpha: 1.0
                                )))
                                .frame(width: 10, height: 10)
                            Text("Chain \(chainID)")
                                .font(.caption)
                        }
                    }
                } else {
                    legendRow(title: "Helix", color: .red)
                    legendRow(title: "Sheet", color: .blue)
                    legendRow(title: "Loop", color: .white)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.primary)
    }

    private func legendRow(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption)
        }
    }
}
