import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit
import ImageIO

// MARK: - Library models

struct SkinAsset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var storedFileName: String
    var isFavorite: Bool
    var tags: [String]
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int
    var contentHash: String
    var addedAt: Date
}

struct CardProfile: Codable, Hashable {
    var cardHash: String
    var nickname: String = ""
    var note: String = ""
    var assignedSkinId: UUID? = nil
    var lastAppliedSkinId: UUID? = nil
    var lastAppliedAt: Date? = nil
}

struct ApplyRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var cardHash: String
    var skinId: UUID?
    var skinName: String
    var appliedAt: Date
    var succeeded: Bool
}

struct ImportSummary: Hashable {
    var added = 0
    var duplicates = 0
    var failed = 0
    var addedIds: [UUID] = []
}

private struct LibraryPayload: Codable {
    var version: Int = 2
    var assets: [SkinAsset] = []
    var cards: [String: CardProfile] = [:]
    var history: [ApplyRecord] = []
}

// MARK: - ManagerStore

@MainActor
final class ManagerStore: ObservableObject {
    static let shared = ManagerStore()

    @Published var assets: [SkinAsset] = []
    @Published var cards: [String: CardProfile] = [:]
    @Published var history: [ApplyRecord] = []
    @Published var lastImportSummary: ImportSummary? = nil
    @Published var lastError: String? = nil

