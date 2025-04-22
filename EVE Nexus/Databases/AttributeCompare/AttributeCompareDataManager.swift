import Foundation

// 属性对比功能实用工具
enum AttributeCompareUtil {
    // 所有用于JSON序列化的结构都必须遵循Codable
    struct AttributeValueInfo: Codable {
        let value: Double
        let unitID: Int?
    }

    // 完整的对比结果结构，全部基于Codable
    struct CompareResult: Codable {
        // 属性对比数据 - 格式: [attributeID: [typeID: {value, unitID}]]
        let compareResult: [String: [String: AttributeValueInfo]]

        // 物品名称信息 - 格式: [typeID: name]
        let typeInfo: [String: String]

        // 已发布属性名称信息 - 格式: [attributeID: display_name]
        let publishedAttributeInfo: [String: String]

//         // 未发布属性名称信息 - 格式: [attributeID: name]
//         let unpublishedAttributeInfo: [String: String]

        // 属性图标信息 - 格式: [attributeID: iconFileName]
        let attributeIcons: [String: String]

        // 编码键名映射
        enum CodingKeys: String, CodingKey {
            case compareResult = "compare_result"
            case typeInfo = "type_info"
            case publishedAttributeInfo = "published_attribute_info"
            // case unpublishedAttributeInfo = "unpublished_attribute_info"
            case attributeIcons = "attribute_icons"
        }
    }
}
