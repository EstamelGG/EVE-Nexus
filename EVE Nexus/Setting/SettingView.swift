import SwiftUI
import UIKit
import Kingfisher

// MARK: - 数据模型

struct SettingItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
    let icon: String?
    let iconColor: Color
    let action: () -> Void
    var customView: ((SettingItem) -> AnyView)?

    init(
        title: String, detail: String? = nil, icon: String? = nil, iconColor: Color = .blue,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
        customView = nil
    }

    init<V: View>(
        title: String, detail: String? = nil, icon: String? = nil, iconColor: Color = .blue,
        action: @escaping () -> Void, @ViewBuilder customView: @escaping (SettingItem) -> V
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
        self.customView = { AnyView(customView($0)) }
    }
}

// MARK: - 设置组

struct SettingGroup: Identifiable {
    let id = UUID()
    let header: String
    let items: [SettingItem]
}

// MARK: - 缓存管理器

class CacheManager {
    static let shared = CacheManager()
    private let fileManager = FileManager.default

    // 定义需要清理的缓存键前缀
    private let cachePrefixes = [
        "incursions_cache",
        "character_portrait_",
        "corporation_info",
        "corporation_info_",
        "alliance_info_",
        "structure_info_",
        "character_info_",
        "market_orders_",
        "market_history_",
        "contracts_",
        "wallet_journal_",
        "wallet_transactions_",
        "mining_ledger_",
        "industry_jobs_",
        "location_info_",
    ]

    // 定义需要清理的目录列表
    private let cacheDirs = [
        "StructureCache",  // 建筑缓存
        "AssetCache",  // 资产缓存
        "StaticDataSet",  // 临时静态数据
        "ContactsCache",  // 声望
        "kb",  // 战斗日志
        "BRKillmails",  // 战斗日志细节
        "MarketCache",  // 市场价格细节
        "Planetary",  // 行星开发
        "CharacterOrders",  // 人物市场订单
        // "Fitting",  // 舰船配置目录
        "fw",  // 势力战争
    ]

    // 获取缓存目录列表
    func getCacheDirs() -> [String] {
        return cacheDirs
    }

    // 清理指定前缀的缓存
    private func clearCacheWithPrefixes() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys

