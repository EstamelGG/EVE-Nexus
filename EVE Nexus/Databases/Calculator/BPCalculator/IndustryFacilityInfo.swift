import Foundation

// 建筑信息模型
struct IndustryFacilityInfo: Identifiable, Hashable {
    let id: Int
    let typeId: Int
    let name: String
    let iconFileName: String
    let customName: String?
    let isDefault: Bool
    let rigs: [Int]
    let rigInfos: [(id: Int, name: String, iconFileName: String)]
    let systemId: Int?  // 新增：星系ID
    
    // 显示名称逻辑
    var displayName: String {
        if let customName = customName, !customName.isEmpty {
            return "\(customName) - \(name)"
        } else if isDefault {
            return "\(NSLocalizedString("Structure_Selector_Default_Structure", comment: "默认建筑")) - \(name)"
        } else {
            return "\(NSLocalizedString("Structure_Selector_Unnamed_Structure", comment: "未命名建筑")) - \(name)"
        }
    }
    
    init(id: Int, typeId: Int, name: String, iconFileName: String, customName: String? = nil, isDefault: Bool = false, rigs: [Int] = [], rigInfos: [(id: Int, name: String, iconFileName: String)] = [], systemId: Int? = nil) {
        self.id = id
        self.typeId = typeId
        self.name = name
        self.iconFileName = iconFileName
        self.customName = customName
        self.isDefault = isDefault
        self.rigs = rigs
        self.rigInfos = rigInfos
        self.systemId = systemId
    }
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: IndustryFacilityInfo, rhs: IndustryFacilityInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

// 默认建筑配置模型
struct DefaultStructureConfig: Codable {
    let id: Int
    let is_default: Int
    let structure_typeid: Int
    let rigs: [Int]
    let name: String
    let system_id: Int?  // 新增：星系ID
} 
