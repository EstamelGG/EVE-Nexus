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
    
    init(title: String, detail: String? = nil, icon: String? = nil, iconColor: Color = .blue, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
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
    
    // 获取所有缓存统计信息
    func getAllCacheStats() async -> [String: CacheStats] {
        var stats: [String: CacheStats] = [:]
        
        // 1. URLCache统计
        stats["Network"] = getURLCacheStats()
        
        // 2. NSCache统计
        stats["Memory"] = getNSCacheStats()
        
        // 3. UserDefaults统计
        stats["UserDefaults"] = getUserDefaultsStats()
        
        // 4. 临时文件统计
        stats["Temp"] = await getTempFileStats()
        
        // 5. 静态资源统计
        stats["StaticDataSet"] = await getStaticDataStats()
        
        return stats
    }
    
    // 获取URLCache统计
    private func getURLCacheStats() -> CacheStats {
        let urlCache = URLCache.shared
        return CacheStats(
            size: Int64(urlCache.currentDiskUsage + urlCache.currentMemoryUsage),
            count: 1  // URLCache不提供缓存项数量的API
        )
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
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false) {
                totalSize += Int64(data.count)
            }
        }
        
        return CacheStats(size: totalSize, count: count)
    }
    
    // 获取临时文件统计
    private func getTempFileStats() async -> CacheStats {
        let tempPath = NSTemporaryDirectory()
        var totalSize: Int64 = 0
        var fileCount: Int = 0
        
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
        var fileCount: Int = 0
        
        if fileManager.fileExists(atPath: staticDataSetPath.path),
           let enumerator = fileManager.enumerator(atPath: staticDataSetPath.path) {
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
        NetworkManager.shared.clearAllCaches()
        
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
            Logger.error("Error clearing temp files: \(error)")
        }
        
        // 3. 清理入侵相关缓存
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "incursions_cache")
            InfestedSystemsViewModel.clearCache()
        }
        
        // 4. 清理数据库浏览器缓存
        await MainActor.run {
            DatabaseBrowserView.clearCache()
        }
        
        // 5. 清理静态资源
        do {
            try StaticResourceManager.shared.clearAllStaticData()
        } catch {
            Logger.error("Error clearing static data: \(error)")
        }
        
        // 6. 清理 URLCache（最后执行）
        await MainActor.run {
            URLCache.shared.removeAllCachedResponses()
        }
        
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
    private struct FullScreenCover: View {
        let progress: Double
        @Binding var loadingState: LoadingState
        let onComplete: () -> Void
        
        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .opacity(0.8)
                    
                    LoadingView(loadingState: $loadingState,
                              progress: progress,
                              onComplete: onComplete)
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
    @State private var cacheSize: String = "Calc..."
    @ObservedObject var databaseManager: DatabaseManager
    @State private var cacheDetails: [String: CacheStats] = [:]
    @State private var isCleaningCache = false
    @State private var isReextractingIcons = false
    @State private var unzipProgress: Double = 0
    @State private var loadingState: LoadingState = .unzipping
    @State private var showingLoadingView = false
    @State private var refreshingResources: Set<String> = []
    
    // 新增状态属性
    @State private var settingGroups: [SettingGroup] = []
    @State private var resourceInfoCache: [String: String] = [:]
    
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
            let stats = await CacheManager.shared.getAllCacheStats()
            await MainActor.run {
                self.cacheDetails = stats
                updateSettingGroups()
            }
        }
    }
    
    private func updateSettingGroups() {
        settingGroups = [
            createAppearanceGroup(),
            createOthersGroup(),
            createCacheGroup(),
            createStaticResourceGroup()
        ]
    }
    
    // MARK: - 设置组创建函数
    private func createAppearanceGroup() -> SettingGroup {
        SettingGroup(header: NSLocalizedString("Main_Setting_Appearance", comment: ""), items: [
            SettingItem(
                title: NSLocalizedString("Main_Setting_ColorMode", comment: ""),
                detail: getAppearanceDetail(),  // 将当前主题状态作为详情文本
                icon: getThemeIcon(),
                iconColor: .blue,
                action: toggleAppearance
            )
        ])
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
    
    private func createOthersGroup() -> SettingGroup {
        SettingGroup(header: NSLocalizedString("Main_Setting_Others", comment: ""), items: [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Language", comment: ""),
                detail: NSLocalizedString("Main_Setting_Select your language", comment: ""),
                icon: "globe",
                action: { showingLanguageView = true }
            )
        ])
    }
    
    private func createCacheGroup() -> SettingGroup {
        SettingGroup(header: "Cache", items: [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Clean_Cache", comment: ""),
                detail: formatCacheDetails(),
                icon: isCleaningCache ? "arrow.triangle.2.circlepath" : "trash",
                iconColor: .red,
                action: { showingCleanCacheAlert = true }
            ),
            SettingItem(
                title: NSLocalizedString("Main_Setting_Reset_Icons", comment: ""),
                detail: isReextractingIcons ? 
                    String(format: "%.0f%%", unzipProgress * 100) :
                    NSLocalizedString("Main_Setting_Reset_Icons_Detail", comment: ""),
                icon: isReextractingIcons ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath",
                iconColor: .red,
                action: { showingDeleteIconsAlert = true }
            )
        ])
    }
    
    private func createStaticResourceGroup() -> SettingGroup {
        let items = StaticResourceManager.shared.getAllResourcesStatus().map { resource in
            var title = resource.name
            if let downloadTime = resource.downloadTime {
                title += " (" + getRelativeTimeString(from: downloadTime) + ")"
            }
            
            if let type = StaticResourceManager.ResourceType.allCases.first(where: { $0.displayName == resource.name }) {
                switch type {
                case .sovereignty, .incursions, .sovereigntyCampaigns:
                    let isRefreshingThis = refreshingResources.contains(resource.name)
                    
                    let isExpired = resource.exists && resource.lastModified != nil && 
                        Date().timeIntervalSince(resource.lastModified!) > type.cacheDuration
                    
                    return SettingItem(
                        title: title,
                        detail: formatResourceInfo(resource),
                        icon: isRefreshingThis ? "arrow.triangle.2.circlepath" : 
                              (resource.exists ? 
                                (isExpired ? "exclamationmark.triangle.fill" : "checkmark.circle.fill") : 
                                "arrow.triangle.2.circlepath"),
                        iconColor: isRefreshingThis ? .blue :
                                 (resource.exists ? 
                                    (isExpired ? .yellow : .green) : 
                                    .blue),
                        action: { refreshResource(resource) }
                    )
                case .allianceIcons, .netRenders, .marketData:
                    return SettingItem(
                        title: title,
                        detail: formatResourceInfo(resource),
                        action: { }
                    )
                }
            }
            
            return SettingItem(
                title: title,
                detail: formatResourceInfo(resource),
                action: { }
            )
        }
        
        return SettingGroup(header: NSLocalizedString("Main_Setting_Static_Resources", comment: ""), items: items)
    }
    
    // MARK: - 资源管理
    private func refreshResource(_ resource: StaticResourceManager.ResourceInfo) {
        // 如果该资源正在刷新中，直接返回
        guard !refreshingResources.contains(resource.name) else {
            return
        }
        
        Task {
            // 标记资源开始刷新
            await MainActor.run {
                refreshingResources.insert(resource.name)
                // 立即更新UI以显示加载状态
                updateSettingGroups()
            }
            
            do {
                // 找到的资源类型
                guard let type = StaticResourceManager.ResourceType.allCases.first(where: { $0.displayName == resource.name }) else {
                    Logger.error("Unknown resource type: \(resource.name)")
                    return
                }
                
                // 根据类型执行不同的刷新操作
                switch type {
                case .sovereignty:
                    Logger.info("Refreshing sovereignty data")
                    let sovereigntyData = try await NetworkManager.shared.fetchSovereigntyData(forceRefresh: true)
                    let jsonData = try JSONEncoder().encode(sovereigntyData)
                    try StaticResourceManager.shared.saveToFileAndCache(jsonData, filename: type.filename, cacheKey: type.rawValue)
                case .incursions:
                    Logger.info("Refreshing incursions data")
                    let incursionsData = try await NetworkManager.shared.fetchIncursions()
                    let jsonData = try JSONEncoder().encode(incursionsData)
                    try StaticResourceManager.shared.saveToFileAndCache(jsonData, filename: type.filename, cacheKey: type.rawValue)
                case .sovereigntyCampaigns:
                    Logger.info("Refreshing Sovereignty Campaigns data")
                    let sovCamp = try await NetworkManager.shared.fetchSovereigntyCampaigns(forceRefresh: true)
                    let jsonData = try JSONEncoder().encode(sovCamp)
                    try StaticResourceManager.shared.saveToFileAndCache(jsonData, filename: type.filename, cacheKey: type.rawValue)
                case .allianceIcons, .netRenders, .marketData:
                    Logger.info("Alliance icons and net renders are refreshed on-demand")
                    break
                }
                
                // 刷新完成后更新UI
                await MainActor.run {
                    refreshingResources.remove(resource.name)
                    // 立即更新UI以停止加载动画
                    updateSettingGroups()
                    updateAllData()
                }
            } catch {
                Logger.error("Failed to refresh resource: \(error)")
                // 发生错误时也要更新UI
                await MainActor.run {
                    refreshingResources.remove(resource.name)
                    // 立即更新UI以停止加载动画
                    updateSettingGroups()
                }
            }
        }
    }
    
    // MARK: - 辅助计算属性
    private func getResourceBaseName(_ title: String) -> String {
        return title.components(separatedBy: " (").first ?? title
    }
    
    private func isResourceRefreshing(_ title: String) -> Bool {
        return refreshingResources.contains(getResourceBaseName(title))
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
                            showingLoadingView: showingLoadingView,
                            isResourceRefreshing: isResourceRefreshing(item.title)
                        )
                    }
                } header: {
                    Text(group.header)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(isPresented: $showingLanguageView) {
            SelectLanguageView(databaseManager: databaseManager)
        }
        .alert(NSLocalizedString("Main_Setting_Clean_Cache_Title", comment: ""), isPresented: $showingCleanCacheAlert) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("Main_Setting_Clean", comment: ""), role: .destructive) {
                cleanCache()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Clean_Cache_Message", comment: ""))
        }
        .alert(NSLocalizedString("Main_Setting_Reset_Icons_Title", comment: ""), isPresented: $showingDeleteIconsAlert) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("Main_Setting_Reset", comment: ""), role: .destructive) {
                deleteIconsAndRestart()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Reset_Icons_Message", comment: ""))
        }
        .onAppear {
            updateAllData() // 首次加载时更新
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            updateAllData() // 从后台返回时更新
        }
        .onChange(of: selectedTheme) { _, _ in
            updateSettingGroups() // 主题改变时更新
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .fullScreenCover(isPresented: $showingLoadingView) {
            FullScreenCover(
                progress: unzipProgress,
                loadingState: $loadingState,
                onComplete: {
                    showingLoadingView = false
                    updateAllData() // 重置图标完成后更新
                }
            )
        }
    }
    
    // MARK: - 主题管理
    private func getThemeIcon() -> String {
        switch selectedTheme {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.fill"
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
        
        var details = formatFileSize(totalSize)
        details += String(format: NSLocalizedString("Main_Setting_Cache_Total_Count", comment: ""), totalCount)
        
        // 添加详细统计
        if !cacheDetails.isEmpty {
            details += "\n\n" + NSLocalizedString("Main_Setting_Cache_Details", comment: "")
            for (type, stats) in cacheDetails.sorted(by: { $0.key < $1.key }) {
                if stats.size > 0 || stats.count > 0 {
                    let typeLocalized = localizedCacheType(type)
                    details += "\n• " + String(format: NSLocalizedString("Main_Setting_Cache_Item_Format", comment: ""), 
                        typeLocalized,
                        formatFileSize(stats.size), 
                        stats.count)
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
        showingCleanCacheAlert = false
        isCleaningCache = true
        
        // 清空当前缓存显示
        cacheDetails = [:]
        
        Task {
            // 等待一小段时间，确保之前的文件操作都完成
            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2秒
            
            // 1. 清理网络缓存
            await CacheManager.shared.clearAllCaches()
            
            // 2. 清理 NetworkManager 的所有缓存
            NetworkManager.shared.clearAllCaches()
            
            // 3. 清理 StaticResourceManager 的内存缓存
            StaticResourceManager.shared.clearMemoryCache()
            
            // 4. 清理所有静态资源数据（包括文件和内存缓存）
            do {
                try StaticResourceManager.shared.clearAllStaticData()
            } catch {
                Logger.error("Failed to clear static data: \(error)")
            }
            
            // 5. 清理联盟图标缓存
            do {
                try StaticResourceManager.shared.clearAllianceIcons()
            } catch {
                Logger.error("Failed to clear alliance icons: \(error)")
            }
            
            // 6. 清理市场数据缓存
            do {
                try StaticResourceManager.shared.clearMarketData()
            } catch {
                Logger.error("Failed to clear market data: \(error)")
            }
            
            // 7. 清理渲染图缓存
            do {
                try StaticResourceManager.shared.clearNetRenders()
            } catch {
                Logger.error("Failed to clear net renders: \(error)")
            }
            
            // 8. 清理 UserDefaults 中的缓存相关数据
            let defaults = UserDefaults.standard
            for type in StaticResourceManager.ResourceType.allCases {
                defaults.removeObject(forKey: type.downloadTimeKey)
            }
            defaults.removeObject(forKey: "incursions_cache")
            
            // 9. 清理临时文件目录
            let fileManager = FileManager.default
            if let tmpDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                do {
                    let tmpContents = try fileManager.contentsOfDirectory(at: tmpDirectory, includingPropertiesForKeys: nil)
                    for url in tmpContents {
                        try? fileManager.removeItem(at: url)
                    }
                } catch {
                    Logger.error("Failed to clear temporary directory: \(error)")
                }
            }
            
            // 10. 清理 URLCache
            URLCache.shared.removeAllCachedResponses()
            
            // 11. 清理 Cookies
            if let cookies = HTTPCookieStorage.shared.cookies {
                for cookie in cookies {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
            
            // 等待所有清理操作完成
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1秒
            
            // 更新界面
            await MainActor.run {
                updateAllData()
                isCleaningCache = false
            }
            
            Logger.info("Cache cleaning completed")
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
                guard let bundleIconPath = Bundle.main.path(forResource: "icons", ofType: "zip") else {
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
    
    // MARK: - 资源信息格式化
    private func formatRemainingTime(_ remaining: TimeInterval) -> String {
        let days = Int(remaining / (24 * 3600))
        let hours = Int((remaining.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if days > 0 {
            // 如果有天数，显示天和小时
            return String(format: NSLocalizedString("Main_Setting_Cache_Expiration_Days_Hours", comment: ""), days, hours)
        } else if hours > 0 {
            // 如果有小时，显示小时和分钟
            return String(format: NSLocalizedString("Main_Setting_Cache_Expiration_Hours_Minutes", comment: ""), hours, minutes)
        } else {
            // 只剩分钟
            return String(format: NSLocalizedString("Main_Setting_Cache_Expiration_Minutes", comment: ""), minutes)
        }
    }
    
    private func formatResourceInfo(_ resource: StaticResourceManager.ResourceInfo) -> String {
        if resource.exists {
            var info = ""
            if let fileSize = resource.fileSize {
                info += formatFileSize(fileSize)
            }
            
            // 只为主权数据和入侵数据显示缓存有效期
            if let type = StaticResourceManager.ResourceType.allCases.first(where: { $0.displayName == resource.name }),
               let lastModified = resource.lastModified {
                switch type {
                case .sovereignty, .incursions, .sovereigntyCampaigns:
                    let duration = type.cacheDuration
                    let elapsed = Date().timeIntervalSince(lastModified)
                    let remaining = duration - elapsed
                    
                    if remaining > 0 {
                        info += " (" + formatRemainingTime(remaining) + ")"
                    } else {
                        info += " (" + NSLocalizedString("Main_Setting_Static_Resource_Expired", comment: "") + ")"
                    }
                    
                    info += "\n" + String(format: NSLocalizedString("Main_Setting_Static_Resource_Last_Updated", comment: ""), 
                        getRelativeTimeString(from: lastModified))
                default:
                    // 对于其他类型，只显示文件大小
                    break
                }
            }
            
            return info
        } else {
            // 根据资源类型返回不同的提示文本
            if let type = StaticResourceManager.ResourceType.allCases.first(where: { $0.displayName == resource.name }) {
                switch type {
                case .sovereignty, .incursions, .sovereigntyCampaigns:
                    return NSLocalizedString("Main_Setting_Static_Resource_Not_Downloaded", comment: "")
                case .allianceIcons, .netRenders, .marketData:
                    return NSLocalizedString("Main_Setting_Static_Resource_No_Cache", comment: "")
                }
            }
            return NSLocalizedString("Main_Setting_Static_Resource_Not_Downloaded", comment: "")
        }
    }
    
    // 添加一个新的视图组件来优化列表项渲染
    private struct SettingItemView: View {
        let item: SettingItem
        let isCleaningCache: Bool
        let showingLoadingView: Bool
        let isResourceRefreshing: Bool
        
        var body: some View {
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
                        if item.title == NSLocalizedString("Main_Setting_Clean_Cache", comment: "") && isCleaningCache {
                            ProgressView()
                                .frame(width: 36, height: 36)
                        } else if isResourceRefreshing {
                            ProgressView()
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .foregroundColor(item.iconColor)
                        }
                    }
                }
                .frame(height: 36)
            }
            .disabled(isCleaningCache || showingLoadingView)
        }
    }
}
