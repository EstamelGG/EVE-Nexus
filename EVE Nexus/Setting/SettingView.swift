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

struct SettingView: View {
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var showingCleanCacheAlert = false
    @State private var showingLanguageView = false
    @ObservedObject var databaseManager: DatabaseManager
    
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
                    detail: NSLocalizedString("Main_Setting_Clean_Cache_detail", comment: ""),
                    icon: "trash",
                    iconColor: .red,
                    action: { showingCleanCacheAlert = true }
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
        .alert("Clean Cache", isPresented: $showingCleanCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clean", role: .destructive) {
                cleanCache()
            }
        } message: {
            Text("This will clean the icons cache and restart the app. Are you sure?")
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
    
    private func cleanCache() {
        let fileManager = FileManager.default
        let destinationPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Icons")
        
        do {
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
                Logger.info("Successfully deleted Icons directory")
                
                // 确保目录被完全删除
                if !fileManager.fileExists(atPath: destinationPath.path) {
                    Logger.debug("Verified: Icons directory has been removed")
                    // 等待文件系统完成操作
                    Thread.sleep(forTimeInterval: 0.5)
                    exit(0)
                } else {
                    Logger.warning("Warning: Icons directory still exists after deletion")
                }
            } else {
                Logger.error("Icons directory does not exist")
                exit(0)
            }
        } catch {
            Logger.error("Error deleting Icons directory: \(error)")
        }
    }
}

#Preview {
    SettingView(databaseManager: DatabaseManager())
}
