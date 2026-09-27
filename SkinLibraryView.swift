import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Thumbnail cache

@MainActor
final class SkinImageCache {
    static let shared = SkinImageCache()
    private var images: [String: NSImage] = [:]

    func image(for asset: SkinAsset, url: URL) async -> NSImage? {
        if let hit = images[asset.contentHash] { return hit }
        let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            NSImage(contentsOf: url)
        }.value
        images[asset.contentHash] = loaded
        return loaded
    }

    func forget(_ contentHash: String) {
        images.removeValue(forKey: contentHash)
    }
}

// MARK: - Skin Library tab

struct SkinLibraryView: View {
    @ObservedObject var store: ManagerStore
    /// 把一张卡面批量分配给若干张卡（cardHash 列表）。
    let onAssign: (SkinAsset, [String]) -> Void

    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var selection: Set<UUID> = []
    @State private var renameTarget: SkinAsset?
    @State private var renameText = ""
    @State private var tagTarget: SkinAsset?
    @State private var tagText = ""
    @State private var assignTarget: SkinAsset?
    @State private var isDropTargeted = false
    @State private var notice: String?

    private let columns = [GridItem(.adaptive(minimum: 208, maximum: 248), spacing: 16)]

    private var filtered: [SkinAsset] {
        store.sortedAssets.filter { asset in
            if favoritesOnly && !asset.isFavorite { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return asset.name.lowercased().contains(q)
                || asset.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryToolbar
            Divider()
            if store.assets.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ContentUnavailableLabel(title: "没有匹配的卡面",
                                        message: "换个关键词，或取消「只看收藏」。")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { asset in
                            SkinThumbCell(asset: asset, isSelected: selection.contains(asset.id))
                                .onTapGesture { toggleSelection(asset.id) }
                                .overlay(alignment: .topLeading) {
                                    if selection.contains(asset.id) {
                                        Image(systemName: "checkmark.square.fill")
                                            .font(.system(size: 17))
                                            .foregroundColor(.accentColor)
                                            .background(Circle().fill(.white))
                                            .padding(7)
                                    }
                                }
                                .contextMenu { menu(for: asset) }
                        }
                    }
                    .padding(20)
                }
            }
            Spacer(minLength: 0)
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(Color.accentColor.opacity(0.06))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $renameTarget) { asset in
            renameSheet(asset)
        }
        .sheet(item: $tagTarget) { asset in
            tagSheet(asset)
        }
        .sheet(item: $assignTarget) { asset in
            AssignToCardsSheet(store: store, asset: asset) { hashes in
                onAssign(asset, hashes)
                notice = "「\(asset.name)」已分配给 \(hashes.count) 张卡"
            }
        }
        .alert("提示", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("好", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: Toolbar

    private var libraryToolbar: some View {
        HStack(spacing: 10) {
            Button {
                importViaPanel()
            } label: {
                Label("导入图片", systemImage: "photo.badge.plus")
            }

            Menu {
                Button("导入卡面包 (.aircardpack)…") { importPackViaPanel() }
                Button("导出所选为卡面包…") { exportPackViaPanel() }
                    .disabled(selection.isEmpty)
            } label: {
                Label("卡面包", systemImage: "shippingbox")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if selection.count > 0 {
                Text("已选 \(selection.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("取消选择") { selection.removeAll() }
                Button(role: .destructive) {
                    store.deleteAssets(ids: selection)
                    for id in selection { store.asset(id: id).map { SkinImageCache.shared.forget($0.contentHash) } }
                    selection.removeAll()
                } label: {
                    Label("删除所选", systemImage: "trash")
                }
            }

            Spacer()

            Toggle("只看收藏", isOn: $favoritesOnly)
                .toggleStyle(.button)
                .controlSize(.small)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
                TextField("搜索名称或标签", text: $query)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(7)

            Text("共 \(store.assets.count) 张")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 46))
                .foregroundColor(.secondary.opacity(0.6))
            Text("卡面库还是空的")
                .font(.title3.weight(.semibold))
            Text("点「导入图片」，或把 PNG / JPG 直接拖进来。\n导入后图片会复制进 App 自己的素材库，原图移走或改名都不会影响已分配的卡面。")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("导入图片") { importViaPanel() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func menu(for asset: SkinAsset) -> some View {
        Group {
            Button("应用到卡片…") { assignTarget = asset }
                .disabled(store.cards.isEmpty)
            Button(asset.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(id: asset.id) }
            Button("重命名…") {
                renameTarget = asset
                renameText = asset.name
            }
            Button("编辑标签…") {
                tagTarget = asset
                tagText = asset.tags.joined(separator: ", ")
            }
            Divider()
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([store.url(for: asset)])
            }
            Button("复制到剪贴板") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([store.url(for: asset) as NSURL])
            }
            Divider()
            Button(role: .destructive) {
                SkinImageCache.shared.forget(asset.contentHash)
                store.deleteAssets(ids: [asset.id])
                selection.remove(asset.id)
            } label: { Label("删除", systemImage: "trash") }
        }
    }

    // MARK: Sheets

    private func renameSheet(_ asset: SkinAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重命名卡面").font(.headline)
            TextField("名称", text: $renameText)
                .frame(width: 260)
                .onSubmit { commitRename(asset) }
            HStack {
                Spacer()
                Button("取消") { renameTarget = nil }
                Button("保存") { commitRename(asset) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private func commitRename(_ asset: SkinAsset) {
        store.rename(id: asset.id, to: renameText)
        notice = "已重命名为「\(renameText.trimmingCharacters(in: .whitespacesAndNewlines))」"
        renameTarget = nil
    }

    private func tagSheet(_ asset: SkinAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("标签").font(.headline)
            TextField("用逗号分隔，例如：银行卡, 深色", text: $tagText).frame(width: 280)
            Text("标签用于卡面库搜索。")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("取消") { tagTarget = nil }
                Button("保存") {
                    store.setTags(id: asset.id, tags: tagText.components(separatedBy: ","))
                    tagTarget = nil
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    // MARK: Actions

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func importViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .image, .tiff, .gif, .bmp]
        guard panel.runModal() == .OK else { return }
        let summary = store.importImages(from: panel.urls)
        notice = importMessage(summary)
    }

    private func importPackViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.nameFieldStringValue = ""
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let summary = store.importPack(from: url)
        notice = "卡面包导入：新增 \(summary.added) 张，重复跳过 \(summary.duplicates) 张"
            + (summary.failed > 0 ? "，失败 \(summary.failed) 张" : "")
    }

    private func exportPackViaPanel() {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "aircard-skins.aircardpack"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.exportPack(assetIds: ids, to: url) {
            notice = "已导出 \(ids.count) 张卡面到 \(url.lastPathComponent)"
        }
    }

    private func importMessage(_ summary: ImportSummary) -> String {
        var parts: [String] = ["新增 \(summary.added) 张"]
        if summary.duplicates > 0 { parts.append("重复跳过 \(summary.duplicates) 张") }
        if summary.failed > 0 { parts.append("不支持或读取失败 \(summary.failed) 张") }
        return parts.joined(separator: "，")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data,
                          let text = String(data: data, encoding: .utf8),
                          let url = URL(string: text) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            let dropped = urls.filter {
                Self.imageExtensions.contains($0.pathExtension.lowercased())
                    || $0.pathExtension.lowercased() == "aircardpack"
            }
            let packs = dropped.filter { $0.pathExtension.lowercased() == "aircardpack" }
            let images = dropped.filter { $0.pathExtension.lowercased() != "aircardpack" }
            var message: [String] = []
            if !images.isEmpty {
                let s = store.importImages(from: images)
                message.append(importMessage(s))
            }
            for pack in packs {
                let s = store.importPack(from: pack)
                message.append("卡面包 \(pack.deletingPathExtension().lastPathComponent)：新增 \(s.added) 张")
            }
            if !message.isEmpty { notice = message.joined(separator: "；") }
        }
        return true
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"]
}

// MARK: - Thumbnail cell

struct SkinThumbCell: View {
    let asset: SkinAsset
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ProgressView().controlSize(.small)
                }
                if asset.isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.yellow)
                                .shadow(radius: 2)
                                .padding(7)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 118)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : (hovered ? Color.secondary.opacity(0.45) : Color.secondary.opacity(0.18)),
                            lineWidth: isSelected ? 2 : 1)
            )

            HStack(spacing: 5) {
                Text(asset.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if !asset.tags.isEmpty {
                    Text(asset.tags.first ?? "")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Text("\(asset.pixelWidth)×\(asset.pixelHeight) · \(ByteCountFormatter.string(fromByteCount: Int64(asset.byteCount), countStyle: .file))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.85))
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(hovered ? 1 : 0.55))
        )
        .onHover { hovered = $0 }
        .task(id: asset.contentHash) {
            image = await SkinImageCache.shared.image(for: asset,
                                                      url: ManagerStore.shared.url(for: asset))
        }
        .help("点击多选，右键更多操作")
    }
}

