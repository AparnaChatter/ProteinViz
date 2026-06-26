//
//  ContentView.swift
//  ProteinViz
//

import SwiftUI

// MARK: - Root Content View

struct ContentView: View {
    @StateObject private var libraryViewModel = ProteinLibraryViewModel()
    @StateObject private var gestureHandler = GestureHandler()
    @StateObject private var renderer = MetalRenderer()
    @StateObject private var annotationStore = AnnotationStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: libraryViewModel)
        } detail: {
            if let protein = libraryViewModel.selectedProtein {
                ProteinDetailView(
                    protein: protein,
                    renderer: renderer,
                    gestureHandler: gestureHandler,
                    annotationStore: annotationStore
                )
            } else {
                placeholderView
            }
        }
        .onAppear {
            renderer.gestureHandler = gestureHandler
            renderer.protein = libraryViewModel.selectedProtein
        }
        .onChange(of: libraryViewModel.selectedProteinID) { _, _ in
            renderer.protein = libraryViewModel.selectedProtein
        }
        .alert(item: $libraryViewModel.activeAlert) { alert in
            Alert(title: Text("Protein Import Failed"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Import a PDB file to begin")
                    .font(.title2.weight(.semibold))
                Text("A bundled sample protein will appear automatically on first launch.")
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
