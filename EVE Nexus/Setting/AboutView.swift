import SwiftUI

struct AboutView: View {
    private var appIcon: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last
        {
            return UIImage(named: lastIcon)
        }
        return UIImage(named: "DefaultAppIcon")
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Tritanium"
    }

    @State private var databaseVersionInfo: AppConfiguration.Database.VersionInfo?
    @State private var showingSDEUpdateSheet = false

    private var otherAboutItems: [AboutItem] {
        [
            AboutItem(
                title: NSLocalizedString("Main_About_Author", comment: ""),
                value: "iDea Center",
                icon: "person.fill",
                characterId: 96_873_368
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_Github", comment: ""),
                value: "https://github.com/EstamelGG/EVE-Nexus",
                icon: "link",
                url: URL(string: "https://github.com/EstamelGG/EVE-Nexus")
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_Report_Bug", comment: ""),
                value: "jzx1040798357@icloud.com",
                icon: "envelope.fill",
                url: URL(string: "mailto:jzx1040798357@icloud.com")
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_copyright_Title", comment: ""),
                value: "Copyright.md",
                icon: "link",
                url: URL(
                    string:
                    "https://raw.githubusercontent.com/EstamelGG/EVE-Nexus/refs/heads/main/Copyright.md"
                )
            ),
        ]
    }

    var body: some View {
        List {
            // App Logo Section
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        if let icon = appIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .cornerRadius(20)
                                .shadow(radius: 5)
                        }

                        Text(appName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("v\(AppConfiguration.Version.fullVersion)")
                            .font(.system(.body, design: .monospaced))
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 5)
            }

            // Database Version Section
            Section {
                DatabaseVersionRow(
                    versionInfo: databaseVersionInfo,
                    showingUpdateSheet: $showingSDEUpdateSheet
                )
            }

            // Information Section
            Section {
                ForEach(otherAboutItems) { item in
                    if let url = item.url {
                        Link(destination: url) {
                            AboutItemRow(item: item)
                        }
                    } else {
                        AboutItemRow(item: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingSDEUpdateSheet, onDismiss: {
            // 更新完成后重新加载数据库版本信息
            databaseVersionInfo = AppConfiguration.Database.detailedVersionInfo

            // 重新检查更新状态
            Task.detached(priority: .background) {
                await SDEUpdateChecker.shared.checkForUpdates()
            }
        }) {
            SDEUpdateDetailView()
                .interactiveDismissDisabled()
        }
        .onAppear {
            databaseVersionInfo = AppConfiguration.Database.detailedVersionInfo
        }
    }
}

// 数据库版本显示组件
struct DatabaseVersionRow: View {
    let versionInfo: AppConfiguration.Database.VersionInfo?
    @Binding var showingUpdateSheet: Bool

    // 使用 @StateObject 并限定在此组件内
    @StateObject private var updateChecker = SDEUpdateChecker.shared

    private var hasUpdate: Bool {
        updateChecker.updateStatus == .hasUpdate
    }

    private var isChecking: Bool {
        updateChecker.isChecking
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "server.rack")
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Main_About_Database_Version", comment: ""))
                        .font(.system(size: 15))
                        .foregroundColor(.primary)

                    if hasUpdate {
                        Text(NSLocalizedString("Main_About_Database_Update_Available", comment: ""))
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                    }
                }

                if let info = versionInfo {
                    Text("\(NSLocalizedString("Main_About_Build_Number", comment: "")): \(info.fullVersion)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)

                    if info.isPatchVersion, let patchNumber = info.patchNumber {
                        Text("\(NSLocalizedString("Main_About_Patch_Number", comment: "")): \(patchNumber)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(NSLocalizedString("Unknown", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            if isChecking {
                ProgressView()
                    .scaleEffect(0.8)
            } else if hasUpdate {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else if updateChecker.updateStatus == .noUpdate {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if hasUpdate {
                // 有更新：打开更新 sheet
                showingUpdateSheet = true
            } else if !isChecking {
                // 已是最新或其他状态：强制重新检查更新
                Task.detached(priority: .background) {
                    await updateChecker.forceCheckForUpdates()
                }
            }
        }
        .onAppear {
            // 在组件出现时检查更新
            Task.detached(priority: .background) {
                await updateChecker.checkForUpdates()
            }
        }
    }
}

struct AboutItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let url: URL?
    let characterId: Int?

    init(
        title: String,
        value: String,
        icon: String,
        url: URL? = nil,
        characterId: Int? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.url = url
        self.characterId = characterId
    }
}

struct AboutItemRow: View {
    let item: AboutItem
    @State private var portrait: UIImage?
    @State private var isLoadingPortrait = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15))
                Text(item.value)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.value
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
            }

            if item.characterId != nil {
                Spacer()
                if let portrait = portrait {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 42, height: 42)
                        .overlay {
                            if isLoadingPortrait {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                }
            }
        }
        .padding(.vertical, 6)
        .task {
            if let characterId = item.characterId {
                do {
                    portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                        characterId: characterId)
                } catch {
                    Logger.error("加载角色头像失败: \(error)")
                }
                isLoadingPortrait = false
            }
        }
    }
}
