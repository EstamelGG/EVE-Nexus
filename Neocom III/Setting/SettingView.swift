import SwiftUI

// 定义设置项，destination 为 Any? 类型
struct SettingItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String? // 可选的详细描述
    var destination: Any? // 目标视图为 Any? 类型
    
    init(title: String, detail: String? = nil, destination: Any? = nil) {
        self.title = title
        self.detail = detail
        self.destination = destination
    }
}

// 设置项管理器
class SettingsManager {
    static let shared = SettingsManager()

    // 获取所有设置项
    func getSettingItems() -> [SettingItem] {
        return [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Language", comment: "Language section"),
                detail: NSLocalizedString("Main_Setting_Select your language", comment: ""),
                destination: SelectLanguageView() // 目标视图为 SelectLanguageView
            ),
            // 可以在此处添加更多的设置项
            // SettingItem(title: "Notifications", detail: "Enable notifications"),
        ]
    }
}

// 设置视图页面
struct SettingView: View {
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var currentIcon: String = "circle.lefthalf.fill"
    
    var body: some View {
        NavigationView {
            List {
                // 设置项：外观
                Section(header: Text(NSLocalizedString("Main_Setting_Appearance", comment: ""))) {
                    Button(action: toggleAppearance) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Main_Setting_ColorMode", comment: ""))
                                    .font(.system(size: 16))
                                Text(getAppearanceDetail() ?? "Unknown")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: currentIcon)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                        }
                        .frame(height: 36)
                    }
                }
                
                // 设置项：其他
                Section(header: Text(NSLocalizedString("Main_Setting_Others", comment: ""))) {
                    ForEach(SettingsManager.shared.getSettingItems()) { item in
                        NavigationLink(destination: viewForDestination(item.destination)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                        .font(.system(size: 16))
                                        .fontWeight(.medium)
                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .frame(height: 36)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        }
    }
    
    private func toggleAppearance() {
        switch selectedTheme {
        case "light":
            selectedTheme = "dark"
            currentIcon = "moon.fill"
        case "dark":
            selectedTheme = "system"
            currentIcon = "circle.lefthalf.fill"
        case "system":
            selectedTheme = "light"
            currentIcon = "sun.max.fill"
        default:
            break
        }
    }

    private func updateCurrentIcon() {
        switch selectedTheme {
        case "light":
            currentIcon = "sun.max.fill"
        case "dark":
            currentIcon = "moon.fill"
        case "system":
            currentIcon = "circle.lefthalf.fill"
        default:
            currentIcon = "circle.lefthalf.fill"
        }
    }

    private func getAppearanceDetail() -> String? {
        switch selectedTheme {
        case "light":
            return NSLocalizedString("Main_Setting_Light", comment: "")
        case "dark":
            return NSLocalizedString("Main_Setting_Dark", comment: "")
        case "system":
            return NSLocalizedString("Main_Setting_Auto", comment: "")
        default:
            return nil
        }
    }

    // 根据 destination 类型返回对应视图
    private func viewForDestination(_ destination: Any?) -> some View {
        if let view = destination as? SelectLanguageView {
            return AnyView(view)
        } else {
            return AnyView(Text("Unknown destination"))
        }
    }
}

#Preview {
    SettingView()
}
