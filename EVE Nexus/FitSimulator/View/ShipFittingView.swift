import SwiftUI

// 定义配置视图类型枚举
enum FittingViewType: String, CaseIterable, Identifiable {
    case modules
    case drones
    case fighters
    case cargo
    case stats
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .modules:
            return NSLocalizedString("Fitting_modules", comment: "Modules")
        case .drones:
            return NSLocalizedString("Fitting_drones", comment: "Drones")
        case .fighters:
            return NSLocalizedString("Fitting_fighters", comment: "Fighters")
        case .cargo:
            return NSLocalizedString("Fitting_cargo", comment: "Cargo")
        case .stats:
            return NSLocalizedString("Fitting_stats", comment: "Stats")
        }
    }
}

struct ShipFittingView: View {
    @StateObject var viewModel: FittingEditorViewModel
    @State private var showingSettings = false
    @State private var selectedViewType: FittingViewType = .modules
    
    // 构造函数1：新建配置
    init(shipTypeId: Int, shipInfo: (name: String, iconFileName: String), databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: FittingEditorViewModel(
            shipTypeId: shipTypeId,
            shipInfo: shipInfo,
            databaseManager: databaseManager
        ))
    }
    
    // 构造函数2：打开本地配置
    init(fittingId: Int, databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: FittingEditorViewModel(
            fittingId: fittingId,
            databaseManager: databaseManager
        ))
    }
    
    // 构造函数3：打开在线配置
    init(onlineFitting: CharacterFitting, databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: FittingEditorViewModel(
            onlineFitting: onlineFitting,
            databaseManager: databaseManager
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 视图类型选择器
            Picker("ViewType", selection: $selectedViewType) {
                ForEach(getFittingViewTypes()) { viewType in
                    Text(viewType.localizedName).tag(viewType)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // 根据选择的视图类型显示不同内容
            switch selectedViewType {
            case .modules:
                ShipFittingModulesView(viewModel: viewModel)
            case .drones:
                ShipFittingDronesView(viewModel: viewModel)
            case .fighters:
                ShipFittingFightersView(viewModel: viewModel)
            case .cargo:
                ShipFittingCargoView(viewModel: viewModel)
            case .stats:
                ShipFittingStatsView(viewModel: viewModel)
            }
        }
        .navigationTitle(viewModel.shipInfo.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                FittingSettingsView(
                    databaseManager: viewModel.databaseManager,
                    shipTypeID: viewModel.simulationInput.ship.typeId,
                    fittingName: viewModel.simulationInput.name,
                    fittingData: ["name": viewModel.simulationInput.name, "ship_type_id": viewModel.simulationInput.ship.typeId, "fitting_id": viewModel.simulationInput.fittingId],
                    onNameChanged: { updatedData in
                        if let name = updatedData["name"] as? String {
                            // 更新名称
                            viewModel.updateName(name)
                            
                            // 立即保存配置到磁盘
                            viewModel.saveConfiguration()
                            
                            // 记录日志
                            Logger.info("配置名称更新并保存: \(name)")
                        }
                    },
                    onSkillModeChanged: {
                        // 从UserDefaults获取当前选择的技能模式
                        let skillsMode = UserDefaults.standard.string(forKey: "skillsModePreference") ?? "current_char"
                        
                        // 根据技能模式获取对应的技能类型
                        var skillType: CharacterSkillsType
                        
                        switch skillsMode {
                        case "all5":
                            skillType = .all5
                        case "all4":
                            skillType = .all4
                        case "all3":
                            skillType = .all3
                        case "all2":
                            skillType = .all2
                        case "all1":
                            skillType = .all1
                        case "all0":
                            skillType = .all0
                        case "character":
                            // 指定角色的情况，获取保存的角色ID
                            let charId = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")
                            skillType = .character(charId)
                        default:
                            // 默认为当前角色
                            skillType = .current_char
                        }
                        
                        // 获取技能数据
                        let skills = CharacterSkillsUtils.getCharacterSkills(type: skillType)
                        
                        // 更新视图模型中的技能数据
                        viewModel.updateCharacterSkills(skills: skills, sourceType: skillType)
                        
                        Logger.info("技能模式更改为\(skillsMode)，已重新计算属性")
                    },
                    viewModel: viewModel
                )
            }
        }
        .onAppear {
            // 计算初始属性
            // viewModel.calculateAttributes()
        }
        .onDisappear {
            // 在离开页面时清除装备选择器的缓存状态
            clearSelectorPreferences()
        }
    }
    
    /// 根据飞船属性获取应该显示的视图类型
    private func getFittingViewTypes() -> [FittingViewType] {
        var viewTypes = [FittingViewType]()
        
        // 始终添加的视图类型
        viewTypes.append(.modules)
        viewTypes.append(.drones)
        
        // 仅当飞船有战斗机舱时添加fighters选项
        if let fighterTubes = viewModel.simulationInput.ship.baseAttributesByName["fighterTubes"], fighterTubes > 0 {
            viewTypes.append(.fighters)
        }
        
        // 其他始终添加的视图类型
        viewTypes.append(.cargo)
        viewTypes.append(.stats)
        
        return viewTypes
    }
    
    /// 清除所有装备选择器的缓存状态
    private func clearSelectorPreferences() {
        // 清理高槽装备选择器状态
        UserDefaults.standard.removeObject(forKey: "LastVisitedHighSlotGroupID")
        UserDefaults.standard.removeObject(forKey: "LastHighSlotSearchKeyword")

        // 清理中槽装备选择器状态
        UserDefaults.standard.removeObject(forKey: "LastVisitedMidSlotGroupID")
        UserDefaults.standard.removeObject(forKey: "LastMidSlotSearchKeyword")

        // 清理低槽装备选择器状态
        UserDefaults.standard.removeObject(forKey: "LastVisitedLowSlotGroupID")
        UserDefaults.standard.removeObject(forKey: "LastLowSlotSearchKeyword")

        // 清理所有包含飞船ID的选择器缓存
        let shipTypeId = viewModel.simulationInput.ship.typeId
        
        // 清理特定飞船的高槽缓存
        UserDefaults.standard.removeObject(forKey: "LastVisitedHighSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastHighSlotSearchKeyword_\(shipTypeId)")
        
        // 清理特定飞船的中槽缓存
        UserDefaults.standard.removeObject(forKey: "LastVisitedMidSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastMidSlotSearchKeyword_\(shipTypeId)")
        
        // 清理特定飞船的低槽缓存
        UserDefaults.standard.removeObject(forKey: "LastVisitedLowSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastLowSlotSearchKeyword_\(shipTypeId)")

        // 清理特定飞船的改装件缓存
        UserDefaults.standard.removeObject(forKey: "LastVisitedRigSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastRigSlotSearchKeyword_\(shipTypeId)")
        
        // 清理特定飞船的子系统缓存
        UserDefaults.standard.removeObject(forKey: "LastVisitedSubSysSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastSubSysSlotSearchKeyword_\(shipTypeId)")
        
        // 确保立即写入
        UserDefaults.standard.synchronize()
        Logger.info("已清理所有装备选择器状态，飞船ID：\(shipTypeId)")
    }
}

