import Foundation

/// 行星工业图纸
struct PlanetarySchematic {
    /// 图纸ID
    let id: Int64
    /// 产出物品类型ID
    let outputTypeId: Int64
    /// 图纸名称
    let name: String
    /// 支持的设施类型ID列表
    let facilities: [Int64]
    /// 生产周期（秒）
    let cycleTime: Int64
    /// 产出数量
    let outputValue: Int64
    /// 输入材料列表 [(材料类型ID, 数量)]
    let inputs: [(typeId: Int64, value: Int64)]
    
    /// 从数据库获取图纸信息
    /// - Parameter schematicId: 图纸ID
    /// - Returns: 图纸信息，如果不存在则返回nil
    static func fetch(schematicId: Int64) -> PlanetarySchematic? {
        let query = """
            SELECT schematic_id, output_typeid, name, facilitys, 
                   cycle_time, output_value, input_typeid, input_value
            FROM planetSchematics 
            WHERE schematic_id = \(schematicId)
        """
        
        if case .success(let rows) = DatabaseManager.shared.executeQuery(query),
           let row = rows.first,
           let id = row["schematic_id"] as? Int64,
           let outputTypeId = row["output_typeid"] as? Int64,
           let name = row["name"] as? String,
           let facilitysStr = row["facilitys"] as? String,
           let cycleTime = row["cycle_time"] as? Int64,
           let outputValue = row["output_value"] as? Int64,
           let inputTypeIds = row["input_typeid"] as? String,
           let inputValues = row["input_value"] as? String {
            
            // 解析支持的设施类型
            let facilities = facilitysStr.split(separator: ",").compactMap { Int64($0) }
            
            // 解析输入材料
            let inputTypeIdArray = inputTypeIds.split(separator: ",").compactMap { Int64($0) }
            let inputValueArray = inputValues.split(separator: ",").compactMap { Int64($0) }
            let inputs = zip(inputTypeIdArray, inputValueArray).map { (typeId: $0, value: $1) }
            
            return PlanetarySchematic(
                id: id,
                outputTypeId: outputTypeId,
                name: name,
                facilities: facilities,
                cycleTime: cycleTime,
                outputValue: outputValue,
                inputs: inputs
            )
        }
        
        return nil
    }
    
    /// 检查设施是否支持此图纸
    /// - Parameter facilityTypeId: 设施类型ID
    /// - Returns: 是否支持
    func isSupported(by facilityTypeId: Int64) -> Bool {
        return facilities.contains(facilityTypeId)
    }
} 