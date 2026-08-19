import Foundation
import SwiftUI

extension DatabaseManager {
    func getTypeMaterials(for typeID: Int) -> [TypeMaterial]? {
        // 内存索引取核心列；名称/icon 从 types 解析（与旧表内宽列一致）
        let entries = SDEMemoryStore.materials(for: typeID)
        guard !entries.isEmpty else { return nil }

        let materials: [TypeMaterial] = entries.map { entry in
            let outputInfo = SDEMemoryStore.type(for: entry.outputMaterial)
            let iconName = outputInfo?.iconFilename ?? ""
            return TypeMaterial(
                process_size: entry.processSize,
                outputMaterial: entry.outputMaterial,
                outputQuantity: entry.outputQuantity,
                outputMaterialName: outputInfo?.name ?? "",
                outputMaterialIcon: iconName.isEmpty
                    ? IconManager.defaultItemIcon : iconName
            )
        }
        return materials
    }

    /// 随机产出材料数据结构
    struct TypeRandomizedMaterial {
        let materialTypeID: Int
        let materialName: String
        let materialIcon: String
        let quantityMin: Int
        let quantityMax: Int
    }

    func getTypeRandomizedMaterials(for typeID: Int) -> [TypeRandomizedMaterial]? {
        let query = """
            SELECT trm.materialTypeID, t.name as materialName, t.icon_filename as materialIcon,
                   trm.quantityMin, trm.quantityMax
            FROM typeRandomizedMaterials trm
            LEFT JOIN types t ON trm.materialTypeID = t.type_id
            WHERE trm.type_id = ?
            ORDER BY trm.materialTypeID
        """

        let result = executeQuery(query, parameters: [typeID])
        var materials: [TypeRandomizedMaterial] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let materialTypeID = row["materialTypeID"] as? Int,
                      let quantityMin = row["quantityMin"] as? Int,
                      let quantityMax = row["quantityMax"] as? Int,
                      let materialName = row["materialName"] as? String
                else {
                    continue
                }

                let materialIcon = (row["materialIcon"] as? String) ?? IconManager.defaultItemIcon

                let material = TypeRandomizedMaterial(
                    materialTypeID: materialTypeID,
                    materialName: materialName,
                    materialIcon: materialIcon.isEmpty ? IconManager.defaultItemIcon : materialIcon,
                    quantityMin: quantityMin,
                    quantityMax: quantityMax
                )
                materials.append(material)
            }

            return materials.isEmpty ? nil : materials

        case let .error(error):
            Logger.error("Error fetching type randomized materials: \(error)")
            return nil
        }
    }
}
