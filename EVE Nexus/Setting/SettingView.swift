import SwiftUI
import UIKit

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

// MARK: - 缓存模型

struct CacheStats {
    var size: Int64
    var count: Int

    static func + (lhs: CacheStats, rhs: CacheStats) -> CacheStats {
        return CacheStats(size: lhs.size + rhs.size, count: lhs.count + rhs.count)
    }
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
        "Logs", // 日志
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
                    // 只统计目录中的文件数量
                    var fileCount = 0
                    
                    if let enumerator = fileManager.enumerator(
                        at: dirPath,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) {
                        for case _ as URL in enumerator {
                            // 只计算文件数量
                            fileCount += 1
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

    // 获取所有缓存统计信息
    func getAllCacheStats() async -> [String: CacheStats] {
        var stats: [String: CacheStats] = [:]

        // 2. NSCache统计
        stats["Memory"] = getNSCacheStats()

        // 3. UserDefaults统计
        stats["UserDefaults"] = getUserDefaultsStats()

        // 4. 临时文件统计
        stats["Temp"] = await getTempFileStats()

        // 5. 静态资源统计
        stats["StaticDataSet"] = await getStaticDataStats()

        // 6. 添加目录缓存统计
        let dirStats = await getDirectoryCacheStats()
        stats.merge(dirStats) { _, new in new }

        return stats
    }

    // 获取目录缓存统计
    private func getDirectoryCacheStats() async -> [String: CacheStats] {
        var stats: [String: CacheStats] = [:]
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for dirName in cacheDirs {
            let dirPath = documentPath.appendingPathComponent(dirName)
            var totalSize: Int64 = 0
            var fileCount = 0

            if fileManager.fileExists(atPath: dirPath.path),
                let enumerator = fileManager.enumerator(
                    at: dirPath,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
            {
                for case let fileURL as URL in enumerator {
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                        totalSize += Int64(attributes[.size] as? UInt64 ?? 0)
                        fileCount += 1
                    } catch {
                        Logger.error("Error calculating file size for \(fileURL.path): \(error)")
                    }
                }
            }

            stats[dirName] = CacheStats(size: totalSize, count: fileCount)
        }

        return stats
    }

    // 获取NSCache统计（如果您的应用使用了自定义的NSCache实例，需要在这里添加）
    private func getNSCacheStats() -> CacheStats {
        let totalCount = 0

        // 如果您有自定义的NSCache实例，在这里添加统计代码
        // 例如：totalCount += yourNSCache.totalCostLimit

        return CacheStats(
            size: 0,  // NSCache不提供大小信息
            count: totalCount
        )
    }

    // 获取UserDefaults统计
    private func getUserDefaultsStats() -> CacheStats {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()

        var totalSize: Int64 = 0
        let count = dictionary.count

        // 估算UserDefaults大小
        for (_, value) in dictionary {
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: value, requiringSecureCoding: false
            ) {
                totalSize += Int64(data.count)
            }
        }

        return CacheStats(size: totalSize, count: count)
    }

    // 获取临时文件统计
    private func getTempFileStats() async -> CacheStats {
        let tempPath = NSTemporaryDirectory()
        var totalSize: Int64 = 0
        var fileCount = 0

        if let tempEnumerator = fileManager.enumerator(atPath: tempPath) {
            for case let fileName as String in tempEnumerator {
                let filePath = (tempPath as NSString).appendingPathComponent(fileName)
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    totalSize += Int64(attributes[.size] as? UInt64 ?? 0)
                    fileCount += 1
                } catch {
                    Logger.error("Error calculating temp file size: \(error)")
                }
            }
        }

        return CacheStats(size: totalSize, count: fileCount)
    }

    // 获取静态资源统计
    private func getStaticDataStats() async -> CacheStats {
        let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
        var totalSize: Int64 = 0
        var fileCount = 0

        if fileManager.fileExists(atPath: staticDataSetPath.path),
            let enumerator = fileManager.enumerator(atPath: staticDataSetPath.path)
        {
            for case let fileName as String in enumerator {
                let filePath = (staticDataSetPath.path as NSString).appendingPathComponent(fileName)
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    totalSize += Int64(attributes[.size] as? UInt64 ?? 0)
                    fileCount += 1
                } catch {
                    Logger.error("Error calculating static data size: \(error)")
                }
            }
        }

