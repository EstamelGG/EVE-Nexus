import SwiftUI

/// T3D模式选择器视图
struct T3DModeSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var modeInfos: [ModeInfo] = []
    @State private var hasSelectedItem: Bool = false
    @Environment(\.dismiss) private var dismiss

    // 添加选择槽位的信息和回调
    let slotFlag: FittingFlag
    let onModuleSelected: ((Int) -> Void)?
    /// 添加飞船ID
    let shipTypeID: Int

    /// 初始化方法
    init(
        databaseManager: DatabaseManager,
        slotFlag: FittingFlag,
        onModuleSelected: ((Int) -> Void)? = nil,
        shipTypeID: Int = 0
    ) {
        self.databaseManager = databaseManager
        self.slotFlag = slotFlag
        self.onModuleSelected = onModuleSelected
        self.shipTypeID = shipTypeID

        // 预加载模式数据
        _modeInfos = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            if modeInfos.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                List {
                    ForEach(modeInfos) { modeInfo in
                        HStack {
                            // 显示模式图标
                            IconManager.shared.loadImage(for: modeInfo.iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(modeInfo.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 标记已选择模式
                            hasSelectedItem = true
                            Logger.info("用户选择了T3D模式: \(modeInfo.name), ID: \(modeInfo.typeId)")

                            // 调用回调函数安装模式
                            onModuleSelected?(modeInfo.typeId)

                            dismiss()
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Fitting_Mode_Selection", comment: "模式选择"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadModeOptions()
        }
    }

    /// 加载模式选项（支持所有模式切换飞船）
    private func loadModeOptions() {
        Logger.info("加载模式选项，飞船ID: \(shipTypeID)")

        // 使用新的工具函数获取模式选项
        let modes = ModeSwitchingUtils.getModeOptions(
            for: shipTypeID,
            databaseManager: databaseManager
        )

        modeInfos = modes.map { mode in
            ModeInfo(
                typeId: mode.typeId,
                name: mode.name,
                iconFileName: mode.iconFileName,
                groupName: "Mode" // 模式装备的组名
            )
        }

        Logger.info("加载了 \(modeInfos.count) 个模式选项")
    }
}

/// T3D模式信息结构体
private struct ModeInfo: Identifiable {
    let id: UUID = .init()
    let typeId: Int
    let name: String
    let iconFileName: String
    let groupName: String
}
