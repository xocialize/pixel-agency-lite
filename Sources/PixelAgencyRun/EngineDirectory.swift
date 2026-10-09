import Foundation
import MESClientKit
import MESCore
import Observation

/// One engine as the user sees it in the picker (LITE-1): found on the network, added by address, paired, or several
/// of these at once.
public struct EngineEntry: Identifiable, Sendable, Hashable {
    /// The engine's id when known, otherwise its address or service name.
    public var id: String
    public var name: String
    /// Where to reach it, once known (discovered engines resolve on connect).
    public var url: URL?
    public var auth: AuthMode?
    /// `image/0.1`, …
    public var profiles: [String]
    /// The Base versions it speaks.
    public var specVersions: [String]
    public var version: String?
    /// The engine's own load hint from DNS-SD (Base §3.1), if it publishes one.
    public var load: String?
    public var isPaired: Bool
    public var isDiscovered: Bool
    public var isAdded: Bool

    /// Paired mode needs a pairing before anything but the handshake works (Base §3.3).
    public var needsPairing: Bool { auth == .paired && !isPaired }

    var discovered: DiscoveredEngine?
    public static func == (a: EngineEntry, b: EngineEntry) -> Bool {
        a.id == b.id && a.name == b.name && a.url == b.url && a.isPaired == b.isPaired && a.isDiscovered == b.isDiscovered
            && a.load == b.load && a.profiles == b.profiles
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The engines this client knows (LITE-1, LITE-2): found over DNS-SD, added by address, and paired. It connects to
/// them, pairs with them, and keeps pairings in a `CredentialStore`.
@MainActor @Observable
public final class EngineDirectory {
    public private(set) var entries: [EngineEntry] = []
    /// Engines added by address, kept across launches.
    public private(set) var addedURLs: [URL]
    let credentials: CredentialStore
    let clientName: String
    let defaults: UserDefaults
    private var found: [DiscoveredEngine] = []
    private var addedInfo: [URL: EngineInfo] = [:]
    private var browsing: Task<Void, Never>?

    static let addedKey = "PixelAgency.addedEngines"

    /// - Parameters:
    ///   - clientName: how this client appears on an engine's pairing prompt, e.g. "Pixel Agency Lite on Studio Mac".
    public init(credentials: CredentialStore, clientName: String, defaults: UserDefaults = .standard) {
        self.credentials = credentials
        self.clientName = clientName
        self.defaults = defaults
        addedURLs = (defaults.stringArray(forKey: Self.addedKey) ?? []).compactMap(URL.init(string:))
        rebuild()
    }

    // MARK: - Finding engines

    /// Starts browsing `_mes-engine._tcp` (Base §3.1); the list updates as engines come and go.
    public func startBrowsing() {
        guard browsing == nil else { return }
        browsing = Task { [weak self] in
            for await engines in EngineBrowser.browse() {
                guard let self else { return }
                self.found = engines
                self.rebuild()
            }
        }
    }

    public func stopBrowsing() {
        browsing?.cancel()
        browsing = nil
    }

    /// Adds an engine by its base URL (`http://host:port/mes/v0`), reading its handshake (`GET engine`, which needs
    /// no token even in paired mode).
    @discardableResult
    public func add(url: URL) async throws -> EngineEntry {
        let info = try await HTTPEngineConnection(baseURL: url, trustOnFirstUse: url.scheme == "https").engineInfo()
        addedInfo[url] = info
        if !addedURLs.contains(url) {
            addedURLs.append(url)
            defaults.set(addedURLs.map(\.absoluteString), forKey: Self.addedKey)
        }
        rebuild()
        return entries.first { $0.id == info.id }!
    }

    /// Forgets an added engine and any pairing with it (unpairing on the engine when reachable).
    public func forget(_ entry: EngineEntry) async {
        if let paired = credentials.pairings().first(where: { $0.engineID == entry.id }) {
            try? await Pairing.unpair(paired)
            try? credentials.remove(engineID: paired.engineID)
        }
        addedURLs.removeAll { url in addedInfo[url]?.id == entry.id || url == entry.url }
        defaults.set(addedURLs.map(\.absoluteString), forKey: Self.addedKey)
        rebuild()
    }

    // MARK: - Connecting and pairing

    /// A connection to `entry`: resolving a discovered engine's address, and using its pairing when paired.
    public func connect(_ entry: EngineEntry) async throws -> HTTPEngineConnection {
        let url = try await address(of: entry)
        if let paired = credentials.pairings().first(where: { $0.engineID == entry.id }) {
            var current = paired
            current.baseURL = url                                     // addresses change; the pinned certificate doesn't
            return HTTPEngineConnection(paired: current)
        }
        guard !entry.needsPairing else {
            throw MESClientError.unexpected("\(entry.name) needs pairing first.")
        }
        return HTTPEngineConnection(baseURL: url)
    }

    /// Starts pairing (Base §5 steps 1–4): the returned `Pairing` carries the code to show.
    public func beginPairing(_ entry: EngineEntry) async throws -> Pairing {
        try await Pairing.begin(baseURL: try await address(of: entry), identity: try credentials.identity(name: clientName))
    }

    /// Waits up to `wait` seconds for the engine's operator (step 5). On approval the pairing is saved; returns whether
    /// it was approved. Throws `pairing_rejected` or `gone`.
    public func completePairing(_ pairing: Pairing, wait: Int = 60) async throws -> Bool {
        guard case .approved(let engine) = try await pairing.confirm(wait: wait) else { return false }
        try credentials.save(engine)
        rebuild()
        return true
    }

    func address(of entry: EngineEntry) async throws -> URL {
        if let url = entry.url { return url }
        guard let discovered = entry.discovered else { throw MESClientError.unexpected("No address for \(entry.name).") }
        return try await discovered.resolve()
    }

    // MARK: - The list

    func rebuild() {
        var byID: [String: EngineEntry] = [:]
        var order: [String] = []
        func merge(_ e: EngineEntry) {
            if var existing = byID[e.id] {
                existing.url = existing.url ?? e.url
                existing.auth = existing.auth ?? e.auth
                if existing.profiles.isEmpty { existing.profiles = e.profiles }
                if existing.specVersions.isEmpty { existing.specVersions = e.specVersions }
                existing.version = existing.version ?? e.version
                existing.load = e.load ?? existing.load
                existing.isPaired = existing.isPaired || e.isPaired
                existing.isDiscovered = existing.isDiscovered || e.isDiscovered
                existing.isAdded = existing.isAdded || e.isAdded
                existing.discovered = existing.discovered ?? e.discovered
                byID[e.id] = existing
            } else {
                byID[e.id] = e
                order.append(e.id)
            }
        }
        for url in addedURLs {
            let info = addedInfo[url]
            merge(EngineEntry(id: info?.id ?? url.absoluteString, name: info?.name ?? url.host ?? url.absoluteString, url: url,
                              auth: info?.auth, profiles: info?.profiles.flatMap { p in p.versions.map { "\(p.id)/\($0)" } } ?? [],
                              specVersions: info?.baseVersions ?? [], version: info?.implementation.version, load: nil,
                              isPaired: false, isDiscovered: false, isAdded: true))
        }
        for d in found {
            merge(EngineEntry(id: d.id, name: d.serviceName, url: nil, auth: d.auth, profiles: d.profiles, specVersions: d.baseVersions,
                              version: d.version, load: d.txt["load"], isPaired: false, isDiscovered: true, isAdded: false, discovered: d))
        }
        for p in credentials.pairings() {
            merge(EngineEntry(id: p.engineID, name: p.engineName, url: nil, auth: .paired, profiles: [], specVersions: [], version: nil,
                              load: nil, isPaired: true, isDiscovered: false, isAdded: false))
            // A paired engine not currently discovered is reached at its last known address.
            if byID[p.engineID]?.url == nil && byID[p.engineID]?.discovered == nil { byID[p.engineID]?.url = p.baseURL }
        }
        entries = order.compactMap { byID[$0] }.sorted { a, b in
            if a.isPaired != b.isPaired { return a.isPaired }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
