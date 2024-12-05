import Foundation

// 分类模型
struct Category: Identifiable {
    let id: Int
    let name: String
    let published: Bool
    let iconID: Int
    let iconFileNew: String
}

// 组模型
struct Group: Identifiable {
    let id: Int
    let name: String
    let iconID: Int
    let categoryID: Int
    let published: Bool
    let icon_filename: String
}

// 物品模型
struct DatabaseItem: Identifiable {
    let id: Int
    let typeID: Int
    let name: String
    let iconFileName: String
    let pgNeed: Int
    let cpuNeed: Int
    let metaGroupID: Int
    let published: Bool
}

// 物品详情模型
struct ItemDetails {
    let name: String
    let description: String
    let iconFileName: String
    let groupName: String
    let categoryName: String
} 