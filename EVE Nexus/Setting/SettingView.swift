import SwiftUI
import UIKit

// 设置项结构
struct SettingItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
    let icon: String
    let iconColor: Color
    let action: () -> Void
    
    init(title: String, detail: String? = nil, icon: String, iconColor: Color = .blue, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
    }
}

// 设置组结构
struct SettingGroup: Identifiable {
    let id = UUID()
    let header: String
    let items: [SettingItem]
}

// 缓存统计结构
struct CacheStats {
    var size: Int64
    var count: Int
    
    static func + (lhs: CacheStats, rhs: CacheStats) -> CacheStats {
        return CacheStats(size: lhs.size + rhs.size, count: lhs.count + rhs.count)
    }
}

// 缓存管理器
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
    
    // 清理所有缓存
    func clearAllCaches() async {
        await withTaskGroup(of: Void.self) { group in
            // 1. 清理URLCache（异步）
            group.addTask {
                await MainActor.run {
                    URLCache.shared.removeAllCachedResponses()
                }
            }
            
            // 2. 清理临时文件（异步）
            group.addTask {
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
            }
            
            // 3. 清理NetworkManager缓存
            group.addTask {
                NetworkManager.shared.clearAllCaches()
            }
            
            // 4. 清理URL Session缓存（异步）
            group.addTask {
                await self.clearURLSessionCacheAsync()
            }
            
            // 5. 清理入侵相关缓存（异步）
            group.addTask {
                await MainActor.run {
                    UserDefaults.standard.removeObject(forKey: "incursions_cache")
                    InfestedSystemsViewModel.clearCache()
                }
            }
            
            // 6. 清理数据库浏览器缓存
            group.addTask {
                await MainActor.run {
                    DatabaseBrowserView.clearCache()
                }
            }
            
            // 等待所有任务完成
            await group.waitForAll()
        }
        
        Logger.info("所有缓存清理完成")
    }
    
    // 异步清理URL Session缓存
    private func clearURLSessionCacheAsync() async {
        await MainActor.run {
            // 清理默认session的缓存
            URLCache.shared.removeAllCachedResponses()
            
            // 清理cookies
            if let cookies = HTTPCookieStorage.shared.cookies {
                for cookie in cookies {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
        
        // 清理磁盘缓存
        if let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
            do {
                let files = try await MainActor.run {
                    try self.fileManager.contentsOfDirectory(atPath: cachesPath)
                }
                for file in files where file.contains("com.apple.nsurlsessiond") {
                    let filePath = (cachesPath as NSString).appendingPathComponent(file)
                    try? await MainActor.run {
                        try self.fileManager.removeItem(atPath: filePath)
                    }
                }
            } catch {
                Logger.error("Error clearing URL session cache: \(error)")
            }
        }
    }
}

struct SettingView: View {
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var showingCleanCacheAlert = false
    @State private var showingDeleteIconsAlert = false
    @State private var showingLanguageView = false
    @State private var cacheSize: String = "计算中..."
    @ObservedObject var databaseManager: DatabaseManager
    @State private var cacheDetails: [String: CacheStats] = [:]
    @State private var isCleaningCache = false
    
    private var settingGroups: [SettingGroup] {
        [
            SettingGroup(header: NSLocalizedString("Main_Setting_Appearance", comment: ""), items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_ColorMode", comment: ""),
                    detail: getAppearanceDetail(),
                    icon: getThemeIcon(),
                    action: toggleAppearance
                )
            ]),
            
            SettingGroup(header: NSLocalizedString("Main_Setting_Others", comment: ""), items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Language", comment: ""),
                    detail: NSLocalizedString("Main_Setting_Select your language", comment: ""),
                    icon: "globe",
                    action: { showingLanguageView = true }
                )
            ]),
            
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
                    detail: NSLocalizedString("Main_Setting_Reset_Icons_Detail", comment: ""),
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .red,
                    action: { showingDeleteIconsAlert = true }
                )
            ]),
            
            SettingGroup(header: NSLocalizedString("Main_Setting_Static_Resources", comment: ""), items:
                StaticResourceManager.shared.getAllResourcesStatus().map { resource in
                    SettingItem(
                        title: NSLocalizedString("Main_Setting_Static_Resource_\(resource.name)", comment: ""),
                        detail: formatResourceInfo(resource),
                        icon: resource.exists ? "checkmark.circle.fill" : "xmark.circle.fill",
                        iconColor: resource.exists ? .green : .red,
                        action: {}
                    )
                }
            )
        ]
    }
    
    var body: some View {
        List {
            ForEach(settingGroups) { group in
                Section(
                    header: Text(group.header)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(nil)
                ) {
                    ForEach(group.items) { item in
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
                                if item.title == NSLocalizedString("Main_Setting_Clean_Cache", comment: "") && isCleaningCache {
                                    ProgressView()
                                        .frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 20))
                                        .frame(width: 36, height: 36)
                                        .foregroundColor(item.iconColor)
                                }
                            }
                            .frame(height: 36)
                        }
                        .disabled(isCleaningCache)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
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
            calculateCacheSize()
        }
    }
    
    private func getThemeIcon() -> String {
        switch selectedTheme {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.fill"
        }
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
    
    private func formatCacheDetails() -> String {
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
        default:
            return type
        }
    }
    
    private func calculateCacheSize() {
        Task {
            let stats = await CacheManager.shared.getAllCacheStats()
            await MainActor.run {
                cacheDetails = stats
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
        
        Task {
            // 1. 执行清理
            await CacheManager.shared.clearAllCaches()
            
            // 2. 重新计算缓存大小并立即更新UI
            calculateCacheSize()
            
            // 3. 隐藏加载指示器
            isCleaningCache = false
        }
    }
    
    private func deleteIconsAndRestart() {
        Task {
            let fileManager = FileManager.default
            let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let iconPath = documentPath.appendingPathComponent("Icons")
            
            do {
                if fileManager.fileExists(atPath: iconPath.path) {
                    try fileManager.removeItem(at: iconPath)
                    Logger.info("Successfully deleted Icons directory")
                }
                // 等待文件系统完成操作
                try await Task.sleep(for: .milliseconds(500))
                exit(0)
            } catch {
                Logger.error("Error deleting Icons directory: \(error)")
            }
        }
    }
    
    private func formatResourceInfo(_ resource: StaticResourceManager.ResourceInfo) -> String {
        if resource.exists {
            var info = ""
            if let size = resource.fileSize {
                info += formatFileSize(size)
            }
            if let date = resource.lastModified {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                info += "\n" + String(format: NSLocalizedString("Main_Setting_Static_Resource_Last_Updated", comment: ""), formatter.string(from: date))
            }
            return info
        } else {
            return NSLocalizedString("Main_Setting_Static_Resource_Not_Downloaded", comment: "")
        }
    }
}

#Preview {
    SettingView(databaseManager: DatabaseManager())
}
