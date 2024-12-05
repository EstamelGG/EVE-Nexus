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
    public let pgNeed: Int
    public let cpuNeed: Int
    public let metaGroupID: Int
    public let published: Bool
    
    public init(id: Int, typeID: Int, name: String, iconFileName: String, pgNeed: Int, cpuNeed: Int, metaGroupID: Int, published: Bool) {
        self.id = id
        self.typeID = typeID
        self.name = name
        self.iconFileName = iconFileName
        self.pgNeed = pgNeed
        self.cpuNeed = cpuNeed
        self.metaGroupID = metaGroupID
        self.published = published
    }
}

// 物品详情模型
public struct ItemDetails {
    public let name: String
    public let description: String
    public let iconFileName: String
    public let groupName: String
    public let categoryName: String
    
    public init(name: String, description: String, iconFileName: String, groupName: String, categoryName: String) {
        self.name = name
        self.description = description
        self.iconFileName = iconFileName
        self.groupName = groupName
        self.categoryName = categoryName
    }
} 