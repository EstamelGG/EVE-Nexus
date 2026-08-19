import Foundation

/// 蓝图制造数据与 LP 商店数据加载（无独立 lookup，调用方直接读存储属性）
extension SDEMemoryStore {
    /// 蓝图制造数据（output/skills/materials/process_time + 插件效果，约 4.7 万行）
    static func loadBlueprintData(_ db: DatabaseManager) {
        var outputs: [Int: (typeID: Int, quantity: Int)] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT blueprintTypeID, typeID, quantity FROM blueprint_manufacturing_output", useCache: false
        ) {
            for row in rows {
                guard let bpID = row["blueprintTypeID"] as? Int,
                      let typeID = row["typeID"] as? Int,
                      let quantity = row["quantity"] as? Int
                else { continue }
                outputs[bpID] = (typeID, quantity)
            }
        }
        blueprintOutputs = outputs

        // 产品 → 蓝图反索引：制造来源复用 outputs，发明来源补一次全表读取，合并去重
        var blueprintsByProduct: [Int: [Int]] = [:]
        for (bpID, output) in outputs {
            blueprintsByProduct[output.typeID, default: []].append(bpID)
        }
        if case let .success(rows) = db.executeQuery(
            "SELECT blueprintTypeID, typeID FROM blueprint_invention_products", useCache: false
        ) {
            for row in rows {
                guard let bpID = row["blueprintTypeID"] as? Int,
                      let typeID = row["typeID"] as? Int
                else { continue }
                if !(blueprintsByProduct[typeID] ?? []).contains(bpID) {
                    blueprintsByProduct[typeID, default: []].append(bpID)
                }
            }
        }
        blueprintIDsByProduct = blueprintsByProduct

        var skills: [Int: [Int]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT blueprintTypeID, typeID FROM blueprint_manufacturing_skills", useCache: false
        ) {
            for row in rows {
                guard let bpID = row["blueprintTypeID"] as? Int,
                      let typeID = row["typeID"] as? Int
                else { continue }
                if !(skills[bpID] ?? []).contains(typeID) {
                    skills[bpID, default: []].append(typeID)
                }
            }
        }
        blueprintSkills = skills

        var materials: [Int: [(typeID: Int, quantity: Int)]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT blueprintTypeID, typeID, quantity FROM blueprint_manufacturing_materials", useCache: false
        ) {
            for row in rows {
                guard let bpID = row["blueprintTypeID"] as? Int,
                      let typeID = row["typeID"] as? Int,
                      let quantity = row["quantity"] as? Int
                else { continue }
                materials[bpID, default: []].append((typeID, quantity))
            }
        }
        blueprintMaterials = materials

        var times: [Int: Int] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT blueprintTypeID, manufacturing_time FROM blueprint_process_time", useCache: false
        ) {
            for row in rows {
                guard let bpID = row["blueprintTypeID"] as? Int,
                      let time = row["manufacturing_time"] as? Int
                else { continue }
                times[bpID] = time
            }
        }
        blueprintManufacturingTimes = times

        var rigs: [Int: [(category: Int, groupID: Int)]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT id, category, group_id FROM facility_rig_effects", useCache: false
        ) {
            for row in rows {
                guard let id = row["id"] as? Int,
                      let category = row["category"] as? Int,
                      let groupID = row["group_id"] as? Int
                else { continue }
                rigs[id, default: []].append((category, groupID))
            }
        }
        facilityRigEffects = rigs
    }

    /// LP 商店数据（offers/outputs/requirements，约 3.8 万行）
    static func loadLoyaltyOffers(_ db: DatabaseManager) {
        var byCorp: [Int: [Int]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT corporation_id, offer_id FROM loyalty_offers", useCache: false
        ) {
            for row in rows {
                guard let corpID = row["corporation_id"] as? Int,
                      let offerID = row["offer_id"] as? Int
                else { continue }
                byCorp[corpID, default: []].append(offerID)
            }
        }
        loyaltyOffersByCorporation = byCorp

        var outputs: [Int: LPOfferOutput] = [:]
        var outputsByType: [Int: [Int]] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT offer_id, type_id, quantity, isk_cost, lp_cost, ak_cost
            FROM loyalty_offer_outputs
            """,
            useCache: false
        ) {
            for row in rows {
                guard let offerID = row["offer_id"] as? Int,
                      let typeID = row["type_id"] as? Int,
                      let quantity = row["quantity"] as? Int,
                      let iskCost = row["isk_cost"] as? Int,
                      let lpCost = row["lp_cost"] as? Int,
                      let akCost = row["ak_cost"] as? Int
                else { continue }

                outputs[offerID] = LPOfferOutput(
                    offerID: offerID, typeID: typeID, quantity: quantity,
                    iskCost: iskCost, lpCost: lpCost, akCost: akCost
                )
                outputsByType[typeID, default: []].append(offerID)
            }
        }
        loyaltyOfferOutputs = outputs
        loyaltyOfferOutputsByType = outputsByType

        var requirements: [Int: [LPOfferRequirement]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT offer_id, required_type_id, required_quantity FROM loyalty_offer_requirements", useCache: false
        ) {
            for row in rows {
                guard let offerID = row["offer_id"] as? Int,
                      let typeID = row["required_type_id"] as? Int,
                      let quantity = row["required_quantity"] as? Int
                else { continue }
                requirements[offerID, default: []].append(LPOfferRequirement(typeID: typeID, quantity: quantity))
            }
        }
        loyaltyOfferRequirements = requirements
    }
}
