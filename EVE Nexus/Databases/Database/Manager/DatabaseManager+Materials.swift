import Foundation
import SwiftUI

extension DatabaseManager {
    func getTypeMaterials(for typeID: Int) -> [TypeMaterial]? {
        let query = """
            SELECT process_size, output_material, output_quantity, output_material_name, output_material_icon
            FROM typeMaterials
            WHERE typeid = ?
            ORDER BY output_material
        """

        let result = executeQuery(query, parameters: [typeID])
        var materials: [TypeMaterial] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let process_size = row["process_size"] as? Int,
                      let outputMaterial = row["output_material"] as? Int,
                      let outputQuantity = row["output_quantity"] as? Int,
                      let outputMaterialName = row["output_material_name"] as? String,
                      let outputMaterialIcon = row["output_material_icon"] as? String
                else {
                    continue
                }

                let material = TypeMaterial(
                    process_size: process_size,
                    outputMaterial: outputMaterial,
                    outputQuantity: outputQuantity,
                    outputMaterialName: outputMaterialName,
                    outputMaterialIcon: outputMaterialIcon.isEmpty
                        ? IconManager.defaultItemIcon : outputMaterialIcon
                )
                materials.append(material)
            }

            return materials.isEmpty ? nil : materials

        case let .error(error):
            Logger.error("Error fetching type materials: \(error)")
            return nil
        }
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
