import Foundation

/// 配方信息结构体
struct SchematicInfo {
    let outputTypeId: Int
    let cycleTime: Int
    let outputValue: Int
    let inputs: [(typeId: Int, value: Int)]
}
