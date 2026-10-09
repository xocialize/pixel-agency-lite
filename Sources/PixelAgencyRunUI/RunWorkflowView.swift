import DesignScaffold
import DesignScaffoldWorkspace
import MESClientKit
import MESCore
import PixelAgencyRun
import SwiftUI

/// The whole run workflow (LITE-16): engines, operations and this session's runs on the left; the picture in the
/// middle; the operation's controls and what happened on the right. Lite's window is this view; Desktop embeds it.
public struct RunWorkflowView: View {
    @Bindable var workflow: RunWorkflow
    /// Where "Save" puts results (the working folder, LITE-17).
    let saveFolder: URL?

    public init(workflow: RunWorkflow, saveFolder: URL?) {
        self.workflow = workflow
        self.saveFolder = saveFolder
    }

    public var body: some View {
        WorkspaceSplit {
            Sidebar(workflow: workflow)
        } center: {
            Canvas(workflow: workflow, saveFolder: saveFolder)
        } trailing: {
            Inspector(workflow: workflow)
        }
        .sheet(isPresented: Binding(get: { workflow.pairing != nil }, set: { if !$0 { workflow.cancelPairing() } })) {
            if let pairing = workflow.pairing { PairingSheet(pairing: pairing) { workflow.cancelPairing() } }
        }
        .onAppear { workflow.directory.startBrowsing() }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Bindable var workflow: RunWorkflow
    @State private var addingEngine = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    SectionHeader("Engines") {
                        Button { addingEngine = true } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless).help("Add an engine by address")
                    }
                    if workflow.directory.entries.isEmpty {
                        Text("Looking for engines on your network…")
                            .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
                    }
                    ForEach(workflow.directory.entries) { entry in
                        Button { Task { await workflow.select(entry) } } label: {
                            EngineRow(entry: entry, selected: workflow.engine?.id == entry.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Forget") { Task { await workflow.directory.forget(entry) } }
                        }
                    }
                }
                if !workflow.operations.isEmpty {
                    ForEach(workflow.groupedOperations, id: \.profile) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            SectionHeader(group.profile)
                            ForEach(group.operations, id: \.operation) { d in
                                Button { workflow.choose(d) } label: {
                                    OperationRow(descriptor: d, selected: workflow.current?.descriptor.operation == d.operation)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !workflow.log.runs.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionHeader("This session", trailing: "\(workflow.log.runs.count)")
                        ForEach(workflow.log.runs) { run in
                            Button { workflow.show(run) } label: { SessionRow(run: run, selected: workflow.current === run) }
                                .buttonStyle(.plain)
                        }
                        Text("Cleared when Lite quits. Save what you want to keep.")
                            .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.tertiaryLabel)
                    }
                }
            }
            .padding(Tokens.Space.m)
        }
        .sheet(isPresented: $addingEngine) { AddEngineSheet(workflow: workflow, isPresented: $addingEngine) }
    }
}

struct EngineRow: View {
    let entry: EngineEntry
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1)
                Text(detail).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.xs)
        .background(selected ? Tokens.Color.selectionWash : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var color: Color { entry.needsPairing ? Tokens.Color.degraded : entry.isDiscovered || entry.isPaired ? Tokens.Color.ready : Tokens.Color.tertiaryLabel }

    /// LITE-1: profiles, spec version, load and pairing state.
    var detail: String {
        var parts: [String] = []
        if !entry.profiles.isEmpty { parts.append(entry.profiles.joined(separator: ", ")) }
        if let v = entry.specVersions.first { parts.append("MES \(v)") }
        if let load = entry.load { parts.append("load \(load)") }
        parts.append(entry.isPaired ? "paired" : entry.needsPairing ? "needs pairing" : entry.auth == .open ? "this Mac" : "")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct OperationRow: View {
    let descriptor: Descriptor
    let selected: Bool

    var body: some View {
        HStack {
            Text(descriptor.title)
            Spacer()
            Text(descriptor.operation.split(separator: ".").last.map(String.init) ?? "")
                .font(Tokens.Font.mono).foregroundStyle(Tokens.Color.tertiaryLabel)
        }
        .padding(.vertical, 3).padding(.horizontal, Tokens.Space.xs)
        .background(selected ? Tokens.Color.selectionWash : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SessionRow: View {
    let run: RunSession
    let selected: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Thumbnail(file: run.results.first(where: \.isImage)?.file, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.descriptor.title).lineLimit(1)
                Text(PhaseText.short(run.phase)).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.xs)
        .background(selected ? Tokens.Color.selectionWash : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .contentShape(Rectangle())
    }
}

/// LITE-1: connect by address.
struct AddEngineSheet: View {
    let workflow: RunWorkflow
    @Binding var isPresented: Bool
    @State private var address = "http://127.0.0.1:17600/mes/v0"
    @State private var problem: String?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Add an engine").font(Tokens.Font.panelTitle)
            Text("Its base URL: http://host:port/mes/v0 for an engine on this Mac, https://… for a paired engine on your network.")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            TextField("Address", text: $address).textFieldStyle(.roundedBorder).font(Tokens.Font.mono)
            if let problem { Text(problem).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.failure) }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let url = URL(string: address) else { problem = "That isn't a URL."; return }
                    adding = true
                    Task {
                        do {
                            let entry = try await workflow.directory.add(url: url)
                            isPresented = false
                            await workflow.select(entry)
                        } catch { problem = "\(error)" }
                        adding = false
                    }
                }
                .keyboardShortcut(.defaultAction).disabled(adding)
            }
        }
        .padding(Tokens.Space.l)
        .frame(width: 420)
    }
}

/// Base §5 step 4, the client's half: the code, and what to do with it.
struct PairingSheet: View {
    let pairing: Pairing
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.l) {
            Text("Pair with \(pairing.engine.name)").font(Tokens.Font.panelTitle)
            Text(pairing.code.prefix(3) + " " + pairing.code.suffix(3))
                .font(.system(size: 44, weight: .semibold, design: .monospaced)).monospacedDigit()
                .accessibilityLabel("Pairing code \(pairing.code.map(String.init).joined(separator: " "))")
            Text("Check that the engine shows the same code, then approve the pairing there. A different code means someone may be in between: don't approve.")
                .multilineTextAlignment(.center).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Tokens.Space.s) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            }
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
        .padding(Tokens.Space.xl)
        .frame(width: 380)
    }
}

/// Short descriptions of a run's phase.
enum PhaseText {
    static func short(_ phase: RunSession.Phase) -> String {
        switch phase {
        case .editing: "Not run yet"
        case .submitting: "Sending…"
        case .running(let state, _, let fraction, _):
            fraction.map { "\(state.rawValue) \(Int($0 * 100))%" } ?? state.rawValue.capitalized
        case .collecting: "Collecting…"
        case .finished: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// A small image from a file, or a placeholder.
struct Thumbnail: View {
    let file: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let file, let image = NSImage(contentsOf: file) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(Tokens.Color.tertiaryLabel)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
