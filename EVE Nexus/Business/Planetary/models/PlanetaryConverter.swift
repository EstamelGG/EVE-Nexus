import Foundation

/// 行星数据转换器
class PlanetaryConverter {
    
    /// 提取器状态
    struct ExtractorStatus {
        let isActive: Bool
        let expiryTime: Date?
        let productType: Type?
        let cycleTime: TimeInterval?
        let headCount: Int
        let qtyPerCycle: Int?
    }
    
    /// 工厂状态
    struct FactoryStatus {
        let isActive: Bool
        let schematic: Schematic?
        let hasReceivedInputs: Bool
        let receivedInputsLastCycle: Bool
        let lastCycleStartTime: Date?
    }
    
    /// 将PlanetaryDetail转换为Colony模型
    /// - Parameters:
    ///   - detail: 行星详情
    ///   - characterId: 角色ID
    ///   - planetId: 行星ID
    ///   - planetName: 行星名称
    ///   - planetType: 行星类型
    ///   - systemId: 恒星系ID
    ///   - systemName: 恒星系名称
    ///   - upgradeLevel: 升级等级
    ///   - lastUpdate: 最后更新时间（可选，默认为当前时间）
    /// - Returns: 殖民地模型
    static func convertToColony(
        detail: PlanetaryDetail,
        characterId: Int,
        planetId: Int,
        planetName: String,
        planetType: String,
        systemId: Int,
        systemName: String,
        upgradeLevel: Int,
        lastUpdate: String = Date().ISO8601Format()
    ) -> Colony {
        // 创建唯一ID
        let colonyId = "\(characterId)_\(planetId)"
        Logger.info("======= 创建殖民地ID: \(colonyId) ========")
        // 解析最后更新时间
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let updateDate = dateFormatter.date(from: lastUpdate) ?? Date()
        
        // 创建恒星系
        let system = SolarSystem(
            id: systemId,
            name: systemName
        )
        
        // 转换设施
        let pins = convertPins(detail.pins, upgradeLevel: upgradeLevel)
        
        // 转换连接
        let links = convertLinks(detail.links)
        
        // 转换路由
        let routes = convertRoutes(detail.routes)
        
        // 计算殖民地状态
        let status = getColonyStatus(pins: pins)
        
        // 计算殖民地概览
        let overview = getColonyOverview(routes: routes, pins: pins)
        Logger.info("======== 初始状态转换完成 ========")
        return Colony(
            id: colonyId,
            checkpointSimTime: updateDate,
            currentSimTime: updateDate,
            characterId: characterId,
            system: system,
            upgradeLevel: upgradeLevel,
            links: links,
            pins: pins,
            routes: routes,
            status: status,
            overview: overview
        )
    }
    