    let rootURL: URL
    let skinsURL: URL
    private let libraryURL: URL
    private var pendingSave: Task<Void, Never>?
    private var libraryIsTrustworthy = true
    private let maxHistoryPerCard = 25

    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        rootURL = base.appendingPathComponent("AirCard Manager", isDirectory: true)
        skinsURL = rootURL.appendingPathComponent("Skins", isDirectory: true)
        libraryURL = rootURL.appendingPathComponent("library.json")
        Self.prepareDirectories(skinsURL: skinsURL, rootURL: rootURL)
        load()
    }

    private static func prepareDirectories(skinsURL: URL, rootURL: URL) {
        try? FileManager.default.createDirectory(at: skinsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    func load() {
        // 文件读不到才是真的空库；解析失败必须停住，否则会误删图片、并把空库覆盖回磁盘。
        guard let data = try? Data(contentsOf: libraryURL) else {
            libraryIsTrustworthy = true
            pruneOrphanedFiles()
            migrateLegacyCardHashes()
            return
        }
        do {
            let payload = try JSONDecoder.aircard().decode(LibraryPayload.self, from: data)
            assets = payload.assets
            cards = payload.cards
            history = payload.history
            libraryIsTrustworthy = true
            pruneOrphanedFiles()
            migrateLegacyCardHashes()
        } catch {
            libraryIsTrustworthy = false
            lastError = "素材库文件解析失败，为保护现有数据已停止写入：\(error.localizedDescription)"
        }
    }

    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        guard libraryIsTrustworthy else { return }
        let payload = LibraryPayload(version: 2, assets: assets, cards: cards, history: history)
        guard let data = try? JSONEncoder.aircardSorted().encode(payload) else { return }
        do {
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            lastError = "无法写入素材库：\(error.localizedDescription)"
        }
    }

    /// 素材库里的图片文件若已无对应记录，说明记录被回滚或导入中断，清掉避免占用磁盘。
    private func pruneOrphanedFiles() {
        let fm = FileManager.default
        guard let onDisk = try? fm.contentsOfDirectory(atPath: skinsURL.path) else { return }
        let referenced = Set(assets.map { $0.storedFileName })
        for file in onDisk where !referenced.contains(file) {
            if Self.supportedExtensions.contains((file as NSString).pathExtension.lowercased()) || file.hasSuffix(".importing") {
                try? fm.removeItem(at: skinsURL.appendingPathComponent(file))
            }
        }
    }

    /// 上游 App 只把卡 hash 存在 UserDefaults / ~/.aircard_cards.json，接管后合并进本库。
    private func migrateLegacyCardHashes() {
        var legacy: [String] = []
        for key in ["mak5er.aircard.savedCards", "mak5er.savedCards", "LumiCards.savedCards"] {
            if let saved = UserDefaults.standard.stringArray(forKey: key) {
                legacy.append(contentsOf: saved)
            }
        }
        for path in ["~/.aircard_cards.json", "~/.lumicards_cards.json"] {
            let full = NSString(string: path).expandingTildeInPath
            if let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
               let hashes = try? JSONDecoder().decode([String].self, from: data) {
                legacy.append(contentsOf: hashes)
            }
        }
        var changed = false
        for hash in legacy where cards[hash] == nil && Self.looksLikeCardHash(hash) {
            cards[hash] = CardProfile(cardHash: hash)
            changed = true
        }
        if changed { save() }
    }

    static func looksLikeCardHash(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 && trimmed.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Asset queries

    func url(for asset: SkinAsset) -> URL {
        skinsURL.appendingPathComponent(asset.storedFileName)
    }

    func asset(id: UUID?) -> SkinAsset? {
        guard let id else { return nil }
        return assets.first { $0.id == id }
    }

    func asset(withHash contentHash: String) -> SkinAsset? {
        assets.first { $0.contentHash == contentHash }
    }

    var sortedAssets: [SkinAsset] {
        assets.sorted { $0.addedAt > $1.addedAt }
    }

    // MARK: - Import / export individual images

    @discardableResult
    func importImages(from urls: [URL], suggestedNames: [URL: String] = [:]) -> ImportSummary {
        var summary = ImportSummary()

        for source in urls {
            let ext = source.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                summary.failed += 1
                continue
            }
            guard let data = try? Data(contentsOf: source) else {
                summary.failed += 1
                continue
            }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let existing = asset(withHash: hash) {
                summary.duplicates += 1
                summary.addedIds.append(existing.id)
                continue
            }

            let id = UUID()
            let storedName = "\(id.uuidString.prefix(8))-\(hash.prefix(8)).\(ext)"
            let destination = skinsURL.appendingPathComponent(storedName)
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                summary.failed += 1
                continue
            }

            let size = Self.pixelSize(of: destination) ?? (0, 0)
            let baseName = suggestedNames[source] ?? source.deletingPathExtension().lastPathComponent
            let asset = SkinAsset(
                id: id,
                name: sanitizedAssetName(baseName, fallback: source.lastPathComponent),
                storedFileName: storedName,
                isFavorite: false,
                tags: [],
                pixelWidth: size.0,
                pixelHeight: size.1,
                byteCount: data.count,
                contentHash: hash,
                addedAt: Date()
            )
            assets.append(asset)
            summary.added += 1
            summary.addedIds.append(id)
        }

        if summary.added > 0 { scheduleSave() }
        lastImportSummary = summary
        return summary
    }

    private func sanitizedAssetName(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(80))
    }

    func deleteAssets(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let fm = FileManager.default
        for id in ids {
            guard let idx = assets.firstIndex(where: { $0.id == id }) else { continue }
            try? fm.removeItem(at: url(for: assets[idx]))
            assets.remove(at: idx)
        }
        // 分配指向已删素材的卡回到"未分配"，避免 Flash 时读到不存在的文件。
        for (hash, profile) in cards where profile.assignedSkinId != nil && ids.contains(profile.assignedSkinId!) {
            cards[hash]?.assignedSkinId = nil
        }
        scheduleSave()
    }

    func rename(id: UUID, to newName: String) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        assets[idx].name = String(cleaned.prefix(80))
        scheduleSave()
    }

    func toggleFavorite(id: UUID) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[idx].isFavorite.toggle()
        scheduleSave()
    }

    func setTags(id: UUID, tags: [String]) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[idx].tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        scheduleSave()
    }

    private static func pixelSize(of url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let w, let h else { return nil }
        return (w, h)
    }

    // MARK: - Card profiles

    @discardableResult
    func ensureCard(_ cardHash: String) -> CardProfile {
        if let existing = cards[cardHash] { return existing }
        let created = CardProfile(cardHash: cardHash)
        cards[cardHash] = created
        scheduleSave()
        return created
    }

    func assignSkin(_ skinId: UUID?, to cardHash: String) {
        ensureCard(cardHash)
        cards[cardHash]?.assignedSkinId = skinId
        scheduleSave()
    }

    func skinId(for cardHash: String) -> UUID? {
        cards[cardHash]?.assignedSkinId
    }

    func setNickname(_ nickname: String, for cardHash: String) {
        ensureCard(cardHash)
        cards[cardHash]?.nickname = String(nickname.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        scheduleSave()
    }

    func setNote(_ note: String, for cardHash: String) {
        ensureCard(cardHash)
        cards[cardHash]?.note = String(note.prefix(400))
        scheduleSave()
    }

    func forgetCard(_ cardHash: String) {
        cards.removeValue(forKey: cardHash)
        scheduleSave()
    }

    /// 界面上删掉的卡同步出库，避免残留一堆没人管的旧 hash。
    func pruneCards(keeping liveHashes: Set<String>) {
        let doomed = cards.keys.filter { !liveHashes.contains($0) }
        guard !doomed.isEmpty else { return }
        for hash in doomed { cards.removeValue(forKey: hash) }
        scheduleSave()
    }

    func displayName(for cardHash: String) -> String {
        let nickname = cards[cardHash]?.nickname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return nickname.isEmpty ? cardHash : nickname
    }

    /// 卡片主视图先走卡名索引，命中不到再退回 hash 片段。
    func matchesCardQuery(_ cardHash: String, query: String) -> Bool {
        if query.isEmpty { return true }
        let q = query.lowercased()
        if displayName(for: cardHash).lowercased().contains(q) { return true }
        if (cards[cardHash]?.note.lowercased() ?? "").contains(q) { return true }
        return cardHash.lowercased().contains(q)
    }

    // MARK: - Apply history & rollback targets

    func recordApply(cardHash: String, skinId: UUID?, skinName: String, succeeded: Bool) {
        let record = ApplyRecord(id: UUID(), cardHash: cardHash, skinId: skinId,
                                 skinName: skinName, appliedAt: Date(), succeeded: succeeded)
        history.append(record)
        if succeeded {
            ensureCard(cardHash)
            cards[cardHash]?.lastAppliedSkinId = skinId
            cards[cardHash]?.lastAppliedAt = record.appliedAt
        }
        if history.count > 400 { history.removeFirst(history.count - 400) }
        scheduleSave()
    }

    func records(for cardHash: String) -> [ApplyRecord] {
        history.filter { $0.cardHash == cardHash && $0.succeeded }
            .sorted { $0.appliedAt > $1.appliedAt }
            .prefix(maxHistoryPerCard)
            .compactMap { $0 }
    }

    /// 回滚目标：该卡最近一次成功刷入、且当前尚未生效的那张卡面。
    func rollbackTarget(for cardHash: String) -> SkinAsset? {
        let current = cards[cardHash]?.lastAppliedSkinId
        for record in records(for: cardHash) {
            if let skinId = record.skinId, skinId != current, let asset = asset(id: skinId) {
                return asset
            }
        }
        return nil
    }

    // MARK: - Skin packs (.aircardpack = zip)

    func exportPack(assetIds: [UUID], to destination: URL) -> Bool {
        let selected = assets.filter { assetIds.contains($0.id) }
        guard !selected.isEmpty else {
            lastError = "请先在卡面库中勾选要导出的卡面。"
            return false
        }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("aircardpack-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var manifestEntries: [[String: Any]] = []
            for asset in selected {
                let copyName = "\(asset.contentHash.prefix(12)).\((asset.storedFileName as NSString).pathExtension)"
                try fm.copyItem(at: url(for: asset), to: staging.appendingPathComponent(copyName))
                manifestEntries.append([
                    "name": asset.name,
                    "file": copyName,
                    "hash": asset.contentHash,
                    "favorite": asset.isFavorite,
                    "tags": asset.tags,
                    "width": asset.pixelWidth,
                    "height": asset.pixelHeight,
                    "addedAt": asset.addedAt.timeIntervalSince1970,
                ])
            }
            let manifest: [String: Any] = ["format": "aircardpack", "version": 1, "skins": manifestEntries]
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: staging.appendingPathComponent("manifest.json"))
            try? fm.removeItem(at: destination)
            return Self.runZip(staging: staging, destination: destination)
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
            return false
        }
    }

    func importPack(from packURL: URL) -> ImportSummary {
        var summary = ImportSummary()
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("aircardpack-in-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        guard Self.runUnzip(source: packURL, destination: staging) else {
            lastError = "解压卡面包失败，请确认是有效的 .aircardpack 文件。"
            return summary
        }

        var namesByFile: [String: String] = [:]
        var metaByHash: [String: (favorite: Bool, tags: [String])] = [:]
        if let manifestData = try? Data(contentsOf: staging.appendingPathComponent("manifest.json")),
           let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let entries = manifest["skins"] as? [[String: Any]] {
            for entry in entries {
                guard let file = entry["file"] as? String else { continue }
                if let name = entry["name"] as? String { namesByFile[file] = name }
                guard let hash = entry["hash"] as? String else { continue }
                metaByHash[hash] = (
                    favorite: (entry["favorite"] as? Bool) ?? false,
                    tags: (entry["tags"] as? [String]) ?? []
                )
            }
        }

        let imageFiles = (try? fm.contentsOfDirectory(atPath: staging.path))?.sorted() ?? []
        var urls: [URL] = []
        var suggested: [URL: String] = [:]
        for file in imageFiles where Self.supportedExtensions.contains((file as NSString).pathExtension.lowercased()) {
            let url = staging.appendingPathComponent(file)
            urls.append(url)
            suggested[url] = namesByFile[file] ?? (url.deletingPathExtension().lastPathComponent)
        }
        if urls.isEmpty {
            lastError = "卡面包里没有可识别的图片。"
            return summary
        }

        summary = importImages(from: urls, suggestedNames: suggested)
        // 按内容 hash 回查，而不是按下标：重复图不会新增，下标会与 urls 错位。
        for id in summary.addedIds {
            guard let asset = asset(id: id), let meta = metaByHash[asset.contentHash] else { continue }
            if meta.favorite != asset.isFavorite { toggleFavorite(id: id) }
            if !meta.tags.isEmpty && asset.tags != meta.tags { setTags(id: id, tags: meta.tags) }
        }
        return summary
    }

    private static func runZip(staging: URL, destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", staging.path, destination.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            ManagerStore.shared.lastError = "打包失败：\(error.localizedDescription)"
            return false
        }
    }

    private static func runUnzip(source: URL, destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", source.path, destination.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension JSONDecoder {
    /// 与 JSONEncoder.aircardSorted 的 .iso8601 配对；默认策略会把 Date 当 Double 解，导致整库解析失败。
    static func aircard() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    /// 固定键序，避免每次保存产生无意义的 diff。
    static func aircardSorted() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
