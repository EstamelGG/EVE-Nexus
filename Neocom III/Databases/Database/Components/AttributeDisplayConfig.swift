import Foundation

// 属性显示规则配置
struct AttributeDisplayConfig {
    // 默认配置
    private static let defaultGroupOrder: [Int: Int] = [:]  // [categoryId: order] 自定义展示分组的顺序
    private static let defaultHiddenGroups: Set<Int> = []   // 要隐藏的属性分组id
    private static let defaultHiddenAttributes: Set<Int> = [] // 要隐藏的属性id
    
    // 自定义配置 - 可以根据需要设置，不设置则使用默认值
    static var customGroupOrder: [Int: Int]?
    static var customHiddenGroups: Set<Int>?
    static var customHiddenAttributes: Set<Int>?
    
    // 获取实际使用的配置
    static var activeGroupOrder: [Int: Int] {
        customGroupOrder ?? defaultGroupOrder
    }
    
    static var activeHiddenGroups: Set<Int> {
        customHiddenGroups ?? defaultHiddenGroups
    }
    
    static var activeHiddenAttributes: Set<Int> {
        customHiddenAttributes ?? defaultHiddenAttributes
    }
    
    // 判断属性组是否应该显示
    static func shouldShowGroup(_ groupId: Int) -> Bool {
        !activeHiddenGroups.contains(groupId)
    }
    
    // 判断具体属性是否应该显示
    static func shouldShowAttribute(_ attributeID: Int) -> Bool {
        !activeHiddenAttributes.contains(attributeID)
    }
    
    // 获取属性组的排序权重
    static func getGroupOrder(_ groupId: Int) -> Int {
        activeGroupOrder[groupId] ?? 999 // 未定义顺序的组放到最后
    }
    
    // 重置所有配置到默认值
    static func resetToDefaults() {
        customGroupOrder = nil
        customHiddenGroups = nil
        customHiddenAttributes = nil
    }
    
    // 设置自定义配置的便捷方法
    static func setCustomGroupOrder(_ order: [Int: Int]) {
        customGroupOrder = order
    }
    
    static func setHiddenGroups(_ groups: Set<Int>) {
        customHiddenGroups = groups
    }
    
    static func setHiddenAttributes(_ attributes: Set<Int>) {
        customHiddenAttributes = attributes
    }
    
    // 添加单个配置项的便捷方法
    static func hideGroup(_ groupId: Int) {
        var groups = customHiddenGroups ?? defaultHiddenGroups
        groups.insert(groupId)
        customHiddenGroups = groups
    }
    
    static func showGroup(_ groupId: Int) {
        var groups = customHiddenGroups ?? defaultHiddenGroups
        groups.remove(groupId)
        customHiddenGroups = groups
    }
    
    static func hideAttribute(_ attributeID: Int) {
        var attributes = customHiddenAttributes ?? defaultHiddenAttributes
        attributes.insert(attributeID)
        customHiddenAttributes = attributes
    }
    
    static func showAttribute(_ attributeID: Int) {
        var attributes = customHiddenAttributes ?? defaultHiddenAttributes
        attributes.remove(attributeID)
        customHiddenAttributes = attributes
    }
} 
