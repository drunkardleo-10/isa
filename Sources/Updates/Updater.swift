import AppKit
import Combine
import CryptoKit
import Security

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let feed: URL = {
        if let custom = ProcessInfo.processInfo.environment["ISA_FEED"], let url = URL(string: custom) {
            return url
        }
        if let searchFeed = ProcessInfo.processInfo.environment["SEARCH_FEED"], let url = URL(string: searchFeed) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/drunkardleo-10/isa/main/appcast.json")!
    }()

    struct Release: Equatable {
        let version: String
        let build: Int
        let archive: URL
        let dmg: URL
        let sha256: String?
        let notes: String?
        let minimumSystemVersion: String?

        var runsHere: Bool {
            guard let need = minimumSystemVersion else { return true }
            let parts = need.split(separator: ".").map { Int($0) ?? 0 }
            let least = OperatingSystemVersion(
                majorVersion: parts.count > 0 ? parts[0] : 0,
                minorVersion: parts.count > 1 ? parts[1] : 0,
                patchVersion: parts.count > 2 ? parts[2] : 0
            )
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(least)
        }
    }

    enum Stage: Equatable {
        case none
        case fetching(Release)
        case ready(Release)
        case offered(Release)
        case waiting(Release)
    }

    @Published private(set) var stage: Stage = .none
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?

    nonisolated static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    nonisolated static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 1000
    }

    private let lastCheckKey = "isa.update.lastChecked"
    static let autoUpdateKey = "autoCheckUpdates"

    private var installsAutomatically: Bool {
        if UserDefaults.standard.object(forKey: Updater.autoUpdateKey) != nil {
            return UserDefaults.standard.bool(forKey: Updater.autoUpdateKey)
        }
        return true
    }

    private var clock: Timer?

    private init() {
        if let stored = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            self.lastChecked = stored
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Swap.sweep()
        }
    }

    func checkIfDue() {
        Swap.sweep()
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkIfDueInternal()
                }
            }
            clock?.tolerance = 300
        }
        checkIfDueInternal()
    }

    private func checkIfDueInternal() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        let interval = Date().timeIntervalSince(last)
        guard interval > 72000 || ProcessInfo.processInfo.environment["ISA_FEED"] != nil else { return }
        check(silent: true)
    }

    func check(silent: Bool = false, then done: ((Release?) -> Void)? = nil) {
        guard !checking else { return }
        checking = true
        Task { [weak self] in
            let found = await Updater.fetch()
            guard let self else { return }
            self.checking = false
            let now = Date()
            self.lastChecked = now
            UserDefaults.standard.set(now, forKey: self.lastCheckKey)

            guard let found, found.build > Updater.build, found.runsHere else {
                if case .ready = self.stage {} else {
                    self.stage = .none
                }
                done?(nil)
                return
            }

            done?(found)

            if self.installsAutomatically {
                self.take(found)
            } else {
                switch self.stage {
                case .fetching, .ready:
                    break
                case .waiting(let known) where known == found:
                    break
                case .none, .offered, .waiting:
                    self.stage = .waiting(found)
                }
            }
        }
    }

    func install() {
        guard case .waiting(let release) = stage else { return }
        take(release)
    }

    private func take(_ release: Release) {
        switch stage {
        case .fetching, .ready:
            return
        case .none, .offered, .waiting:
            break
        }
        stage = .fetching(release)
        Task.detached(priority: .utility) {
            let worked: Bool
            do {
                try await Swap.install(release)
                worked = true
            } catch {
                worked = false
            }
            await MainActor.run { [weak self] in
                self?.landed(release, worked: worked)
            }
        }
    }

    private func landed(_ release: Release, worked: Bool) {
        guard case .fetching(let fetching) = stage, fetching == release else { return }
        stage = worked ? .ready(release) : .offered(release)
    }

    func relaunch() {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; shift; exec \"$@\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier)
        ] + Updater.reopen
        try? waiter.run()
        NSApp.terminate(nil)
    }

    private static var reopen: [String] {
        var arguments = ["/usr/bin/open"]
        if let customFeed = ProcessInfo.processInfo.environment["ISA_FEED"] {
            arguments += ["--env", "ISA_FEED=\(customFeed)"]
        }
        return arguments + [Bundle.main.bundleURL.path]
    }

    private static func fetch() async -> Release? {
        var request = URLRequest(url: feed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let build = (json["build"] as? Int) ?? Int(json["build"] as? String ?? ""),
              let archive = link(json["url"]),
              let dmg = link(json["dmg"])
        else { return nil }

        let sha = (json["sha256"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let notes = (json["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Release(
            version: version,
            build: build,
            archive: archive,
            dmg: dmg,
            sha256: sha.flatMap { $0.isEmpty ? nil : $0 },
            notes: notes.flatMap { $0.isEmpty ? nil : $0 },
            minimumSystemVersion: json["minimumSystemVersion"] as? String
        )
    }

    private static func link(_ value: Any?) -> URL? {
        guard let url = (value as? String).flatMap(URL.init(string:)) else { return nil }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

private enum Swap {
    enum Refused: Error {
        case readOnly, download, hash, archive, plist, wrongApp, notNewer, unsigned, wrongTeam, move
    }

    static var target: URL { Bundle.main.bundleURL }

    static var aside: URL {
        target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + ".old")
    }

    static func install(_ release: Updater.Release) async throws {
        let files = FileManager.default
        guard target.pathExtension == "app" else {
            throw Refused.wrongApp
        }
        guard files.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw Refused.readOnly
        }

        let scratch = (try? files.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true
        )) ?? files.temporaryDirectory.appendingPathComponent("isa-update-\(release.build)", isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }

        let zip = scratch.appendingPathComponent("isa.zip")
        try await download(release.archive, to: zip)
        if let expected = release.sha256, !expected.isEmpty {
            guard try digest(of: zip).lowercased() == expected.lowercased() else {
                throw Refused.hash
            }
        }
        let unpacked = scratch.appendingPathComponent("unpacked", isDirectory: true)
        try extract(zip, into: unpacked)
        guard let fresh = try files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw Refused.archive }
        try verify(fresh)
        try swap(fresh)
    }

    private static func download(_ url: URL, to file: URL) async throws {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (got, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw Refused.download
        }
        try FileManager.default.moveItem(at: got, to: file)
    }

    private static func digest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var sha = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func extract(_ zip: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Refused.archive }
    }

    private static func verify(_ bundle: URL) throws {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Refused.plist }

        if let expectedID = Bundle.main.bundleIdentifier {
            guard info["CFBundleIdentifier"] as? String == expectedID else {
                throw Refused.wrongApp
            }
        }
        guard Int(info["CFBundleVersion"] as? String ?? "") ?? 0 > Updater.build else {
            throw Refused.notNewer
        }

        if let currentTeam = teamID(of: target) {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
                throw Refused.unsigned
            }
            if let identifier = Bundle.main.bundleIdentifier, let requirement = developerID(team: currentTeam, identifier: identifier) {
                let strict = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
                guard SecStaticCodeCheckValidity(code, strict, requirement) == errSecSuccess else {
                    throw Refused.unsigned
                }
            }
            guard teamID(of: bundle) == currentTeam else {
                throw Refused.wrongTeam
            }
        }
    }

    private static func developerID(team: String, identifier: String) -> SecRequirement? {
        let text = "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    private static func teamID(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signing = info as? [String: Any]
        else { return nil }
        return signing[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func swap(_ fresh: URL) throws {
        let files = FileManager.default
        sweep()
        guard !files.fileExists(atPath: aside.path) else { throw Refused.move }
        try files.moveItem(at: target, to: aside)
        do {
            try files.moveItem(at: fresh, to: target)
        } catch {
            try? files.moveItem(at: aside, to: target)
            throw Refused.move
        }
    }

    static func sweep() {
        let plist = aside.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        if let expected = Bundle.main.bundleIdentifier, info["CFBundleIdentifier"] as? String != expected {
            return
        }
        try? FileManager.default.removeItem(at: aside)
    }
}
