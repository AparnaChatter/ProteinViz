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
    @ObservedObject var annotationStore: AnnotationStore
    @State private var representationMode: RepresentationMode = .spheres
    @State private var colorMode: ColorMode = .cpk
    @State private var isLegendExpanded = true
    @State private var geometryAlertMessage: String?
    @State private var isAnnotationMode = false
    @State private var screenshotItem: ScreenshotItem?
    @State private var isCapturingScreenshot = false
    @State private var screenshotErrorMessage: String?

    var body: some View {
        ZStack {
            MetalView(
                protein: protein,
                renderer: renderer,
                gestureHandler: gestureHandler,
                onTap: handleTap
            )
            .clipped()
            .ignoresSafeArea()

            AnnotationOverlay(
                protein: protein,
                annotationStore: annotationStore,
                gestureHandler: gestureHandler,
                renderer: renderer
            )
            .allowsHitTesting(true)
        }
        .navigationTitle(protein.name)
        .overlay(alignment: .bottomLeading) {
            if colorMode != .cpk {
                legendOverlay
                    .padding()
            }
        }
        .overlay(alignment: .topLeading) {
            if isAnnotationMode {
                annotationModeBanner
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

                Button {
                    isAnnotationMode.toggle()
                } label: {
                    Label("Annotation Mode", systemImage: isAnnotationMode ? "mappin.circle.fill" : "mappin.circle")
                }
                .tint(isAnnotationMode ? .yellow : nil)

                Button {
                    captureScreenshot()
                } label: {
                    if isCapturingScreenshot {
                        ProgressView()
                    } else {
                        Label("Capture", systemImage: "camera")
                    }
                }
                .disabled(isCapturingScreenshot)

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
        .sheet(item: $screenshotItem) { item in
            ScreenshotAnnotationView(baseImage: item.image)
        }
        .alert("Ribbon Geometry Error", isPresented: Binding(
            get: { geometryAlertMessage != nil },
            set: { if !$0 { geometryAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { geometryAlertMessage = nil }
        } message: {
            Text(geometryAlertMessage ?? "")
        }
        .alert("Capture Failed", isPresented: Binding(
            get: { screenshotErrorMessage != nil },
            set: { if !$0 { screenshotErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { screenshotErrorMessage = nil }
        } message: {
            Text(screenshotErrorMessage ?? "")
        }
    }

    // MARK: - Annotation handling

    private func handleTap(_ point: CGPoint, _ size: CGSize) {
        guard isAnnotationMode else { return }
        guard let picked = renderer.pickAtom(at: point, viewSize: size) else { return }
        let label = defaultLabel(for: picked.atom)
        let annotation = ProteinAnnotation(
            anchorWorld: picked.normalizedPosition,
            text: label,
            atomSerial: picked.atom.serial,
            residueName: picked.atom.residueName,
            chainID: picked.atom.chainID,
            residueSeq: picked.atom.residueSeq
        )
        annotationStore.add(annotation, to: protein)
    }

    private func defaultLabel(for atom: Atom) -> String {
        let residue = atom.residueName.trimmingCharacters(in: .whitespacesAndNewlines)
        if residue.isEmpty {
            return atom.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(residue) \(atom.residueSeq)"
    }

    // MARK: - Screenshot

    private func captureScreenshot() {
        isCapturingScreenshot = true
        renderer.captureScreenshot { image in
            Task { @MainActor in
                self.isCapturingScreenshot = false
                if let image {
                    self.screenshotItem = ScreenshotItem(image: image)
                } else {
                    self.screenshotErrorMessage = "Could not capture the current frame."
                }
            }
        }
    }

    // MARK: - Annotation Mode Banner

    private var annotationModeBanner: some View {
        Label("Tap an atom to add a label", systemImage: "hand.tap")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.yellow.opacity(0.8), lineWidth: 1))
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
