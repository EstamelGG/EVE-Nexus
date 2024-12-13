import Foundation

// 分类模型
public struct Category: Identifiable {
    public let id: Int
    public let name: String
    public let published: Bool
    public let iconID: Int
    public let iconFileNew: String
    
    public init(id: Int, name: String, published: Bool, iconID: Int, iconFileNew: String) {
        self.id = id
        self.name = name
        self.published = published
        self.iconID = iconID
        self.iconFileNew = iconFileNew
    }
}

// 组模型
public struct Group: Identifiable {
    public let id: Int
    public let name: String
    public let iconID: Int
    public let categoryID: Int
    public let published: Bool
    public let icon_filename: String
    
    public init(id: Int, name: String, iconID: Int, categoryID: Int, published: Bool, icon_filename: String) {
        self.id = id
        self.name = name
        self.iconID = iconID
        self.categoryID = categoryID
        self.published = published
        self.icon_filename = icon_filename
    }
}

// 物品模型
public struct DatabaseItem: Identifiable {
    public let id: Int
    public let typeID: Int
    public let name: String
    public let iconFileName: String
    public let categoryID: Int
    public let pgNeed: Int?
    public let cpuNeed: Int?
    public let rigCost: Int?
    public let emDamage: Double?
    public let themDamage: Double?
    public let kinDamage: Double?
    public let expDamage: Double?
    public let highSlot: Int?
    public let midSlot: Int?
    public let lowSlot: Int?
    public let rigSlot: Int?
    public let gunSlot: Int?
    public let missSlot: Int?
    public let metaGroupID: Int
    public let published: Bool
    
    public init(id: Int, typeID: Int, name: String, iconFileName: String, categoryID: Int, pgNeed: Int?, cpuNeed: Int?, rigCost: Int?, emDamage: Double?, themDamage: Double?, kinDamage: Double?, expDamage: Double?, highSlot: Int?, midSlot: Int?, lowSlot: Int?, rigSlot: Int?, gunSlot: Int?, missSlot: Int?, metaGroupID: Int, published: Bool) {
        self.id = id
        self.typeID = typeID
        self.name = name
        self.iconFileName = iconFileName
        self.categoryID = categoryID
        self.pgNeed = pgNeed
        self.cpuNeed = cpuNeed
        self.rigCost = rigCost
        self.emDamage = emDamage
        self.themDamage = themDamage
        self.kinDamage = kinDamage
        self.expDamage = expDamage
        self.highSlot = highSlot
        self.midSlot = midSlot
        self.lowSlot = lowSlot
        self.rigSlot = rigSlot
        self.gunSlot = gunSlot
        self.missSlot = missSlot
        self.metaGroupID = metaGroupID
        self.published = published
    }
}

// Trait 相关模型
public struct Trait {
    public let content: String
    public let importance: Int
    public let skill: Int?
    public let bonusType: String
    
    public init(content: String, importance: Int, skill: Int? = nil, bonusType: String = "") {
        self.content = content
        self.importance = importance
        self.skill = skill
        self.bonusType = bonusType
    }
}

public struct TraitGroup {
    public let roleBonuses: [Trait]
    public let typeBonuses: [Trait]
    
    public init(roleBonuses: [Trait], typeBonuses: [Trait]) {
        self.roleBonuses = roleBonuses
        self.typeBonuses = typeBonuses
    }
}

// 物品详情模型
public struct ItemDetails {
    public let name: String
    public let description: String
    public let iconFileName: String
    public let groupName: String
    public let categoryName: String
    public let categoryID: Int?
    public let roleBonuses: [Trait]?
    public let typeBonuses: [Trait]?
    public let typeId: Int
    public let groupID: Int?
    public let volume: Double?
    public let capacity: Double?
    public let mass: Double?
    
    public init(name: String, description: String, iconFileName: String, groupName: String, categoryID: Int? = nil,
               categoryName: String, roleBonuses: [Trait]? = [], typeBonuses: [Trait]? = [],
               typeId: Int, groupID: Int?, volume: Double? = nil, capacity: Double? = nil, mass: Double? = nil) {
        self.name = name
        self.description = description
        self.iconFileName = iconFileName
        self.groupName = groupName
        self.categoryName = categoryName
        self.categoryID = categoryID
        self.roleBonuses = roleBonuses
        self.typeBonuses = typeBonuses
        self.typeId = typeId
        self.groupID = groupID
        self.volume = volume
        self.capacity = capacity
        self.mass = mass
    }
}

// 属性分类模型
struct DogmaAttributeCategory: Identifiable {
    let id: Int              // attribute_category_id
    let name: String         // name
    let description: String  // description
}

// 属性模型
struct DogmaAttribute: Identifiable {
    let id: Int              // attribute_id
    let categoryID: Int      // categoryID
    let name: String         // name
    let displayName: String? // display_name
    let iconID: Int         // iconID
    let iconFileName: String // icon_filename
    let value: Double       // value from typeAttributes
    let unitID: Int?       // unitID from dogmaAttributes
    
    // 显示名称
    var displayTitle: String {
        return displayName?.isEmpty == false ? displayName! : name
    }
    
    // 是否应该显示
    var shouldDisplay: Bool {
        // 如果 displayName 为空或为空字符串，不显示
        guard let displayName = displayName, !displayName.isEmpty else {
            return false
        }
        return true
    }
}

// 属性分组模型
struct AttributeGroup: Identifiable {
    let id: Int              // category id
    let name: String         // category name
    let attributes: [DogmaAttribute]
} 
