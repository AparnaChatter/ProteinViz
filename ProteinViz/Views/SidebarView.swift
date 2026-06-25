//
//  SidebarView.swift
//  ProteinViz
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Alerts

struct ProteinLibraryAlert: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Library Entry

struct ProteinLibraryEntry: Identifiable, Hashable {
    let id = UUID()
    let protein: Protein
    let sourceURL: URL?

    var name: String {
        protein.name
    }
}

// MARK: - Library View Model

@MainActor
final class ProteinLibraryViewModel: ObservableObject {
    @Published var proteins: [ProteinLibraryEntry] = []
    @Published var selectedProteinID: ProteinLibraryEntry.ID?
    @Published var activeAlert: ProteinLibraryAlert?

    init() {
        Task {
            await loadBundledSample()
        }
    }

    var selectedProtein: Protein? {
        proteins.first(where: { $0.id == selectedProteinID })?.protein
    }

    // MARK: - Loading

    func loadBundledSample() async {
        guard proteins.isEmpty else {
            return
        }

        guard let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "pdb") else {
            activeAlert = ProteinLibraryAlert(message: "The bundled sample PDB file could not be found in the app bundle.")
            return
        }

        do {
            let protein = try await PDBParser.parse(from: sampleURL)
            let entry = ProteinLibraryEntry(protein: protein, sourceURL: sampleURL)
            proteins = [entry]
            selectedProteinID = entry.id
        } catch {
            activeAlert = ProteinLibraryAlert(message: error.localizedDescription)
        }
    }

    func importProtein(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let protein = try await PDBParser.parse(from: url)
            let entry = ProteinLibraryEntry(protein: protein, sourceURL: url)
            proteins.append(entry)
            selectedProteinID = entry.id
        } catch {
            activeAlert = ProteinLibraryAlert(message: error.localizedDescription)
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var viewModel: ProteinLibraryViewModel
    @State private var isPresentingImporter = false

    private var pdbContentType: UTType {
        UTType(filenameExtension: "pdb") ?? .data
    }

    var body: some View {
        List(selection: $viewModel.selectedProteinID) {
            Section("Loaded Proteins") {
                ForEach(viewModel.proteins) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.headline)
                        Text("\(entry.protein.atomCount) atoms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(entry.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ProteinViz")
        .safeAreaInset(edge: .bottom) {
            Button {
                isPresentingImporter = true
            } label: {
                Label("Import PDB", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .fileImporter(
                isPresented: $isPresentingImporter,
                allowedContentTypes: [pdbContentType],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        return
                    }
                    Task {
                        await viewModel.importProtein(from: url)
                    }
                case .failure(let error):
                    viewModel.activeAlert = ProteinLibraryAlert(message: error.localizedDescription)
                }
            }
        }
    }
}
