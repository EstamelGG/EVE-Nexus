import Foundation

struct PlanetaryFacility {
    // 基础属性
    let identifier: Int64
    private(set) var name: String

    // 缓存字典，用于存储identifier和pinName的映射关系
    private static var nameCache: [Int64: String] = [:]

    init(identifier: Int64) {
        self.identifier = identifier
        name = Self.generatePinName(from: identifier)
    }

    /// 生成设施名称
    /// 算法参考自 libdgmpp 的实现
    /// - Parameter identifier: 设施ID
    /// - Returns: 生成的设施名称
    private static func generatePinName(from identifier: Int64) -> String {
        // 如果缓存中存在，直接返回
        if let cachedName = nameCache[identifier] {
            return cachedName
        }

        // 基础字符集
        let baseString = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let len = Int64(baseString.count - 1)  // 注意这里减1，与原始代码保持一致
        var pinName = ""

        // 生成5位字符的名称，中间带连字符
        for i in 0..<5 {
            // 计算当前位置的字符索引
            let at = Int((identifier / Int64(pow(Double(len), Double(i)))) % len)

            // 在第三个字符前添加连字符
            if i == 2 {
                pinName += "-"
            }

            // 从字符集中获取对应字符并添加到结果中
            let index = baseString.index(baseString.startIndex, offsetBy: at)
            pinName += String(baseString[index])
        }

        // 将结果存入缓存
        nameCache[identifier] = pinName
        Logger.debug("\(identifier):\(pinName)")
        return pinName
    }
}
