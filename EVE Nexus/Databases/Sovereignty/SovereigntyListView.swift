import SwiftUI

/// 主权势力列表（第一级：全部主权势力，按星系数量降序）
struct SovereigntyListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var sovereignties: [SovereigntyInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @StateObject private var iconLoader = AllianceIconLoader()

    /// 数据加载状态管理，避免重复加载
    @State private var hasLoadedInitialData = false

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Loading_Sovereignty", comment: "加载主权信息中..."))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                SovereigntySearchScope {
                    List {
                        ForEach(sovereignties, id: \.id) { sovereignty in
                            NavigationLink(
                                destination: SovereigntyRegionsView(
                                    databaseManager: databaseManager,
                                    sovereigntyInfo: sovereignty
                                )
                            ) {
                                sovereigntyRow(sovereignty)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Sovereignty_List", comment: "主权势力列表"))
        .refreshable {
            await refreshSovereigntyData()
        }
        .onAppear {
            // 只在第一次加载时执行数据加载，避免从详情页返回时重新加载
            if !hasLoadedInitialData {
                Task {
                    await loadSovereigntyData(forceRefresh: false)
                }
                hasLoadedInitialData = true
            }
        }
        .onDisappear {
            iconLoader.cancelAllTasks()
        }
        .alert(
            NSLocalizedString("Load_Error", comment: "加载错误"), isPresented: $showError,
            actions: {
                Button(NSLocalizedString("OK", comment: "确定"), role: .cancel) {
                    showError = false
                }
            },
            message: {
                if let errorMsg = errorMessage {
                    Text(errorMsg)
                } else {
                    Text(NSLocalizedString("Unknown_Error", comment: "未知错误"))
                }
            }
        )
    }

    /// 加载主权数据（数据源为主权搜索引擎，全 app 唯一管道）
    private func loadSovereigntyData(forceRefresh: Bool) async {
        if !forceRefresh {
            isLoading = true
        }

        do {
            let list = try await SovereigntySearchEngine.shared.loadAll(
                forceRefresh: forceRefresh
            )

            sovereignties = list
            isLoading = false

            // 加载联盟图标
            iconLoader.loadIcons(for: list.filter(\.isAlliance).map(\.id))
        } catch {
            Logger.error("加载主权数据失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }

    /// 刷新主权数据
    private func refreshSovereigntyData() async {
        iconLoader.cancelAllTasks()
        await loadSovereigntyData(forceRefresh: true)
    }

    /// 主权势力行视图
    private func sovereigntyRow(_ sovereignty: SovereigntyInfo) -> some View {
        HStack {
            if let icon = iconLoader.icons[sovereignty.id] ?? sovereignty.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                ProgressView()
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading) {
                Text(sovereignty.name)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = sovereignty.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                Text(
                    "\(sovereignty.systemCount) \(NSLocalizedString("Sovereignty_Systems", comment: "个星系"))"
                )
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()
        }
    }
}
