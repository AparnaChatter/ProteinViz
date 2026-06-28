//
//  ContentView.swift
//  ProteinViz
//

import SwiftUI
import simd

// MARK: - Root Content View

struct ContentView: View {
    @StateObject private var libraryViewModel = ProteinLibraryViewModel()
    @StateObject private var gestureHandler = GestureHandler()
    @StateObject private var renderer = MetalRenderer()
    @StateObject private var annotationStore = AnnotationStore()

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(viewModel: libraryViewModel)
        } detail: {
            if let protein = libraryViewModel.selectedProtein {
                ProteinDetailView(
                    protein: protein,
                    renderer: renderer,
                    gestureHandler: gestureHandler,
                    annotationStore: annotationStore,
                    curatedEntry: libraryViewModel.selectedEntry?.curatedEntry
                )
            } else {
                placeholderView
            }
        }
        .onAppear {
            renderer.gestureHandler = gestureHandler
            renderer.protein = libraryViewModel.selectedProtein
            applyCameraHint(for: libraryViewModel.selectedEntry)
        }
        .onChange(of: libraryViewModel.selectedProteinID) { _, _ in
            renderer.protein = libraryViewModel.selectedProtein
            applyCameraHint(for: libraryViewModel.selectedEntry)
        }
        .alert(item: $libraryViewModel.activeAlert) { alert in
            Alert(title: Text("Protein Import Failed"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Camera Hint

    private func applyCameraHint(for entry: ProteinLibraryEntry?) {
        guard let curated = entry?.curatedEntry else {
            gestureHandler.resetCamera()
            return
        }
        gestureHandler.rotation = curated.initialRotationQuaternion ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        gestureHandler.zoom = curated.initialZoom ?? 1.0
        gestureHandler.panOffset = .zero
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Pick a protein to begin")
                    .font(.title2.weight(.semibold))
                Text("The Curated Library walks through the major protein families with built-in tutorial hints.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .padding(24)
        }
    }
}

#Preview {
    ContentView()
}
