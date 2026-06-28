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
    let curatedEntry: CuratedProteinEntry?
    @State private var representationMode: RepresentationMode = .spheres
    @State private var colorMode: ColorMode = .cpk
    @State private var isLegendExpanded = true
    @State private var geometryAlertMessage: String?
    @State private var isAnnotationMode = false
    @State private var screenshotItem: ScreenshotItem?
    @State private var isCapturingScreenshot = false
    @State private var screenshotErrorMessage: String?
    @State private var isShowingCuratedInfo = false
    @State private var showLigands: Bool = true
    @State private var hoverInfo: HoverInfo?
    @State private var selectedResidueKey: String?
    @State private var showSequenceStrip: Bool = false

    var body: some View {
        GeometryReader { geo in
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

                if showLigands && !protein.ligandInstances.isEmpty {
                    LigandLabelsOverlay(
                        protein: protein,
                        gestureHandler: gestureHandler,
                        renderer: renderer
                    )
                    .allowsHitTesting(false)
                }

                if let info = hoverInfo {
                    HoverTooltip(atom: info.atom)
                        .position(tooltipPosition(for: info.screenPoint, in: geo.size))
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                handleHover(phase: phase, viewSize: geo.size)
            }
        }
        .navigationTitle(protein.name)
        .overlay(alignment: .bottomLeading) {
            if colorMode != .cpk {
                legendOverlay
                    .padding()
            }
        }
        .overlay(alignment: .bottom) {
            if showSequenceStrip {
                SequenceStripView(protein: protein, selectedResidueKey: $selectedResidueKey)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                if curatedEntry != nil {
                    Button {
                        isShowingCuratedInfo = true
                    } label: {
                        Label("About this protein", systemImage: "info.circle")
                    }
                }

                Button {
                    showLigands.toggle()
                } label: {
                    Label(
                        showLigands ? "Hide Ligands" : "Show Ligands",
                        systemImage: showLigands ? "atom" : "atom"
                    )
                }
                .tint(showLigands ? .orange : nil)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSequenceStrip.toggle()
                    }
                } label: {
                    Label(
                        showSequenceStrip ? "Hide Sequence" : "Show Sequence",
                        systemImage: "textformat.abc"
                    )
                }
                .tint(showSequenceStrip ? .yellow : nil)

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
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Material.bar, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            renderer.protein = protein
            renderer.representationMode = representationMode
            renderer.colorMode = colorMode
            renderer.showLigands = showLigands
            renderer.selectedResidueKey = selectedResidueKey
        }
        .onChange(of: representationMode) { _, newValue in
            renderer.representationMode = newValue
        }
        .onChange(of: colorMode) { _, newValue in
            renderer.colorMode = newValue
        }
        .onChange(of: showLigands) { _, newValue in
            renderer.showLigands = newValue
        }
        .onChange(of: selectedResidueKey) { _, newValue in
            renderer.selectedResidueKey = newValue
        }
        .onChange(of: protein.name) { _, _ in
            // Clear the residue selection when the user switches protein so the highlight
            // doesn't bleed across structures.
            selectedResidueKey = nil
        }
        .onChange(of: renderer.geometryError) { _, newValue in
            geometryAlertMessage = newValue
        }
        .sheet(item: $screenshotItem) { item in
            ScreenshotAnnotationView(baseImage: item.image)
        }
        .sheet(isPresented: $isShowingCuratedInfo) {
            if let curatedEntry {
                CuratedProteinInfoSheet(entry: curatedEntry, protein: protein)
            }
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

    // MARK: - Pencil hover

    /// Snapshot of the most recent Apple Pencil hover hit. Drives the floating tooltip.
    struct HoverInfo: Equatable {
        let screenPoint: CGPoint
        let atom: Atom
    }

    private func handleHover(phase: HoverPhase, viewSize: CGSize) {
        switch phase {
        case .active(let location):
            if let picked = renderer.pickAtom(at: location, viewSize: viewSize) {
                let info = HoverInfo(screenPoint: location, atom: picked.atom)
                if hoverInfo != info { hoverInfo = info }
            } else if hoverInfo != nil {
                hoverInfo = nil
            }
        case .ended:
            hoverInfo = nil
        }
    }

    /// Offsets the tooltip from the pencil tip and keeps it inside the visible area.
    private func tooltipPosition(for cursor: CGPoint, in viewSize: CGSize) -> CGPoint {
        let tooltipWidth: CGFloat = 200
        let tooltipHeight: CGFloat = 50
        let offset: CGFloat = 22

        var x = cursor.x + offset + tooltipWidth / 2
        var y = cursor.y - offset - tooltipHeight / 2

        // Flip the tooltip to the left of the tip if it would clip the right edge.
        if x + tooltipWidth / 2 > viewSize.width - 8 {
            x = cursor.x - offset - tooltipWidth / 2
        }
        // Drop the tooltip below the tip if it would clip the top edge.
        if y - tooltipHeight / 2 < 8 {
            y = cursor.y + offset + tooltipHeight / 2
        }
        return CGPoint(x: x, y: y)
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

// MARK: - Hover Tooltip

/// Floating, non-interactive label that follows the Apple Pencil tip during hover.
/// Shows residue identity / atom name for protein atoms, and a friendly ligand name
/// (via LigandLibrary) for HETATM atoms.
private struct HoverTooltip: View {
    let atom: Atom

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(primaryLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Text(secondaryLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        .fixedSize()
    }

    private var primaryLabel: String {
        let residue = atom.residueName.trimmingCharacters(in: .whitespacesAndNewlines)
        if atom.isLigand {
            if let friendly = LigandLibrary.commonName(for: residue) {
                return "\(residue) — \(friendly)"
            }
            return residue.isEmpty ? "Ligand" : residue
        }
        return residue.isEmpty ? "Residue" : "\(residue) \(atom.residueSeq)"
    }

    private var secondaryLabel: String {
        let atomName = atom.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chain = "Chain \(String(atom.chainID))"
        return atomName.isEmpty ? chain : "\(chain) · \(atomName)"
    }
}
