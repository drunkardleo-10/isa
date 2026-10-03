import SwiftUI
import WebKit

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colour: Int
    var icon: String?
    var sharesSignIns: Bool?
    var downloads: String?

    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    var isFirst: Bool { id == Profile.firstID }

    var symbol: String {
        icon.flatMap { Profiles.icons.contains($0) ? $0 : nil } ?? (isFirst ? "person.crop.circle" : "briefcase")
    }
}

enum Profiles {
    static let colours: [Color] = [
        Color(red: 0.45, green: 0.47, blue: 0.52),
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.20, green: 0.66, blue: 0.45),
        Color(red: 0.96, green: 0.62, blue: 0.20),
        Color(red: 0.90, green: 0.33, blue: 0.40),
        Color(red: 0.62, green: 0.40, blue: 0.90),
    ]
    static let colourNames = ["Slate", "Blue", "Green", "Orange", "Red", "Violet"]

    static let icons = [
        "person.crop.circle", "briefcase", "building.2", "desktopcomputer", "laptopcomputer", "chevron.left.forwardslash.chevron.right", "terminal",
        "sparkles", "brain.head.profile", "lightbulb", "gamecontroller", "beach.umbrella", "cup.and.saucer",
        "music.note", "film", "paintpalette", "camera", "house", "book",
        "graduationcap", "cart", "airplane", "dumbbell", "leaf", "heart",
    ]
    static let iconNames = [
        "Personal", "Work", "Office", "Desktop", "Laptop", "Code", "Terminal",
        "AI", "Thinking", "Ideas", "Games", "Leisure", "Café",
        "Music", "Film", "Art", "Photos", "Home", "Reading",
        "Studies", "Shopping", "Travel", "Sport", "Nature", "Life",
    ]

    private static var file: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("isa", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("profiles.json")
    }

    static func read() -> [Profile] {
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        let first = saved.first(where: \.isFirst) ?? Profile(id: Profile.firstID, name: "Personal", colour: 0)
        return [first] + saved.filter { !$0.isFirst }
    }

    static func write(_ profiles: [Profile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        NotificationCenter.default.post(name: changed, object: profiles)
    }

    static let changed = Notification.Name("IsaProfilesChanged")

    @MainActor static var current = Profile.firstID

    @MainActor private static var stores: [UUID: WKWebsiteDataStore] = [:]
    @MainActor static var sharing: Set<UUID> = []

    @MainActor static func store(for id: UUID) -> WKWebsiteDataStore {
        if id == Profile.firstID || sharing.contains(id) {
            return .default()
        }
        if let made = stores[id] {
            return made
        }
        let made = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = made
        return made
    }

    @MainActor static var everyStore: [WKWebsiteDataStore] {
        [.default()] + stores.values
    }

    @MainActor static func erase(_ id: UUID) {
        guard id != Profile.firstID else { return }
        let store = store(for: id)
        let everything = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        }
        stores[id] = nil
        let pending = Set(UserDefaults.standard.stringArray(forKey: "isa_profiles_erasing") ?? []).union([id.uuidString])
        UserDefaults.standard.set(pending.sorted(), forKey: "isa_profiles_erasing")
        sweep()
        for delay in [3.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                sweep()
            }
        }
    }

    @MainActor static func sweep() {
        for text in UserDefaults.standard.stringArray(forKey: "isa_profiles_erasing") ?? [] {
            guard let id = UUID(uuidString: text) else { continue }
            Task { @MainActor in
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: id)
                } catch {
                    let left = await WKWebsiteDataStore.allDataStoreIdentifiers
                    guard !left.contains(id) else { return }
                }
                let now = (UserDefaults.standard.stringArray(forKey: "isa_profiles_erasing") ?? []).filter { $0 != text }
                UserDefaults.standard.set(now, forKey: "isa_profiles_erasing")
            }
        }
    }
}

struct Parked {
    var tabs: [Tab]
    var activeID: UUID?
}
