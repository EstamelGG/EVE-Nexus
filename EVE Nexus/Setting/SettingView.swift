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
        // 1. 清理URLCache
        URLCache.shared.removeAllCachedResponses()
        
        // 2. 清理NSCache（如果有自定义实例）
        // yourNSCache.removeAllObjects()
        
        // 3. 清理临时文件
        let tempPath = NSTemporaryDirectory()
        do {
            let tempFiles = try fileManager.contentsOfDirectory(atPath: tempPath)
            for file in tempFiles {
                let filePath = (tempPath as NSString).appendingPathComponent(file)
                try fileManager.removeItem(atPath: filePath)
            }
        } catch {
            Logger.error("Error clearing temp files: \(error)")
        }
        
        // 4. 清理NetworkManager缓存
        NetworkManager.shared.clearAllCaches()
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
                    icon: "trash",
                    iconColor: .red,
                    action: { showingCleanCacheAlert = true }
                ),
                SettingItem(
                    title: "重置图标缓存",
                    detail: "删除所有图标缓存并重启应用",
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .red,
                    action: { showingDeleteIconsAlert = true }
                )
            ])
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
                                Image(systemName: item.icon)
                                    .font(.system(size: 20))
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(item.iconColor)
                            }
                            .frame(height: 36)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .navigationDestination(isPresented: $showingLanguageView) {
            SelectLanguageView(databaseManager: databaseManager)
        }
        .alert("清理缓存", isPresented: $showingCleanCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                cleanCache()
            }
        } message: {
            Text("这将清理应用缓存，包括网络缓存和临时文件。是否确认？")
        }
        .alert("重置图标缓存", isPresented: $showingDeleteIconsAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                deleteIconsAndRestart()
            }
        } message: {
            Text("这将删除所有已下载的图标缓存并重启应用。是否确认？")
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
        
        var details = "\(formatFileSize(totalSize))"
        details += "\n总数量：\(totalCount) 项"
        
        // 添加详细统计
        if !cacheDetails.isEmpty {
            details += "\n\n各项统计："
            for (type, stats) in cacheDetails.sorted(by: { $0.key < $1.key }) {
                if stats.size > 0 || stats.count > 0 {
                    details += "\n• \(type)：\(formatFileSize(stats.size)) (\(stats.count) 项)"
                }
            }
        }
        
        return details
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
        Task {
            await CacheManager.shared.clearAllCaches()
            let stats = await CacheManager.shared.getAllCacheStats()
            await MainActor.run {
                cacheDetails = stats
            }
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
}

#Preview {
    SettingView(databaseManager: DatabaseManager())
}
