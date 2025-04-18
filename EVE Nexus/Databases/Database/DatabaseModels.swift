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

    public init(
        id: Int, name: String, iconID: Int, categoryID: Int, published: Bool, icon_filename: String
    ) {
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

    public init(
        id: Int, typeID: Int, name: String, iconFileName: String, categoryID: Int, pgNeed: Int?,
        cpuNeed: Int?, rigCost: Int?, emDamage: Double?, themDamage: Double?, kinDamage: Double?,
        expDamage: Double?, highSlot: Int?, midSlot: Int?, lowSlot: Int?, rigSlot: Int?,
        gunSlot: Int?, missSlot: Int?, metaGroupID: Int, published: Bool
    ) {
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
    public let repackagedVolume: Double?
    public let capacity: Double?
    public let mass: Double?
    public let marketGroupID: Int?

    public init(
        name: String, description: String, iconFileName: String, groupName: String,
        categoryID: Int? = nil,
        categoryName: String, roleBonuses: [Trait]? = [], typeBonuses: [Trait]? = [],
        typeId: Int, groupID: Int?, volume: Double? = nil, repackagedVolume: Double? = nil,
        capacity: Double? = nil,
        mass: Double? = nil,
        marketGroupID: Int? = nil
    ) {
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
        self.repackagedVolume = repackagedVolume
        self.capacity = capacity
        self.mass = mass
        self.marketGroupID = marketGroupID
    }
}

// 属性分类模型
struct DogmaAttributeCategory: Identifiable {
    let id: Int  // attribute_category_id
    let name: String  // name
    let description: String  // description
}

// 属性模型
struct DogmaAttribute: Identifiable {
    let id: Int
    let categoryID: Int
    let name: String
    let displayName: String?
    let iconID: Int
    let iconFileName: String
    let value: Double
    let unitID: Int?

    // 修改显示名称逻辑
    var displayTitle: String {
        return displayName ?? name  // 如果displayName为nil，则使用name
    }

    // 修改显示逻辑
    var shouldDisplay: Bool {
        return true  // 始终显示，因为现在总是有可用的显示名称
    }
}

// 属性分组模型
struct AttributeGroup: Identifiable {
    let id: Int  // category id
    let name: String  // category name
    let attributes: [DogmaAttribute]
}
