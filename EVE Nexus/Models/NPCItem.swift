import Foundation

public struct NPCItem {
    public let typeID: Int
    public let name: String
    public let enName: String  // 添加英文名称
    public let iconFileName: String

    public init(typeID: Int, name: String, enName: String, iconFileName: String) {
        self.typeID = typeID
        self.name = name
        self.enName = enName
        self.iconFileName = iconFileName
    }
}