// MARK: - Pick a skin from the library for one card

struct SkinPickerSheet: View {
    @ObservedObject var store: ManagerStore
    let currentSkinId: UUID?
    let onChoose: (UUID?) -> Void
    /// 库里没有合适的图时，直接从文件选一张并入库分配。
    let onImportNew: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var filtered: [SkinAsset] {
        let q = query.lowercased()
        return store.sortedAssets.filter {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("从卡面库选择").font(.headline)
                Spacer()
                TextField("搜索", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("关闭") { dismiss() }
            }
            .padding(14)

            Divider()

            if store.assets.isEmpty {
                ContentUnavailableLabel(title: "卡面库为空",
                                        message: "先到「卡面库」标签页导入图片。")
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 200), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { asset in
                            SkinPickCell(asset: asset, isCurrent: asset.id == currentSkinId)
                                .onTapGesture {
                                    onChoose(asset.id)
                                    dismiss()
                                }
                        }
                    }
                    .padding(14)
                }
                .frame(minHeight: 240)
            }

            Divider()
            HStack {
                Button("清除该卡分配") {
                    onChoose(nil)
                    dismiss()
                }
                .foregroundColor(.secondary)
                Button("导入新图片…") { onImportNew() }
                Spacer()
                Text("\(store.assets.count) 张可选").font(.caption).foregroundColor(.secondary)
            }
            .padding(12)
        }
        .frame(width: 620, height: 480)
    }
}

