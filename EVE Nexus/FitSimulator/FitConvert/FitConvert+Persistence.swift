import Foundation

extension FitConvert {
    /// 将在线配置JSON数据解析为本地配置模型
    static func online2local(jsonData: Data) throws -> [LocalFitting] {
        let decoder = JSONDecoder()
        let onlineFittings = try decoder.decode([OnlineFitting].self, from: jsonData)
        return onlineFittings.map { online in
            // 从items中提取无人机、货舱和舰载机信息
            let drones = online.items
                .filter { $0.flag == .droneBay }
                .map { Drone(type_id: $0.type_id, quantity: $0.quantity, active_count: 0, muta: nil) }

            let cargo = online.items
                .filter { $0.flag == .cargo }
                .map { CargoItem(type_id: $0.type_id, quantity: $0.quantity) }

            // 获取数据库管理器
            let databaseManager = DatabaseManager.shared

            // 从舰载机舱中筛选出舰载机
            let fighterBayItems = online.items.filter { $0.flag == .fighterBay }

            // 处理舰载机配置
            if AppConfiguration.Fitting.showDebug {
                Logger.info("准备处理舰载机配置，找到 \(fighterBayItems.count) 个舰载机物品")
            }
            let fighters = processFighters(
                shipTypeId: online.ship_type_id,
                fighterBayItems: fighterBayItems,
                databaseManager: databaseManager
            )
            if AppConfiguration.Fitting.showDebug {
                Logger.info("舰载机处理完成，生成了 \(fighters.count) 个FighterSquad")
            }

            // 过滤掉无人机、货舱和舰载机，只保留装备
            var equipmentItems = online.items.filter {
                $0.flag != .droneBay && $0.flag != .cargo && $0.flag != .fighterBay
            }

            // 检查是否为模式切换飞船，如果是则添加默认模式
            let shipTypeId = online.ship_type_id

            // 使用新的工具函数检查飞船是否支持模式切换
            if ModeSwitchingUtils.isModeSwitchingShip(
                shipTypeId: shipTypeId,
                databaseManager: databaseManager
            ) {
                // 获取默认模式ID
                if let defaultModeId = ModeSwitchingUtils.getDefaultModeId(
                    for: shipTypeId,
                    databaseManager: databaseManager
                ) {
                    // 将模式作为模块添加到装备列表中
                    let modeItem = FittingItem(
                        flag: .t3dModeSlot0,
                        quantity: 1,
                        type_id: defaultModeId
                    )

                    // 添加模式到装备列表
                    equipmentItems.append(modeItem)
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("在线配置导入: 为模式切换飞船(ID: \(shipTypeId))添加默认模式模块: \(defaultModeId)")
                    }
                }
            }

            return LocalFitting(
                description: online.description,
                fitting_id: online.fitting_id,
                items: equipmentItems.map { item in
                    // 在线配置中没有弹药、突变和预热信息
                    LocalFittingItem(
                        flag: item.flag,
                        quantity: item.quantity,
                        type_id: item.type_id,
                        status: 1
                    )
                },
                name: online.name,
                ship_type_id: online.ship_type_id,
                drones: drones.isEmpty ? nil : drones, // 如果没有无人机则为nil
                fighters: fighters.isEmpty ? nil : fighters, // 如果没有舰载机则为nil
                cargo: cargo.isEmpty ? nil : cargo // 如果没有货舱物品则为nil
                // 在线配置中没有植入体和环境信息
            )
        }
    }

    /// 将本地配置保存为JSON文件
    static func saveLocalFitting(_ fitting: LocalFitting) throws {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建Fitting目录
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        if !FileManager.default.fileExists(atPath: fittingsDirectory.path) {
            try FileManager.default.createDirectory(
                at: fittingsDirectory, withIntermediateDirectories: true
            )
        }

        // 创建文件路径
        let filePath = fittingsDirectory.appendingPathComponent(
            "local_fitting_\(fitting.fitting_id).json"
        )

        // 将配置转换为JSON数据
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // 美化输出格式
        let jsonData = try encoder.encode(fitting)

        // 写入文件
        try jsonData.write(to: filePath)

        Logger.info("配置已保存到: \(filePath.path)")
    }

    /// 从JSON文件加载本地配置
    static func loadLocalFitting(fittingId: Int) throws -> LocalFitting {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建文件路径
        let filePath = documentsDirectory.appendingPathComponent(
            "Fitting/local_fitting_\(fittingId).json"
        )

        // 读取文件数据
        let jsonData = try Data(contentsOf: filePath)

        // 解码JSON数据
        let decoder = JSONDecoder()
        return try decoder.decode(LocalFitting.self, from: jsonData)
    }

    /// 从JSON文件加载所有本地配置
    static func loadAllLocalFittings() throws -> [LocalFitting] {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建Fitting目录路径
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")

        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: fittingsDirectory.path) else {
            return []
        }

        // 获取目录中的所有文件
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: fittingsDirectory, includingPropertiesForKeys: nil
        )

        // 过滤出配置文件并加载
        var fittings: [LocalFitting] = []
        for fileURL in fileURLs
            where fileURL.lastPathComponent.hasPrefix("local_fitting_")
            && fileURL.pathExtension == "json"
        {
            do {
                let jsonData = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                let fitting = try decoder.decode(LocalFitting.self, from: jsonData)
                fittings.append(fitting)
            } catch {
                Logger.error("加载配置文件失败 \(fileURL.lastPathComponent): \(error)")
                continue
            }
        }

        return fittings
    }
}
