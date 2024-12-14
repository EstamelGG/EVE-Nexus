import Foundation

public struct NPCItem {
    public let typeID: Int
    public let name: String
    public let iconFileName: String
    
    public init(typeID: Int, name: String, iconFileName: String) {
        self.typeID = typeID
        self.name = name
        self.iconFileName = iconFileName
    }
} 