        return CacheStats(size: totalSize, count: fileCount)
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

        // 9. 清理 URL Session 缓存
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
    @AppStorage("showCorporationAffairs") private var showCorporationAffairs: Bool = false
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames: Bool = true
    @State private var showingCleanCacheAlert = false
    @State private var showingDeleteIconsAlert = false
    @State private var showingLanguageView = false
    @State private var cacheSize: String = "Calc..."
    @ObservedObject var databaseManager: DatabaseManager
    @State private var cacheDetails: [String: CacheStats] = [:]
    @State private var isCleaningCache = false
    @State private var isReextractingIcons = false
    @State private var unzipProgress: Double = 0
    @State private var loadingState: LoadingState = .unzipping
    @State private var showingLoadingView = false
    @State private var settingGroups: [SettingGroup] = []
    @State private var resourceInfoCache: [String: String] = [:]
    @State private var showingLogViewer = false
    @State private var showResetIconsAlert = false
    @State private var showResetDatabaseAlert = false
    @State private var showResetDatabaseSuccessAlert = false
    @State private var showingESIStatusView = false

    // MARK: - 时间处理工具

    private func getRelativeTimeString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)

        if let days = components.day, days > 0 {
            return String(format: NSLocalizedString("Time_Days_Ago", comment: ""), days)
        } else if let hours = components.hour, hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Ago", comment: ""), hours)
        } else if let minutes = components.minute, minutes > 0 {
            return String(format: NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes)
        } else {
            return NSLocalizedString("Time_Just_Now", comment: "")
        }
    }

    // MARK: - 数据更新函数

    private func updateAllData() {
        Task {
            // 统计 StaticDataSet 目录大小
            let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
            var totalSize: Int64 = 0

            if FileManager.default.fileExists(atPath: staticDataSetPath.path) {
                if let enumerator = FileManager.default.enumerator(
                    at: staticDataSetPath,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [
                                .isDirectoryKey
                            ])
                            // 跳过目录，只计算文件大小
                            if resourceValues.isDirectory == true {
                                continue
                            }

                            let attributes = try FileManager.default.attributesOfItem(
                                atPath: fileURL.path)
                            if let fileSize = attributes[.size] as? Int64 {
                                totalSize += fileSize
                            }
                        } catch {
                            Logger.error(
                                "Error calculating file size for \(fileURL.path): \(error)")
                        }
                    }
                } else {
                    Logger.error("Failed to create directory enumerator")
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
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                   ) {
                    for case let fileURL as URL in enumerator {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [
                                .isDirectoryKey
                            ])
                            // 跳过目录，只计算文件大小
                            if resourceValues.isDirectory == true {
                                continue
                            }
                            Logger.info(
                                "Calculating file size for \(fileURL.path)")
                            let attributes = try fileManager.attributesOfItem(
                                atPath: fileURL.path)
                            if let fileSize = attributes[.size] as? Int64 {
                                totalSize += fileSize
                            }
                        } catch {
                            Logger.error(
                                "Error calculating file size for \(fileURL.path): \(error)")
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
                //            SettingItem(
                //                title: NSLocalizedString("Main_Setting_Logs", comment: ""),
                //                detail: NSLocalizedString("Main_Setting_Logs_Detail", comment: ""),
                //                icon: "doc.text.magnifyingglass",
                //                action: { showingLogViewer = true }
                //            )
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

    // MARK: - 资源管理

    private func refreshResource(_: StaticResourceManager.ResourceInfo) {
        // 图片资源是按需加载的，不需要手动刷新
        Logger.info("Image resources are refreshed on-demand")
    }

    // MARK: - 资源信息格式化

    private func formatRemainingTime(_ remaining: TimeInterval) -> String {
        let days = Int(remaining / (24 * 3600))
        let hours = Int((remaining.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            // 如果有天数，显示天和小时
            return String(
                format: NSLocalizedString("Main_Setting_Cache_Expiration_Days_Hours", comment: ""),
                days, hours
            )
        } else if hours > 0 {
            // 如果有小时，显示小时和分钟
            return String(
                format: NSLocalizedString(
                    "Main_Setting_Cache_Expiration_Hours_Minutes", comment: ""
                ), hours, minutes
            )
        } else {
            // 只剩分钟
            return String(
                format: NSLocalizedString("Main_Setting_Cache_Expiration_Minutes", comment: ""),
                minutes
            )
        }
    }

    private func formatResourceInfo(_ resource: StaticResourceManager.ResourceInfo) -> String {
        if resource.exists && resource.fileSize != nil && resource.fileSize! > 0 {
            var info = ""
            if let fileSize = resource.fileSize {
                info += FormatUtil.formatFileSize(fileSize)
            }

            // 只显示文件大小和最后更新时间
            if let lastModified = resource.lastModified {
                info +=
                    "\n"
                    + String(
                        format: NSLocalizedString(
                            "Main_Setting_Static_Resource_Last_Updated", comment: ""
                        ),
                        getRelativeTimeString(from: lastModified)
                    )
            }

            return info
        } else {
            return NSLocalizedString("Main_Setting_Static_Resource_No_Cache", comment: "")
        }
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
                        .fontWeight(.bold)
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
        .navigationDestination(isPresented: $showingLogViewer) {
            LogViewer()
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

    private func formatCacheDetails() -> String {
        // 如果正在清理，显示"-"
        if isCleaningCache {
            return "-"
        }

        let totalSize = cacheDetails.values.reduce(0) { $0 + $1.size }
        let totalCount = cacheDetails.values.reduce(0) { $0 + $1.count }

        var details = FormatUtil.formatFileSize(totalSize)
        details += String(
            format: NSLocalizedString("Main_Setting_Cache_Total_Count", comment: ""), totalCount
        )

        // 添加详细统计
        if !cacheDetails.isEmpty {
            details += "\n\n" + NSLocalizedString("Main_Setting_Cache_Details", comment: "")
            for (type, stats) in cacheDetails.sorted(by: { $0.key < $1.key }) {
                if stats.size > 0 || stats.count > 0 {
                    let typeLocalized = localizedCacheType(type)
                    details +=
                        "\n• "
                        + String(
                            format: NSLocalizedString(
                                "Main_Setting_Cache_Item_Format", comment: ""
                            ),
                            typeLocalized,
                            FormatUtil.formatFileSize(stats.size),
                            stats.count
                        )
                }
            }
        }

        return details
    }

    private func localizedCacheType(_ type: String) -> String {
        switch type {
        case "Network":
            return NSLocalizedString("Main_Setting_Cache_Type_Network", comment: "")
        case "Memory":
            return NSLocalizedString("Main_Setting_Cache_Type_Memory", comment: "")
        case "UserDefaults":
            return NSLocalizedString("Main_Setting_Cache_Type_UserDefaults", comment: "")
        case "Temp":
            return NSLocalizedString("Main_Setting_Cache_Type_Temp", comment: "")
        case "Database":
            return NSLocalizedString("Main_Setting_Cache_Type_Database", comment: "")
        case "StaticDataSet":
            return NSLocalizedString("Main_Setting_Cache_Type_StaticDataSet", comment: "")
        case "CharacterPortraits":
            return NSLocalizedString("Main_Setting_Cache_Type_Character_Portraits", comment: "")
        case "FactionIcons":
            return NSLocalizedString("Main_Setting_Static_Resource_Faction_Icons", comment: "")
        case "NetRenders":
            return NSLocalizedString("Main_Setting_Cache_Type_Net_Renders", comment: "")
        case "MarketData":
            return NSLocalizedString("Main_Setting_Cache_Type_Market_Data", comment: "")
        default:
            return type
        }
    }

    private func calculateCacheSize() {
        Task {
            let stats = await CacheManager.shared.getAllCacheStats()
            // 在主线程更新 UI
            await MainActor.run {
                self.cacheDetails = stats
            }
        }
    }

    private func formatFileSize(_ size: Int64) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }

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
            loadingState = .unzipping

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
