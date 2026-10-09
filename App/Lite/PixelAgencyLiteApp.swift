import AppKit
import DesignScaffold
import PixelAgencyRun
import PixelAgencyRunUI
import SwiftUI

/// Pixel Agency Lite: a thin app around the open run workflow (LITE-16). It adds the working folder (APP-3–5),
/// settings, and the end of the session at quit (LITE-11).
@main
struct PixelAgencyLiteApp: App {
    @NSApplicationDelegateAdaptor(LiteAppDelegate.self) var appDelegate
    @State private var lite = LiteModel.shared

    var body: some Scene {
        Window("Pixel Agency Lite", id: "main") {
            LiteRoot(lite: lite)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unifiedCompact)
        Settings {
            LiteSettings(lite: lite)
        }
    }
}

/// The app's state: the working folder, the session, and the run workflow over the engines this Mac knows.
@MainActor @Observable
final class LiteModel {
    static let shared = LiteModel()
    /// MDM-presettable (README APP-10): managed preferences in the app's defaults domain.
    static let commercialOnlyKey = "PixelAgency.commercialOnlyByDefault"

    let folder = WorkingFolder()
    let log = SessionLog()
    let workflow: RunWorkflow

    private init() {
        let directory = EngineDirectory(credentials: KeychainCredentialStore(prefix: "PixelAgency.Lite"),
                                        clientName: "Pixel Agency Lite on \(Host.current().localizedName ?? "a Mac")")
        workflow = RunWorkflow(directory: directory, log: log)
        workflow.commercialOnlyByDefault = UserDefaults.standard.bool(forKey: Self.commercialOnlyKey)
    }

    /// Ends the session (LITE-11): collected results not saved are deleted; the working folder is released.
    func end() {
        log.clear()
        folder.stop()
    }
}

final class LiteAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LiteModel.shared.end() }
    }
}

struct LiteRoot: View {
    let lite: LiteModel

    var body: some View {
        switch lite.folder.status {
        case .ready(let url):
            RunWorkflowView(workflow: lite.workflow, saveFolder: url)
                .frame(minWidth: Tokens.Layout.minWindowWidth, minHeight: Tokens.Layout.minWindowHeight)
        default:
            WorkingFolderOnboarding(folder: lite.folder, appName: "Pixel Agency Lite",
                                    purpose: "Results you save go there; everything else from a session is cleared when you quit.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct LiteSettings: View {
    let lite: LiteModel
    @AppStorage(LiteModel.commercialOnlyKey) private var commercialOnly = false
    @State private var changing = false

    var body: some View {
        Form {
            Section("Working folder") {
                LabeledContent("Results are saved to") {
                    Text(lite.folder.url?.path ?? "Not chosen").font(Tokens.Font.mono).lineLimit(1).truncationMode(.middle)
                }
                Button("Change…") { changing = true }
                Text("Changing the folder doesn't move anything: results already saved stay where they are.")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            }
            Section("Models") {
                Toggle("Commercial-use models only", isOn: $commercialOnly)
                    .onChange(of: commercialOnly) { _, on in lite.workflow.commercialOnlyByDefault = on }
                Text("When on, new runs ask engines for models whose licence allows commercial use. Every result shows its model's licence either way.")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            }
            Section("About") {
                LabeledContent("Pixel Agency Lite", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("Licence", value: "Apache-2.0, open source")
                LabeledContent("Speaks", value: "Media Engine Specification · Base 0.1")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fileImporter(isPresented: $changing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try? lite.folder.choose(url)
            }
        }
    }
}