        // 遍历所有键
        for key in allKeys {
            // 检查是否有匹配的前缀
            if cachePrefixes.contains(where: { key.hasPrefix($0) }) {
                Logger.debug("正在清理缓存键: \(key)")
                defaults.removeObject(forKey: key)
            }
        }
        defaults.synchronize()
        Logger.info("基于前缀的缓存清理完成")
    }

    // 清理指定目录
    private func clearCacheDirectories() async {
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var totalFilesRemoved = 0

        for dirName in cacheDirs {
            let dirPath = documentPath.appendingPathComponent(dirName)

            do {
                if fileManager.fileExists(atPath: dirPath.path) {
                    // 统计目录中的所有文件数量（包括子目录）
                    var fileCount = 0

                    if let enumerator = fileManager.enumerator(
                        at: dirPath,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            do {
                                let resourceValues = try fileURL.resourceValues(forKeys: [
                                    .isRegularFileKey
                                ])
                                // 只计算文件，不计算目录本身
                                if resourceValues.isRegularFile == true {
                                    fileCount += 1
                                }
                            } catch {
                                Logger.error("获取文件属性失败 - \(fileURL.path): \(error)")
                            }
                        }
                    }

                    // 删除并重建目录
                    try fileManager.removeItem(at: dirPath)
                    try fileManager.createDirectory(at: dirPath, withIntermediateDirectories: true)

                    // 更新总计数
                    totalFilesRemoved += fileCount

                    // 记录日志
                    Logger.debug("成功清理并重建目录: \(dirName)，删除了 \(fileCount) 个文件")
                }
            } catch {
                Logger.error("清理目录失败 - \(dirName): \(error)")
            }
        }

        Logger.info("目录缓存清理完成，共删除 \(totalFilesRemoved) 个文件")
    }
    
    // 清理头像加载器缓存
    private func clearPortraitLoaderCaches() {
        // 清理 Kingfisher 的内存缓存和磁盘缓存
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
        
        Logger.info("头像加载器缓存清理完成")
    }

    // 清理所有缓存
    func clearAllCaches() async {
        // 1. 清理 NetworkManager 缓存
        await NetworkManager.shared.clearAllCaches()

        // 2. 清理临时文件
        let tempPath = NSTemporaryDirectory()
        do {
            let files = try await MainActor.run {
                try self.fileManager.contentsOfDirectory(atPath: tempPath)
            }
            for file in files {
                let filePath = (tempPath as NSString).appendingPathComponent(file)
                try? await MainActor.run {
                    try self.fileManager.removeItem(atPath: filePath)
                }
            }
        } catch {
            Logger.error("清理临时文件失败: \(error)")
        }

        // 3. 清理基于前缀的缓存
        await MainActor.run {
            clearCacheWithPrefixes()
        }

        // 4. 清理目录缓存
        await clearCacheDirectories()

        // 5. 清理入侵相关缓存
        await MainActor.run {
            InfestedSystemsViewModel.clearCache()
        }

        // 6. 清理数据库浏览器缓存
        await MainActor.run {
            DatabaseBrowserView.clearCache()
        }

        // 7. 清理静态资源
        do {
            try StaticResourceManager.shared.clearAllStaticData()
        } catch {
            Logger.error("清理静态资源失败: \(error)")
        }

        // 8. 清理建筑物缓存
        await UniverseStructureAPI.shared.clearCache()
        
        // 9. 清理头像加载器缓存
        await MainActor.run {
            clearPortraitLoaderCaches()
        }

        // 10. 清理 Swift URLCache
        await MainActor.run {
            URLCache.shared.removeAllCachedResponses()
            Logger.info("URLCache 清理完成")
        }

        // 11. 清理 URL Session 缓存
        await clearURLSessionCacheAsync()

        Logger.info("所有缓存清理完成")
    }

    // 异步清理URL Session缓存
    private func clearURLSessionCacheAsync() async {
        await MainActor.run {
            // 清理cookies
            if let cookies = HTTPCookieStorage.shared.cookies {
                for cookie in cookies {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
    }
}

// MARK: - 设置视图

struct SettingView: View {
    // MARK: - 界面组件

    private let fileManager = FileManager.default

    private struct FullScreenCover: View {
        let progress: Double
        @Binding var loadingState: LoadingState
        let onComplete: () -> Void

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    LoadingView(
                        loadingState: $loadingState,
                        progress: progress,
                        onComplete: onComplete
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .edgesIgnoringSafeArea(.all)
            .interactiveDismissDisabled()
        }
    }

    // MARK: - 属性定义

    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var showingCleanCacheAlert = false
    @State private var showingDeleteIconsAlert = false
    @State private var showingLanguageView = false
    @State private var cacheSize: String = NSLocalizedString("Misc_Calculating", comment: "")
    @ObservedObject var databaseManager: DatabaseManager
    @State private var isCleaningCache = false
    @State private var isReextractingIcons = false
    @State private var unzipProgress: Double = 0
    @State private var loadingState: LoadingState = .processing
    @State private var showingLoadingView = false
    @State private var settingGroups: [SettingGroup] = []
    @State private var showResetDatabaseAlert = false
    @State private var showResetDatabaseSuccessAlert = false
    @State private var showingESIStatusView = false

    // MARK: - 数据更新函数

    private func updateAllData() {
        Task {
            // 统计 StaticDataSet 目录大小
            let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
            var totalSize: Int64 = 0

            if FileManager.default.fileExists(atPath: staticDataSetPath.path) {
                if let enumerator = FileManager.default.enumerator(
                    at: staticDataSetPath,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [
                                .isRegularFileKey
                            ])
                            // 只统计文件，跳过目录
                            if resourceValues.isRegularFile == true {
                                let attributes = try FileManager.default.attributesOfItem(
                                    atPath: fileURL.path)
                                if let fileSize = attributes[.size] as? Int64 {
                                    totalSize += fileSize
                                    Logger.info(
                                        "Calculating file size for \(fileURL.path): \(fileSize) bytes"
                                    )
                                }
                            }
                        } catch {
                            Logger.error(
                                "计算文件大小失败 - \(fileURL.path): \(error)")
                        }
                    }
                } else {
                    Logger.error("创建目录枚举器失败")
                }
            }

            // 计算缓存目录大小
            let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            // 使用CacheManager中的缓存目录列表
            let cacheDirs = CacheManager.shared.getCacheDirs()

            for dirName in cacheDirs {
                let dirPath = documentPath.appendingPathComponent(dirName)

                if fileManager.fileExists(atPath: dirPath.path),
                    let enumerator = fileManager.enumerator(
                        at: dirPath,
                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )
                {
                    while let fileURL = enumerator.nextObject() as? URL {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [
                                .isRegularFileKey
                            ])
                            // 只统计文件，跳过目录
                            if resourceValues.isRegularFile == true {
                                let attributes = try fileManager.attributesOfItem(
                                    atPath: fileURL.path)
                                if let fileSize = attributes[.size] as? Int64 {
                                    totalSize += fileSize
                                    Logger.info(
                                        "Calculating file size for \(fileURL.path): \(fileSize) bytes"
                                    )
                                }
                            }
                        } catch {
                            Logger.error(
                                "计算文件大小失败 - \(fileURL.path): \(error)")
                        }
                    }
                }
            }

            // 更新界面
            await MainActor.run {
                let formattedSize = FormatUtil.formatFileSize(totalSize)
                self.cacheSize = formattedSize
                self.updateSettingGroups()
            }
        }
    }

    private func updateSettingGroups() {
        settingGroups = [
            createAppearanceGroup(),
            createCorporationAffairsGroup(),
            createOthersGroup(),
            createCacheGroup(),
        ]
    }

    // MARK: - 设置组创建函数

    private func createAppearanceGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Appearance", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_ColorMode", comment: ""),
                    detail: getAppearanceDetail(),  // 将当前主题状态作为详情文本
                    icon: getThemeIcon(),
                    iconColor: .blue,
                    action: toggleAppearance
                )
            ]
        )
    }

    private func toggleAppearance() {
        switch selectedTheme {
        case "light":
            selectedTheme = "dark"
        case "dark":
            selectedTheme = "system"
        case "system":
            selectedTheme = "light"
        default:
            break
        }
    }

    private struct CorporationAffairsToggle: View {
        @AppStorage("showCorporationAffairs") private var showCorporationAffairs: Bool = false

        var body: some View {
            HStack {
                Toggle(isOn: $showCorporationAffairs) {
                    VStack(alignment: .leading) {
                        Text(
                            NSLocalizedString("Main_Setting_Show_Corporation_Affairs", comment: "")
                        )
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        Text(
                            NSLocalizedString(
                                "Main_Setting_Show_Corporation_Affairs_detail", comment: ""
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    }
                }
                .tint(.green)
            }
        }
    }

    private struct ShowImportantAttributesToggle: View {
        @State private var showImportantOnly: Bool = AttributeDisplayConfig.showImportantOnly

        var body: some View {
            HStack {
                Toggle(isOn: $showImportantOnly) {
                    VStack(alignment: .leading) {
                        Text(
                            NSLocalizedString(
                                "Main_Database_Show_Important_Only", comment: "只显示重要属性")
                        )
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        Text(
                            NSLocalizedString(
                                "Main_Database_Show_Important_Only_Detail",
                                comment: "只显示有display_name的属性"
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    }
                }
                .tint(.green)
                .onChange(of: showImportantOnly) { _, newValue in
                    AttributeDisplayConfig.showImportantOnly = newValue
                }
            }
        }
    }

    private func createCorporationAffairsGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Corporation_Affairs", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Show_Corporation_Affairs", comment: ""),
                    detail: nil,
                    iconColor: .blue,
                    action: {}
                ) { _ in
                    AnyView(CorporationAffairsToggle())
                }
            ]
        )
    }

    private func createOthersGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Others", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Language", comment: ""),
                    detail: NSLocalizedString("Main_Setting_Select_your_language", comment: ""),
                    icon: "translate",
                    action: { showingLanguageView = true }
                ),
                SettingItem(
                    title: NSLocalizedString("Main_Setting_ESI_Status", comment: ""),
                    detail: NSLocalizedString("Main_Setting_ESI_Status_Detail", comment: ""),
                    icon: "waveform.path.ecg.rectangle",
                    iconColor: .blue,
                    action: { showingESIStatusView = true }
                ),
                SettingItem(
                    title: NSLocalizedString("Main_Database_Attribute_Settings", comment: "属性显示设置"),
                    detail: nil,
                    iconColor: .blue,
                    action: {}
                ) { _ in
                    AnyView(ShowImportantAttributesToggle())
                },
            ]
        )
    }

    private func createCacheGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Cache", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Clean_Cache", comment: ""),
                    detail: cacheSize,
                    icon: isCleaningCache ? "arrow.triangle.2.circlepath" : "trash",
                    iconColor: .red,
                    action: { showingCleanCacheAlert = true }
                ),
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Reset_Icons", comment: ""),
                    detail: isReextractingIcons
                        ? String(format: "%.0f%%", unzipProgress * 100)
                        : NSLocalizedString("Main_Setting_Reset_Icons_Detail", comment: ""),
                    icon: isReextractingIcons
                        ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath",
                    iconColor: .red,
                    action: { showingDeleteIconsAlert = true }
                ),
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Reset_Database", comment: ""),
                    detail: NSLocalizedString("Main_Setting_Reset_Database_Detail", comment: ""),
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .red,
                    action: { showResetDatabaseAlert = true }
                ),
            ]
        )
    }

    // 添加一个新的视图组件来优化列表项渲染
    private struct SettingItemView: View {
        let item: SettingItem
        let isCleaningCache: Bool
        let showingLoadingView: Bool

        var body: some View {
            if let customView = item.customView {
                customView(item)
                    .disabled(isCleaningCache || showingLoadingView)
            } else {
                Button(action: item.action) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        if let icon = item.icon {
                            if item.title
                                == NSLocalizedString("Main_Setting_Clean_Cache", comment: "")
                                && isCleaningCache
                            {
                                ProgressView()
                                    .frame(width: 36)
                            } else {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .frame(width: 36)
                                    .foregroundColor(item.iconColor)
                            }
                        }
                    }
                }
                .disabled(isCleaningCache || showingLoadingView)
            }
        }
    }

    // MARK: - 视图主体

    var body: some View {
        List {
            ForEach(settingGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        SettingItemView(
                            item: item,
                            isCleaningCache: isCleaningCache,
                            showingLoadingView: showingLoadingView
                        )
                    }
                } header: {
                    Text(group.header)
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(isPresented: $showingLanguageView) {
            SelectLanguageView(databaseManager: databaseManager)
        }
        .navigationDestination(isPresented: $showingESIStatusView) {
            ESIStatusView()
        }
        .alert(
            NSLocalizedString("Main_Setting_Clean_Cache_Title", comment: ""),
            isPresented: $showingCleanCacheAlert
        ) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Main_Setting_Clean", comment: ""), role: .destructive) {
                cleanCache()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Clean_Cache_Message", comment: ""))
        }
        .alert(
            NSLocalizedString("Main_Setting_Reset_Icons_Title", comment: ""),
            isPresented: $showingDeleteIconsAlert
        ) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Main_Setting_Reset", comment: ""), role: .destructive) {
                deleteIconsAndRestart()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Reset_Icons_Message", comment: ""))
        }
        .alert(
            NSLocalizedString("Main_Setting_Reset_Database_Title", comment: ""),
            isPresented: $showResetDatabaseAlert
        ) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Main_Setting_Reset", comment: ""), role: .destructive) {
                CharacterDatabaseManager.shared.resetDatabase()
                showResetDatabaseSuccessAlert = true
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Reset_Database_Message", comment: ""))
        }
        .alert(
            NSLocalizedString("Main_Setting_Reset_Database_Success_Title", comment: ""),
            isPresented: $showResetDatabaseSuccessAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Main_Setting_Reset_Database_Success_Message", comment: ""))
        }
        .onAppear {
            updateAllData()  // 首次加载时异步计算并更新缓存大小
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            updateAllData()  // 从后台返回时更新
        }
        .onChange(of: selectedTheme) { _, _ in
            updateSettingGroups()  // 主题改变时更新
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .fullScreenCover(isPresented: $showingLoadingView) {
            FullScreenCover(
                progress: unzipProgress,
                loadingState: $loadingState,
                onComplete: {
                    showingLoadingView = false
                    updateAllData()  // 重置图标完成后更新
                }
            )
        }
    }

    // MARK: - 主题管理

    private func getThemeIcon() -> String {
        switch selectedTheme {
        case "light":
            return "sun.max.fill"
        case "dark":
            return "moon.fill"
        case "system":
            return "circle.lefthalf.fill"
        default:
            return "circle.lefthalf.fill"
        }
    }

    private func getAppearanceDetail() -> String {
        switch selectedTheme {
        case "light":
            return NSLocalizedString("Main_Setting_Light", comment: "")
        case "dark":
            return NSLocalizedString("Main_Setting_Dark", comment: "")
        case "system":
            return NSLocalizedString("Main_Setting_Auto", comment: "")
        default:
            return NSLocalizedString("Main_Setting_Auto", comment: "")
        }
    }

    // MARK: - 缓存管理

    private func cleanCache() {
        Task {
            isCleaningCache = true
            defer { isCleaningCache = false }

            do {
                // 清理所有缓存
                await CacheManager.shared.clearAllCaches()

                // 更新UI
                await MainActor.run {
                    updateAllData()
                }

                Logger.info("Cache cleaned successfully")
            }
        }
    }

    // MARK: - 图标管理

    private func deleteIconsAndRestart() {
        Task {
            isReextractingIcons = true
            showingLoadingView = true
            loadingState = .processing

            let fileManager = FileManager.default
            let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let iconPath = documentPath.appendingPathComponent("Icons")

            do {
                // 1. 删除现有图标
                if fileManager.fileExists(atPath: iconPath.path) {
                    try fileManager.removeItem(at: iconPath)
                    Logger.info("Successfully deleted Icons directory")
                }

                // 2. 重置解压状态
                IconManager.shared.isExtractionComplete = false

                // 3. 重新解压图标
                guard let bundleIconPath = Bundle.main.path(forResource: "icons", ofType: "zip")
                else {
                    Logger.error("icons.zip file not found in bundle")
                    return
                }

                let iconURL = URL(fileURLWithPath: bundleIconPath)
                try await IconManager.shared.unzipIcons(from: iconURL, to: iconPath) { progress in
                    Task { @MainActor in
                        self.unzipProgress = progress
                    }
                }

                Logger.info("Successfully reextracted icons")

                await MainActor.run {
                    loadingState = .complete
                }
            } catch {
                Logger.error("Error reextracting icons: \(error)")
                await MainActor.run {
                    showingLoadingView = false
                }
            }

            await MainActor.run {
                isReextractingIcons = false
                showingDeleteIconsAlert = false
            }
        }
    }
}