    /// 获取设施组ID
    /// - Parameter typeId: 类型ID
    /// - Returns: 组ID
    private static func getGroupId(for typeId: Int) -> Int {
        let query = "SELECT groupID FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["groupID"] as? Int ?? 0
        }
        return 0
    }
    
    /// 转换设施列表
    /// - Parameter planetaryPins: 行星设施列表
    /// - Returns: 设施模型列表
    private static func convertPins(_ planetaryPins: [PlanetaryPin], upgradeLevel: Int) -> [Pin] {
        return planetaryPins.map { convertPin($0, upgradeLevel: upgradeLevel) }
    }
    
    /// 转换单个设施
    /// - Parameter planetaryPin: 行星设施
    /// - Returns: 设施模型
    private static func convertPin(_ planetaryPin: PlanetaryPin, upgradeLevel: Int) -> Pin {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        // 解析安装时间和过期时间
        let installTime = planetaryPin.installTime != nil ? dateFormatter.date(from: planetaryPin.installTime!) : nil
        let expiryTime = planetaryPin.expiryTime != nil ? dateFormatter.date(from: planetaryPin.expiryTime!) : nil
        let lastCycleStart = planetaryPin.lastCycleStart != nil ? dateFormatter.date(from: planetaryPin.lastCycleStart!) : nil
        
        // 获取设施类型信息
        let typeInfo = getTypeInfo(planetaryPin.typeId)
        let pinType = Type(id: planetaryPin.typeId, name: typeInfo.name, volume: typeInfo.volume)
        
        // 设施名称和标识符
        let pinName = typeInfo.name
        let designator = "PIN-\(planetaryPin.pinId % 10000)"
        
        // 转换内容
        var contents: [Type: Int64] = [:]
        if let pinContents = planetaryPin.contents {
            for content in pinContents {
                // 从数据库获取类型信息
                let contentTypeInfo = getTypeInfo(content.typeId)
                let contentType = Type(id: content.typeId, name: contentTypeInfo.name, volume: contentTypeInfo.volume)
                contents[contentType] = content.amount
            }
        }
        
        // 计算已使用容量
        var capacityUsed: Double = 0.0
        for (type, quantity) in contents {
            capacityUsed += type.volume * Double(quantity)
        }
        
        // 根据设施组ID创建不同的设施对象
        let groupId = getGroupId(for: planetaryPin.typeId)
        
        switch groupId {
        case 1063:  // 采集控制器/提取器组
            // 提取器
            if let extractorDetails = planetaryPin.extractorDetails {
                let productTypeInfo = extractorDetails.productTypeId != nil ? getTypeInfo(extractorDetails.productTypeId!) : (name: "", volume: 0.0)
                let productType = extractorDetails.productTypeId != nil ? Type(id: extractorDetails.productTypeId!, name: productTypeInfo.name, volume: productTypeInfo.volume) : nil
                let cycleTime = extractorDetails.cycleTime != nil ? TimeInterval(extractorDetails.cycleTime!) : nil
                
                // 转换采集头
                var heads: [PlanetaryExtractorHead] = []
                for head in extractorDetails.heads {
                    heads.append(PlanetaryExtractorHead(latitude: Double(head.latitude), longitude: Double(head.longitude)))
                }
                
                Logger.info("提取器 ID: \(planetaryPin.pinId), 名称: \(pinName), 产品: \(productType?.name ?? "无"), 周期时间: \(cycleTime ?? 0)")
                
                return Pin.Extractor(
                    id: planetaryPin.pinId,
                    type: pinType,
                    name: pinName,
                    designator: designator,
                    lastRunTime: lastCycleStart,
                    contents: contents,
                    capacityUsed: capacityUsed,
                    isActive: expiryTime != nil && expiryTime! > Date(),
                    latitude: Double(planetaryPin.latitude),
                    longitude: Double(planetaryPin.longitude),
                    status: .notSetup,
                    expiryTime: expiryTime,
                    installTime: installTime,
                    cycleTime: cycleTime,
                    headRadius: extractorDetails.headRadius != nil ? Double(extractorDetails.headRadius!) : nil,
                    heads: heads,
                    productType: productType,
                    baseValue: extractorDetails.qtyPerCycle
                )
            }
            
            // 如果没有提取器详情，创建一个基本的Pin对象
            return Pin(
                id: planetaryPin.pinId,
                type: pinType,
                name: pinName,
                designator: designator,
                lastRunTime: nil,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: false,
                latitude: Double(planetaryPin.latitude),
                longitude: Double(planetaryPin.longitude),
                status: .notSetup
            )
            
        case 1028:  // 处理设施/工厂组
            // 工厂
            // 添加调试日志，打印所有属性
            Logger.info("工厂 ID: \(planetaryPin.pinId), typeId: \(planetaryPin.typeId), 直接schematicId: \(String(describing: planetaryPin.schematicId)), factoryDetails: \(String(describing: planetaryPin.factoryDetails))")
            
            // 获取配方ID，首先尝试从factoryDetails获取，如果不存在则直接使用schematicId
            var schematicId: Int? = nil
            if let factoryDetails = planetaryPin.factoryDetails {
                schematicId = factoryDetails.schematicId
                Logger.info("工厂 ID: \(planetaryPin.pinId), 从factoryDetails获取配方ID: \(factoryDetails.schematicId)")
            } else if let pinSchematicId = planetaryPin.schematicId {
                schematicId = pinSchematicId
                Logger.info("工厂 ID: \(planetaryPin.pinId), 直接获取配方ID: \(pinSchematicId)")
            } else {
                Logger.warning("工厂 ID: \(planetaryPin.pinId) 没有配方详情")
            }
            
            // 从数据库获取配方信息
            var schematic: Schematic? = nil
            if let id = schematicId {
                Logger.info("正在加载工厂配方，工厂ID: \(planetaryPin.pinId), 配方ID: \(id)")
                schematic = getSchematic(id)
                
                if schematic == nil {
                    Logger.warning("无法获取工厂配方，工厂ID: \(planetaryPin.pinId), 配方ID: \(id)")
                } else {
                    Logger.info("成功加载工厂配方，工厂ID: \(planetaryPin.pinId), 配方ID: \(id), 输出产品: \(schematic!.outputType.name)")
                }
            }
            
            return Pin.Factory(
                id: planetaryPin.pinId,
                type: pinType,
                name: pinName,
                designator: designator,
                lastRunTime: lastCycleStart,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: false,
                latitude: Double(planetaryPin.latitude),
                longitude: Double(planetaryPin.longitude),
                status: .notSetup,
                schematic: schematic,
                hasReceivedInputs: false,
                receivedInputsLastCycle: false,
                lastCycleStartTime: lastCycleStart
            )
            
        case 1029:  // 存储设施组
            // 存储设施
            Logger.info("存储设施 ID: \(planetaryPin.pinId), 名称: \(pinName), 初始容量使用: \(capacityUsed)")
            // 记录初始库存
            if !contents.isEmpty {
                Logger.info("存储设施 \(planetaryPin.pinId) 初始库存:")
                for (type, quantity) in contents {
                    Logger.info("  - \(type.name): \(quantity) 个 (体积: \(type.volume * Double(quantity)))")
                }
            } else {
                Logger.info("存储设施 \(planetaryPin.pinId) 初始库存为空")
            }
            
            return Pin.Storage(
                id: planetaryPin.pinId,
                type: pinType,
                name: pinName,
                designator: designator,
                lastRunTime: nil,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: true,
                latitude: Double(planetaryPin.latitude),
                longitude: Double(planetaryPin.longitude),
                status: .static
            )
            
        case 1030:  // 太空港/发射台组
            // 发射台
            Logger.info("发射台 ID: \(planetaryPin.pinId), 名称: \(pinName), 初始容量使用: \(capacityUsed)")
            // 记录初始库存
            if !contents.isEmpty {
                Logger.info("发射台 \(planetaryPin.pinId) 初始库存:")
                for (type, quantity) in contents {
                    Logger.info("  - \(type.name): \(quantity) 个 (体积: \(type.volume * Double(quantity)))")
                }
            } else {
                Logger.info("发射台 \(planetaryPin.pinId) 初始库存为空")
            }
            
            return Pin.Launchpad(
                id: planetaryPin.pinId,
                type: pinType,
                name: pinName,
                designator: designator,
                lastRunTime: nil,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: true,
                latitude: Double(planetaryPin.latitude),
                longitude: Double(planetaryPin.longitude),
                status: .static
            )
            
        case 1027:  // 指挥中心组
            // 指挥中心
            Logger.info("指挥中心 ID: \(planetaryPin.pinId), 名称: \(pinName), 等级: \(upgradeLevel), 初始容量使用: \(capacityUsed)")
            // 记录初始库存
            if !contents.isEmpty {
                Logger.info("指挥中心 \(planetaryPin.pinId) 初始库存:")
                for (type, quantity) in contents {
                    Logger.info("  - \(type.name): \(quantity) 个 (体积: \(type.volume * Double(quantity)))")
                }
            } else {
                Logger.info("指挥中心 \(planetaryPin.pinId) 初始库存为空")
            }
            
            return Pin.CommandCenter(
                id: planetaryPin.pinId,
                type: pinType,
                name: pinName,
                designator: designator,
                lastRunTime: nil,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: true,
                latitude: Double(planetaryPin.latitude),
                longitude: Double(planetaryPin.longitude),
                status: .static,
                level: upgradeLevel
            )
            
        default:
            // 其他设施
            Logger.info("其他设施采用默认配置: \(planetaryPin.pinId)")
            return Pin(
                id: planetaryPin.pinId,
                type: pinType,
                name: pinName,
                designator: designator,
                lastRunTime: nil,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: true,
                latitude: Double(planetaryPin.latitude),
                longitude: Double(planetaryPin.longitude),
                status: .static
            )
        }
    }
    
    /// 转换连接列表
    /// - Parameter planetaryLinks: 行星连接列表
    /// - Returns: 连接模型列表
    private static func convertLinks(_ planetaryLinks: [PlanetaryLink]) -> [PlanetaryLink] {
        return planetaryLinks
    }
    
    /// 转换路由列表
    /// - Parameter planetaryRoutes: 行星路由列表
    /// - Returns: 路由模型列表
    private static func convertRoutes(_ planetaryRoutes: [PlanetaryRoute]) -> [Route] {
        return planetaryRoutes.map { convertRoute($0) }
    }
    
    /// 转换单个路由
    /// - Parameter planetaryRoute: 行星路由
    /// - Returns: 路由模型
    private static func convertRoute(_ planetaryRoute: PlanetaryRoute) -> Route {
        let typeInfo = getTypeInfo(planetaryRoute.contentTypeId)
        let type = Type(id: planetaryRoute.contentTypeId, name: typeInfo.name, volume: typeInfo.volume)
        
        return Route(
            type: type,
            sourcePinId: planetaryRoute.sourcePinId,
            destinationPinId: planetaryRoute.destinationPinId,
            quantity: Int64(planetaryRoute.quantity),
            routeId: planetaryRoute.routeId,
            waypoints: planetaryRoute.waypoints
        )
    }
    
    /// 获取类型信息
    /// - Parameter typeId: 类型ID
    /// - Returns: 类型名称和体积
    private static func getTypeInfo(_ typeId: Int) -> (name: String, volume: Double) {
        let query = "SELECT name, volume FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            let name = row["name"] as? String ?? "Unknown"
            let volume = row["volume"] as? Double ?? 1.0
            return (name: name, volume: volume)
        }
        
        return (name: "Unknown", volume: 1.0)
    }
    
    /// 获取配方
    /// - Parameter schematicId: 配方ID
    /// - Returns: 配方
    private static func getSchematic(_ schematicId: Int) -> Schematic? {
        // 添加调试日志
        Logger.info("尝试获取配方 ID: \(schematicId)")
        
        // 从数据库获取配方信息
        let query = """
            SELECT schematic_id, output_typeid, name, cycle_time, output_value, input_typeid, input_value
            FROM planetSchematics
            WHERE schematic_id = ?
        """
        
        // 记录查询结果
        let result = DatabaseManager.shared.executeQuery(query, parameters: [schematicId])
        switch result {
        case .success(let rows):
            if rows.isEmpty {
                Logger.warning("未找到配方数据，配方ID: \(schematicId)")
                return nil
            }
            Logger.info("成功查询到配方数据，配方ID: \(schematicId), 行数: \(rows.count)")
            
            // 记录第一行数据的内容
            if let row = rows.first {
                let keys = Array(row.keys).sorted()
                Logger.info("配方数据: \(keys.map { "\($0)=\(String(describing: row[$0]))" }.joined(separator: ", "))")
            }
        case .error(let errorMessage):
            Logger.error("查询配方失败，配方ID: \(schematicId), 错误: \(errorMessage)")
            return nil
        }
        
        guard case .success(let rows) = result,
              let row = rows.first,
              let id = row["schematic_id"] as? Int,
              let outputTypeId = row["output_typeid"] as? Int,
              let cycleTime = row["cycle_time"] as? Int,
              let outputValue = row["output_value"] as? Int else {
            Logger.error("配方数据格式不正确，配方ID: \(schematicId)")
            // 记录实际数据内容
            if case .success(let rows) = result, let row = rows.first {
                let keys = Array(row.keys).sorted()
                let values = keys.map { "\($0)=\(type(of: row[$0])) \(String(describing: row[$0]))" }
                Logger.error("实际数据: \(values.joined(separator: ", "))")
            }
            return nil
        }
        
        // 获取输出类型信息
        let outputTypeInfo = getTypeInfo(outputTypeId)
        let outputType = Type(id: outputTypeId, name: outputTypeInfo.name, volume: outputTypeInfo.volume)
        
        Logger.info("配方输出: \(outputTypeInfo.name) (ID: \(outputTypeId)), 数量: \(outputValue), 单位体积: \(outputType.volume)")
        
        // 解析输入类型ID和数量
        var inputs: [Type: Int64] = [:]
        if let inputTypeIdString = row["input_typeid"] as? String,
           let inputValueString = row["input_value"] as? String {
            
            let inputTypeIds = inputTypeIdString.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let inputValues = inputValueString.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            
            if inputTypeIds.count == inputValues.count {
                for i in 0..<inputTypeIds.count {
                    let typeId = inputTypeIds[i]
                    let quantity = inputValues[i]
                    
                    let typeInfo = getTypeInfo(typeId)
                    let type = Type(id: typeId, name: typeInfo.name, volume: typeInfo.volume)
                    inputs[type] = Int64(quantity)
                    
                    Logger.info("配方输入: \(typeInfo.name) (ID: \(typeId)), 数量: \(quantity)")
                }
            } else {
                Logger.warning("输入类型ID和数量不匹配，配方ID: \(schematicId)")
                Logger.warning("输入类型ID: \(inputTypeIdString), 输入数量: \(inputValueString)")
            }
        }
        
        return Schematic(
            id: id,
            cycleTime: TimeInterval(cycleTime),
            outputType: outputType,
            outputQuantity: Int64(outputValue),
            inputs: inputs
        )
    }
    
    /// 获取殖民地状态
    /// - Parameter pins: 设施列表
    /// - Returns: 殖民地状态
    private static func getColonyStatus(pins: [Pin]) -> ColonyStatus {
        var extractors: [Pin.Extractor] = []
        var factories: [Pin.Factory] = []
        var storages: [Pin.Storage] = []
        var launchpads: [Pin.Launchpad] = []
        var commandCenters: [Pin.CommandCenter] = []
        
        // 分类设施
        for pin in pins {
            if let extractor = pin as? Pin.Extractor {
                extractors.append(extractor)
            } else if let factory = pin as? Pin.Factory {
                factories.append(factory)
            } else if let storage = pin as? Pin.Storage {
                storages.append(storage)
            } else if let launchpad = pin as? Pin.Launchpad {
                launchpads.append(launchpad)
            } else if let commandCenter = pin as? Pin.CommandCenter {
                commandCenters.append(commandCenter)
            }
        }
        
        // 使用外部函数获取殖民地状态
        return EVE_Nexus.getColonyStatus(pins: pins)
    }
    
    /// 获取殖民地概览
    /// - Parameters:
    ///   - routes: 路由列表
    ///   - pins: 设施列表
    /// - Returns: 殖民地概览
    private static func getColonyOverview(routes: [Route], pins: [Pin]) -> ColonyOverview {
        // 计算最终产品
        var finalProducts: [Type: Int64] = [:]
        var routesByDestination: [Int64: [Route]] = [:]
        
        // 按目标设施分组路由
        for route in routes {
            if routesByDestination[route.destinationPinId] == nil {
                routesByDestination[route.destinationPinId] = []
            }
            routesByDestination[route.destinationPinId]?.append(route)
        }
        
        // 查找工厂和发射台
        var factories: [Pin.Factory] = []
        var launchpads: [Pin.Launchpad] = []
        
        for pin in pins {
            if let factory = pin as? Pin.Factory {
                factories.append(factory)
            } else if let launchpad = pin as? Pin.Launchpad {
                launchpads.append(launchpad)
            }
        }
        
        // 查找没有输出路由的工厂（最终产品工厂）
        for factory in factories {
            var hasOutputRoute = false
            for route in routes {
                if route.sourcePinId == factory.id {
                    hasOutputRoute = true
                    break
                }
            }
            
            // 如果没有输出路由，则该工厂生产最终产品
            if !hasOutputRoute && factory.schematic != nil {
                let outputType = factory.schematic!.outputType
                let outputQuantity = factory.schematic!.outputQuantity
                
                // 累加最终产品数量
                if finalProducts[outputType] == nil {
                    finalProducts[outputType] = 0
                }
                finalProducts[outputType]! += outputQuantity
            }
        }
        
        // 计算发射台存储情况
        var launchpadStorage: [Type: Int64] = [:]
        for launchpad in launchpads {
            for (type, quantity) in launchpad.contents {
                if launchpadStorage[type] == nil {
                    launchpadStorage[type] = 0
                }
                launchpadStorage[type]! += quantity
            }
        }
        
        // 将字典转换为集合
        let finalProductsSet = Set(finalProducts.keys)
        
        // 计算容量和使用情况
        var totalCapacity = 0
        var otherUsedCapacity: Double = 0
        var finalProductsUsedCapacity: Double = 0
        
        for launchpad in launchpads {
            if let capacity = getCapacity(for: launchpad) {
                totalCapacity += capacity
            }
            
            for (type, quantity) in launchpad.contents {
                let volumeUsed = Double(type.volume) * Double(quantity)
                if finalProductsSet.contains(type) {
                    finalProductsUsedCapacity += volumeUsed
                } else {
                    otherUsedCapacity += volumeUsed
                }
            }
        }
        
        return ColonyOverview(
            finalProducts: finalProductsSet,
            capacity: totalCapacity,
            otherUsedCapacity: otherUsedCapacity,
            finalProductsUsedCapacity: finalProductsUsedCapacity
        )
    }
} 
