import Foundation

// 属性显示规则配置
struct AttributeDisplayConfig {
    // 默认配置
//    private static let defaultGroupOrder: [String: Int] = [ //展示属性组的顺序
//        "Offensive": 1,
//        "Defensive": 2,
//        "Module": 3,
//        "Structure": 4,
//        "Fitting": 5
//    ]
  
    private static let defaultGroupOrder: [String: Int] = [:]
    
    private static let defaultHiddenGroups: Set<String> = []
    
    private static let defaultHiddenAttributes: Set<Int> = []
    
    // 自定义配置 - 可以根据需要设置，不设置则使用默认值
    static var customGroupOrder: [String: Int]?
    static var customHiddenGroups: Set<String>?
    static var customHiddenAttributes: Set<Int>?
    
    // 获取实际使用的配置
    static var activeGroupOrder: [String: Int] {
        customGroupOrder ?? defaultGroupOrder
    }
    
    static var activeHiddenGroups: Set<String> {
        customHiddenGroups ?? defaultHiddenGroups
    }
    
    static var activeHiddenAttributes: Set<Int> {
        customHiddenAttributes ?? defaultHiddenAttributes
    }
    
    // 判断属性组是否应该显示
    static func shouldShowGroup(_ groupName: String) -> Bool {
        !activeHiddenGroups.contains(groupName)
    }
    
    // 判断具体属性是否应该显示
    static func shouldShowAttribute(_ attributeID: Int) -> Bool {
        !activeHiddenAttributes.contains(attributeID)
    }
    
    // 获取属性组的排序权重
    static func getGroupOrder(_ groupName: String) -> Int {
        activeGroupOrder[groupName] ?? 999 // 未定义顺序的组放到最后
    }
    
    // 重置所有配置到默认值
    static func resetToDefaults() {
        customGroupOrder = nil
        customHiddenGroups = nil
        customHiddenAttributes = nil
    }
    
    // 设置自定义配置的便捷方法
    static func setCustomGroupOrder(_ order: [String: Int]) {
        customGroupOrder = order
    }
    
    static func setHiddenGroups(_ groups: Set<String>) {
        customHiddenGroups = groups
    }
    
    static func setHiddenAttributes(_ attributes: Set<Int>) {
        customHiddenAttributes = attributes
    }
    
    // 添加单个配置项的便捷方法
    static func hideGroup(_ groupName: String) {
        var groups = customHiddenGroups ?? defaultHiddenGroups
        groups.insert(groupName)
        customHiddenGroups = groups
    }
    
    static func showGroup(_ groupName: String) {
        var groups = customHiddenGroups ?? defaultHiddenGroups
        groups.remove(groupName)
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
