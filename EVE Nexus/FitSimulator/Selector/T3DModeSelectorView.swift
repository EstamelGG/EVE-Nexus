import SwiftUI

// T3D模式选择器视图
struct T3DModeSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var modeInfos: [ModeInfo] = []
    @State private var hasSelectedItem: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    // 添加选择槽位的信息和回调
    let slotFlag: FittingFlag
    let onModuleSelected: ((Int) -> Void)?
    // 添加飞船ID
    let shipTypeID: Int
    
    // 初始化方法
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
        self._modeInfos = State(initialValue: [])
    }
    
    var body: some View {
        NavigationStack {
            if modeInfos.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle")
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
                                .frame(width: 30, height: 30)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .onAppear {
            loadModeOptions()
        }
    }
    
    // 加载战术驱逐舰模式选项
    private func loadModeOptions() {
        Logger.info("加载T3D模式选项，飞船ID: \(shipTypeID)")
        
        let query = """
            SELECT t.type_id, t.name, t.en_name, t.icon_filename, g.name as groupName
            FROM types t
            JOIN types s ON s.type_id = ?
            JOIN groups g ON t.groupID = g.group_id
            WHERE t.groupID = 1306
              AND t.en_name LIKE '%' || s.en_name || '%'
            ORDER BY t.name
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [shipTypeID]) {
            modeInfos = rows.compactMap { row in
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFileName = row["icon_filename"] as? String,
                      let groupName = row["groupName"] as? String else {
                    return nil
                }
                
                return ModeInfo(
                    typeId: typeId,
                    name: name,
                    iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName,
                    groupName: groupName
                )
            }
            
            Logger.info("加载了 \(modeInfos.count) 个T3D模式选项")
        } else {
            Logger.error("加载T3D模式选项失败")
        }
    }
}

// T3D模式信息结构体
private struct ModeInfo: Identifiable {
    let id: UUID = UUID()
    let typeId: Int
    let name: String
    let iconFileName: String
    let groupName: String
} 
