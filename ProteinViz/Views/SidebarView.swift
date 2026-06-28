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

// MARK: - Library Sidebar (single column, nested DisclosureGroups)

struct LibrarySidebar: View {
    @ObservedObject var viewModel: ProteinLibraryViewModel
    /// Tracks which groups the user has collapsed. Default empty = every group expanded.
    @State private var collapsedGroups: Set<String> = []
    @State private var isPresentingImporter = false
    @State private var missingEntryForInstructions: CuratedProteinEntry?

    private var pdbContentType: UTType {
        UTType(filenameExtension: "pdb") ?? .data
    }

    /// Canonical display order for biological function classes. Unknown classes fall to the
    /// end alphabetically.
    private static let functionClassOrder: [String] = [
        "Catalytic",
        "Structural",
        "Transport",
        "Hormonal",
        "Defense",
        "Contractile",
        "Regulatory",
        "Reporter",
        "Storage",
        "Other"
    ]

    var body: some View {
        List(selection: $viewModel.selectedProteinID) {
            curatedDisclosure
            importedDisclosure
        }
        .listStyle(.sidebar)
        .navigationTitle("ProteinViz")
        .safeAreaInset(edge: .bottom) {
            importButton
        }
        .sheet(item: $missingEntryForInstructions) { entry in
            MissingCuratedSheet(entry: entry)
        }
    }

    // MARK: - Top-level disclosure groups

    private var curatedDisclosure: some View {
        DisclosureGroup(isExpanded: binding(for: "group:curated")) {
            ForEach(groupedCurated, id: \.0) { className, entries in
                DisclosureGroup(isExpanded: binding(for: "class:\(className)")) {
                    ForEach(entries) { entry in
                        curatedRow(for: entry).tag(entry.id)
                    }
                } label: {
                    Text(className)
                        .font(.subheadline.weight(.semibold))
                }
            }
            if !viewModel.missingCuratedEntries.isEmpty {
                DisclosureGroup(isExpanded: binding(for: "group:notBundled")) {
                    ForEach(viewModel.missingCuratedEntries) { entry in
                        missingRow(for: entry)
                    }
                } label: {
                    Text("Not bundled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Curated Library", systemImage: "books.vertical.fill")
                .font(.headline)
        }
    }

    private var importedDisclosure: some View {
        DisclosureGroup(isExpanded: binding(for: "group:imported")) {
            if viewModel.importedEntries.isEmpty {
                Text("No imported PDB files yet. Tap Import below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.importedEntries) { entry in
                    importedRow(for: entry).tag(entry.id)
                }
            }
        } label: {
            Label("My Files", systemImage: "tray.full")
                .font(.headline)
        }
    }

    // MARK: - Grouping

    private func functionClassKey(for entry: ProteinLibraryEntry) -> String {
        entry.curatedEntry?.functionClass ?? "Other"
    }

    private var groupedCurated: [(String, [ProteinLibraryEntry])] {
        let grouped = Dictionary(grouping: viewModel.curatedEntries, by: functionClassKey)
        let knownOrdered: [(String, [ProteinLibraryEntry])] = Self.functionClassOrder.compactMap { cls in
            guard let entries = grouped[cls], !entries.isEmpty else { return nil }
            return (cls, entries.sorted { $0.displayName < $1.displayName })
        }
        let knownSet = Set(Self.functionClassOrder)
        let extras = grouped
            .filter { !knownSet.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.displayName < $1.displayName }) }
        return knownOrdered + extras
    }

    // MARK: - Rows

    private func curatedRow(for entry: ProteinLibraryEntry) -> some View {
        let curated = entry.curatedEntry
        return VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(.body)
            if let curated {
                Text(curated.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    private func importedRow(for entry: ProteinLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(.body)
            Text(entry.protein.pdbID ?? "\(entry.protein.atomCount) atoms")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }

    private func missingRow(for entry: CuratedProteinEntry) -> some View {
        Button {
            missingEntryForInstructions = entry
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Bundle \(entry.fileName) to enable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(0.7)
                }
                Spacer()
                Image(systemName: "tray.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import

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

    // MARK: - Collapsed-group bookkeeping

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(key) },
            set: { isOpen in
                if isOpen {
                    collapsedGroups.remove(key)
                } else {
                    collapsedGroups.insert(key)
                }
            }
        )
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
                    Text("4. Rebuild and relaunch — the entry will move into the active Curated section.")
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