struct SkinPickCell: View {
    let asset: SkinAsset
    let isCurrent: Bool

    @State private var image: NSImage?
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 86)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    ProgressView().controlSize(.mini)
                }
                if isCurrent {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .shadow(radius: 2)
                                .padding(5)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 86)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isCurrent ? Color.green.opacity(0.7) : Color.clear, lineWidth: 2)
            )
            Text(asset.name).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .scaleEffect(hovered ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .task(id: asset.contentHash) {
            image = await SkinImageCache.shared.image(for: asset,
                                                      url: ManagerStore.shared.url(for: asset))
        }
    }
}

// MARK: - Per-card apply history with rollback

struct CardHistoryPopover: View {
    @ObservedObject var store: ManagerStore
    let cardHash: String
    let onReflash: (SkinAsset) -> Void

    @Environment(\.dismiss) private var dismiss

    private var records: [ApplyRecord] { store.records(for: cardHash) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(store.displayName(for: cardHash)) 的应用记录")
                .font(.system(size: 11, weight: .semibold))
            if records.isEmpty {
                Text("这张卡还没有成功刷入过卡面。")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { offset, record in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(record.skinName)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Text(Self.dateFormatter.string(from: record.appliedAt))
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 6)
                                if offset == 0 {
                                    Text("当前")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.green)
                                } else if let asset = store.asset(id: record.skinId) {
                                    Button("刷回这个") {
                                        onReflash(asset)
                                        dismiss()
                                    }
                                    .controlSize(.mini)
                                } else {
                                    Text("素材已删")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

// MARK: - Assign one skin to a set of cards

struct AssignToCardsSheet: View {
    @ObservedObject var store: ManagerStore
    let asset: SkinAsset
    let onConfirm: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    private var cardHashes: [String] {
        store.cards.keys.sorted {
            store.displayName(for: $0).localizedCaseInsensitiveCompare(store.displayName(for: $1)) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("把「\(asset.name)」分配给…").font(.headline)
                Spacer()
                Text("已选 \(picked.count)/\(cardHashes.count)")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(cardHashes, id: \.self) { hash in
                        let profile = store.cards[hash]
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { picked.contains(hash) },
                                set: { on in if on { picked.insert(hash) } else { picked.remove(hash) } }
                            )).labelsHidden()

                            VStack(alignment: .leading, spacing: 1) {
                                Text(store.displayName(for: hash))
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(hash)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if store.asset(id: profile?.assignedSkinId)?.id == asset.id {
                                Text("当前")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.accentColor)
                            } else if let current = store.asset(id: profile?.assignedSkinId) {
                                Text(current.name)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 90)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(picked.contains(hash) ? Color.accentColor.opacity(0.09) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if picked.contains(hash) { picked.remove(hash) } else { picked.insert(hash) }
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 200)

            Divider()
            HStack(spacing: 8) {
                Button("全选") { picked = Set(cardHashes) }
                Button("全不选") { picked.removeAll() }
                Spacer()
                Button("取消") { dismiss() }
                Button("分配 \(picked.count) 张卡") {
                    onConfirm(cardHashes.filter { picked.contains($0) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - Shared empty content

struct ContentUnavailableLabel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.6))
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - Sheet presentation by item

/// SwiftUI 的 .sheet(item:) 需要一个 Identifiable 载体来记住"给哪张卡弹窗"。
struct CardIdTarget: Identifiable, Hashable {
    let id: String
}
