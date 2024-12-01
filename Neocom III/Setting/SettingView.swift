import SwiftUI

// 设置项结构，destination 现在使用 Any 类型
struct SettingItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String? // 可选的详细描述
    let destination: Any // 目标视图类型为 Any

    init(title: String, detail: String? = nil, destination: Any? = nil) {
        self.title = title
        self.detail = detail
        self.destination = destination ?? Text("Unknown destination")
    }
}

// 设置视图页面
struct SettingView: View {
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var currentIcon: String = "circle.lefthalf.fill"
    
    // 获取设置项
    private let settingItems: [SettingItem] = [
        SettingItem(
            title: NSLocalizedString("Main_Setting_Language", comment: "Language section"),
            detail: NSLocalizedString("Main_Setting_Select your language", comment: ""),
            destination: SelectLanguageView() // 目标视图
        ),
        // 更多设置项
    ]
    
    var body: some View {
        List {
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
            
            Section(header: Text(NSLocalizedString("Main_Setting_Others", comment: ""))) {
                ForEach(settingItems) { item in
                    NavigationLink(destination: destinationView(for: item.destination)) {
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
    
    // 根据目标视图的类型返回视图
    private func destinationView(for destination: Any) -> some View {
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
