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

enum LibraryEntryKind: Hashable {
    case curated(CuratedProteinEntry)
    case imported
}

struct ProteinLibraryEntry: Identifiable, Hashable {
    let id = UUID()
    let protein: Protein
    let kind: LibraryEntryKind
    let sourceURL: URL?

    var displayName: String {
        if case .curated(let entry) = kind {
            return entry.displayName
        }
        return protein.name
    }

    var curatedEntry: CuratedProteinEntry? {
        if case .curated(let entry) = kind {
            return entry
        }
        return nil
    }
}

// MARK: - Library Category

enum LibraryCategory: String, CaseIterable, Identifiable, Hashable {
    case curated = "Curated Library"
    case imported = "My Files"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .curated: return "books.vertical.fill"
        case .imported: return "tray.full"
        }
    }
}

// MARK: - Library View Model

@MainActor
final class ProteinLibraryViewModel: ObservableObject {
    @Published var proteins: [ProteinLibraryEntry] = []
    @Published var missingCuratedEntries: [CuratedProteinEntry] = []
    @Published var selectedProteinID: ProteinLibraryEntry.ID?
    @Published var activeAlert: ProteinLibraryAlert?

    init() {
        Task {
            await loadCuratedLibrary()
            if !proteins.contains(where: { if case .imported = $0.kind { return true } else { return false } }) {
                await loadBundledSample()
            }
            if selectedProteinID == nil, let first = curatedEntries.first ?? proteins.first {
                selectedProteinID = first.id
            }
        }
    }

    // MARK: - Computed

    var selectedProtein: Protein? {
        proteins.first(where: { $0.id == selectedProteinID })?.protein
    }

    var selectedEntry: ProteinLibraryEntry? {
        proteins.first(where: { $0.id == selectedProteinID })
    }

    var curatedEntries: [ProteinLibraryEntry] {
        proteins.filter {
            if case .curated = $0.kind { return true }
            return false
        }
    }

    var importedEntries: [ProteinLibraryEntry] {
        proteins.filter {
            if case .imported = $0.kind { return true }
            return false
        }
    }

    /// Returns the category that owns the currently-selected protein, or nil if nothing is selected.
    var categoryOfSelection: LibraryCategory? {
        guard let entry = selectedEntry else { return nil }
        switch entry.kind {
        case .curated: return .curated
        case .imported: return .imported
        }
    }

    // MARK: - Loading

    func loadCuratedLibrary() async {
        let manifest: CuratedManifest
        do {
            manifest = try CuratedLibraryLoader.loadManifest()
        } catch {
            return
        }

        for entry in manifest.proteins {
            if CuratedLibraryLoader.bundleURL(for: entry) != nil {
                do {
                    let protein = try await CuratedLibraryLoader.loadProtein(for: entry)
                    let libraryEntry = ProteinLibraryEntry(
                        protein: protein,
                        kind: .curated(entry),
                        sourceURL: nil
                    )
                    proteins.append(libraryEntry)
                } catch {
                    missingCuratedEntries.append(entry)
                }
            } else {
                missingCuratedEntries.append(entry)
            }
        }
    }

    func loadBundledSample() async {
        guard let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "pdb") else {
            return
        }
        do {
            let protein = try await PDBParser.parse(from: sampleURL)
            let entry = ProteinLibraryEntry(protein: protein, kind: .imported, sourceURL: sampleURL)
            proteins.append(entry)
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
            let entry = ProteinLibraryEntry(protein: protein, kind: .imported, sourceURL: url)
            proteins.append(entry)
            selectedProteinID = entry.id
        } catch {
            activeAlert = ProteinLibraryAlert(message: error.localizedDescription)
        }
    }
}

// MARK: - Category Sidebar (column 1)

struct CategorySidebar: View {
    @Binding var selection: LibraryCategory?

    var body: some View {
        List(selection: $selection) {
            ForEach(LibraryCategory.allCases) { category in
                Label(category.rawValue, systemImage: category.systemImage)
                    .tag(category)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ProteinViz")
    }
}

// MARK: - Protein List (column 2)

struct ProteinListView: View {
    let category: LibraryCategory
    @ObservedObject var viewModel: ProteinLibraryViewModel
    @State private var isPresentingImporter = false
    @State private var missingEntryForInstructions: CuratedProteinEntry?

    private var pdbContentType: UTType {
        UTType(filenameExtension: "pdb") ?? .data
    }

    var body: some View {
        List(selection: $viewModel.selectedProteinID) {
            switch category {
            case .curated:
                if !viewModel.curatedEntries.isEmpty {
                    Section("Available") {
                        ForEach(viewModel.curatedEntries) { entry in
                            curatedRow(for: entry).tag(entry.id)
                        }
                    }
                }
                if !viewModel.missingCuratedEntries.isEmpty {
                    Section("Not bundled") {
                        ForEach(viewModel.missingCuratedEntries) { entry in
                            missingRow(for: entry)
                        }
                    }
                }
                if viewModel.curatedEntries.isEmpty && viewModel.missingCuratedEntries.isEmpty {
                    ContentUnavailableView("No curated entries", systemImage: "books.vertical", description: Text("curated.json was not found or had no proteins."))
                }
            case .imported:
                if viewModel.importedEntries.isEmpty {
                    ContentUnavailableView(
                        "No imports yet",
                        systemImage: "tray",
                        description: Text("Tap Import PDB below to load a structure from Files.")
                    )
                } else {
                    ForEach(viewModel.importedEntries) { entry in
                        importedRow(for: entry).tag(entry.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if category == .imported {
                importButton
            }
        }
        .sheet(item: $missingEntryForInstructions) { entry in
            MissingCuratedSheet(entry: entry)
        }
    }

    // MARK: - Rows

    private func curatedRow(for entry: ProteinLibraryEntry) -> some View {
        let curated = entry.curatedEntry
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.headline)
            if let curated {
                Text(curated.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(curated.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func importedRow(for entry: ProteinLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.headline)
            Text(entry.protein.pdbID ?? "\(entry.protein.atomCount) atoms")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func missingRow(for entry: CuratedProteinEntry) -> some View {
        Button {
            missingEntryForInstructions = entry
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap to bundle \(entry.fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(0.7)
                }
                Spacer()
                Image(systemName: "tray.and.arrow.down")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var importButton: some View {
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
                guard let url = urls.first else { return }
                Task {
                    await viewModel.importProtein(from: url)
                }
            case .failure(let error):
                viewModel.activeAlert = ProteinLibraryAlert(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Missing Curated Sheet

private struct MissingCuratedSheet: View {
    let entry: CuratedProteinEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.summary)
                        .font(.body)
                } header: {
                    Text(entry.displayName)
                }

                Section("Add it to the bundle") {
                    Text("1. Download the PDB file from RCSB (\(entry.pdbID)).")
                    Text("2. Rename the file to **\(entry.fileName)**.")
                    Text("3. Drag it into the **Resources/** group in Xcode and check the ProteinViz target.")
                    Text("4. Rebuild and relaunch — the entry will move into the Available section.")
                }

                Section("Links") {
                    if let structureURL = entry.rcsbStructureURL {
                        Button {
                            openURL(structureURL)
                        } label: {
                            Label("Open RCSB Structure Page", systemImage: "safari")
                        }
                    }
                    if let downloadURL = entry.rcsbDownloadURL {
                        Button {
                            openURL(downloadURL)
                        } label: {
                            Label("Download \(entry.pdbID).pdb", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }
            .navigationTitle("Missing PDB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
