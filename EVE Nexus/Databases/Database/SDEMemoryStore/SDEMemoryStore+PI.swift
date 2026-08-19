import Foundation

/// 行星工业（planetSchematics / planetResourceHarvest）加载
extension SDEMemoryStore {
    /// PI 配方（planetSchematics，68 行）
    static func loadPlanetSchematics(_ db: DatabaseManager) {
        let query = """
            SELECT schematic_id, output_typeid, cycle_time, output_value,
                   input_typeid, input_value, \(nameColumns)
            FROM planetSchematics
        """
        var byID: [Int: PlanetSchematic] = [:]
        var byOutput: [Int: PlanetSchematic] = [:]
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["schematic_id"] as? Int,
                      let outputTypeID = row["output_typeid"] as? Int
                else { continue }

                let schematic = PlanetSchematic(
                    id: id,
                    outputTypeID: outputTypeID,
                    names: LocalizedText.from(row: row),
                    cycleTime: row["cycle_time"] as? Int ?? 0,
                    outputValue: row["output_value"] as? Int ?? 0,
                    rawInputTypeIDs: (row["input_typeid"] as? String) ?? "",
                    rawInputValues: (row["input_value"] as? String) ?? ""
                )
                byID[id] = schematic
                byOutput[outputTypeID] = schematic
            }
        }
        planetSchematicsByID = byID
        planetSchematicByOutput = byOutput
    }

    /// 行星资源采集（planetResourceHarvest，40 行）
    static func loadPlanetResourceHarvest(_ db: DatabaseManager) {
        var cache: [Int: [Int]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT typeid, harvest_typeid FROM planetResourceHarvest", useCache: false
        ) {
            for row in rows {
                guard let typeID = row["typeid"] as? Int,
                      let harvestTypeID = row["harvest_typeid"] as? Int
                else { continue }
                cache[typeID, default: []].append(harvestTypeID)
            }
        }
        planetResourceHarvests = cache
    }
}
