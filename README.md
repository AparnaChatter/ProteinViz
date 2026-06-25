    # ProteinViz

ProteinViz is an iPad-native molecular visualization app built with SwiftUI and Metal.

## Phase 1 Scope

- Load `.pdb` files from the Files app
- Parse `ATOM` and `HETATM` records
- Render atoms as colored sphere impostors with Metal
- Support one-finger rotate, two-finger pan, and pinch zoom
- Start with a bundled sample protein so the app opens with content immediately

## Project Structure

- `ProteinViz/App/ProteinVizApp.swift` — app entry point
- `ProteinViz/Models/` — `Atom` and `Protein`
- `ProteinViz/Parsing/PDBParser.swift` — async PDB parser
- `ProteinViz/Rendering/` — Metal renderer, render types, and shaders
- `ProteinViz/Views/` — split-view shell, sidebar, detail, and Metal wrapper
- `ProteinViz/Gestures/` — shared gesture state
- `ProteinViz/Resources/sample.pdb` — bundled starter structure

## Notes

This implementation is an original Phase 1 scaffold inspired by the general architecture and sphere-impostor approach used in BioViewer, which is cited in the code comments.
