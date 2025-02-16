import Foundation

/// 行星开发仓库
class PlanetaryIndustryRepository {
    // MARK: - Properties
    
    /// 殖民地
    private var colony: Colony?
    
    /// 最后更新时间
    private var lastUpdate: Date?
    
    /// 是否正在模拟
    private var isSimulating = false
    
    // MARK: - Methods
    
    /// 创建殖民地
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - planetId: 行星ID
    ///   - planetaryDetail: 行星详情
    ///   - startTime: 开始时间
    /// - Returns: 殖民地对象
    func createColony(characterId: Int, planetId: Int, planetaryDetail: PlanetaryDetail, startTime: String) -> Colony {
        // 创建设施列表
        let pins = planetaryDetail.pins.map { createPin(from: $0) }
        
        // 将 startTime 字符串转换为 Date
        let dateFormatter = ISO8601DateFormatter()
        let checkpointTime = dateFormatter.date(from: startTime) ?? Date()
        
        // 创建 Colony 对象
        let colony = Colony(
            id: "\(characterId)_\(planetId)",
            checkpointSimTime: checkpointTime,
            currentSimTime: Date(),
            characterId: characterId,
            links: planetaryDetail.links.map { link in
                PlanetaryFacilityLink(
                    sourcePinId: link.sourcePinId,
                    destinationPinId: link.destinationPinId,
                    level: link.linkLevel
                )
            },
            pins: pins,
            routes: planetaryDetail.routes.map { route in
                Route(
                    type: createCommodityType(typeId: route.contentTypeId),
                    sourcePinId: route.sourcePinId,
                    destinationPinId: route.destinationPinId,
                    quantity: Int64(route.quantity),
                    routeId: route.routeId,
                    waypoints: route.waypoints
                )
            },
            status: getColonyStatus(pins: pins)
        )
        
        // 更新当前殖民地
        self.colony = colony
        self.lastUpdate = Date()
        
        return colony
    }
    
    /// 获取商品组ID
    /// - Parameter typeId: 商品ID
    /// - Returns: 商品组ID
    private func getGroupId(for typeId: Int) -> Int {
        let query = "SELECT groupID, volume, capacity, name, icon_filename FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["groupID"] as? Int ?? 0
        }
        return 0
    }
    
    /// 从 ESI 数据创建设施对象
    /// - Parameter pin: ESI 设施数据
    /// - Returns: 设施对象
    private func createPin(from pin: PlanetaryPin) -> Pin {
        // 创建基本属性
        let type = createCommodityType(typeId: pin.typeId)
        let designator = "\(pin.pinId)"
        let lastRunTime = pin.lastCycleStart.flatMap { ISO8601DateFormatter().date(from: $0) }
        let contents = pin.contents?.reduce(into: [:]) { result, content in
            result[createCommodityType(typeId: content.typeId)] = content.amount
        } ?? [:]
        let isActive = true  // 默认为激活状态
        
        // 根据设施组ID创建不同的设施对象
        let groupId = getGroupId(for: pin.typeId)
        switch groupId {
        case 1063:  // 采集控制器
            guard let extractorDetails = pin.extractorDetails else {
                return Pin(
                    id: pin.pinId,
                    type: type,
                    designator: designator,
                    lastRunTime: lastRunTime,
                    contents: contents,
                    isActive: true,
                    latitude: Float(pin.latitude),
                    longitude: Float(pin.longitude),
                    status: .Static
                )
            }
            
            // 转换日期字符串
            let dateFormatter = ISO8601DateFormatter()
            let expiryTime = pin.expiryTime.flatMap { dateFormatter.date(from: $0) }
            let installTime = pin.installTime.flatMap { dateFormatter.date(from: $0) }
            
            // 计算容量使用
            let capacityUsed: Float = contents.reduce(0) { result, item in
                result + Float(item.key.volume * Float(item.value))
            }
            
            return ExtractorPin(
                id: pin.pinId,
                type: type,
                designator: String(pin.pinId),
                lastRunTime: lastRunTime,
                contents: contents,
                capacityUsed: capacityUsed,
                isActive: true,
                latitude: Float(pin.latitude),
                longitude: Float(pin.longitude),
                status: .extracting,
                expiryTime: expiryTime,
                installTime: installTime,
                cycleTime: extractorDetails.cycleTime.map { TimeInterval($0) },
                productType: extractorDetails.productTypeId.map { createCommodityType(typeId: $0) },
                baseValue: extractorDetails.qtyPerCycle
            )
            
        case 1028:  // 处理设施
            let schematic = getSchematic(for: pin.schematicId ?? 0)
            return FactoryPin(
                id: pin.pinId,
                type: type,
                designator: designator,
                lastRunTime: lastRunTime,
                contents: contents,
                isActive: isActive,
                latitude: Float(pin.latitude),
                longitude: Float(pin.longitude),
                status: .factoryIdle,
                schematic: schematic
            )
            
        case 1029:  // 储藏设施
            return StoragePin(
                id: pin.pinId,
                type: type,
                designator: designator,
                lastRunTime: lastRunTime,
                contents: contents,
                isActive: isActive,
                latitude: Float(pin.latitude),
                longitude: Float(pin.longitude),
                status: .Static
            )
            
        case 1027:  // 指挥中心
            return CommandCenterPin(
                id: pin.pinId,
                type: type,
                designator: designator,
                lastRunTime: lastRunTime,
                contents: contents,
                isActive: isActive,
                latitude: Float(pin.latitude),
                longitude: Float(pin.longitude),
                status: .Static,
                level: 0
            )
            
        case 1030:  // 太空港
            return LaunchpadPin(
                id: pin.pinId,
                type: type,
                designator: designator,
                lastRunTime: lastRunTime,
                contents: contents,
                isActive: isActive,
                latitude: Float(pin.latitude),
                longitude: Float(pin.longitude),
                status: .Static
            )
            
        default:
            return Pin(
                id: pin.pinId,
                type: type,
                designator: designator,
                lastRunTime: lastRunTime,
                contents: contents,
                isActive: isActive,
                latitude: Float(pin.latitude),
                longitude: Float(pin.longitude),
                status: .Static
            )
        }
    }
    
    /// 获取当前殖民地
    /// - Returns: 殖民地对象
    func getColony() -> Colony? {
        return colony
    }
    
    /// 获取商品体积
    /// - Parameter typeId: 商品ID
    /// - Returns: 商品体积
    private func getVolume(for typeId: Int) -> Float {
        let query = "SELECT groupID, volume, capacity, name, icon_filename FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first,
           let volumeValue = row["volume"] as? Double {
            // 使用 Double 类型来保持精度，然后转换为 Float
            return Float(volumeValue)
        }
        return 0.0
    }
    
    /// 创建商品类型
    /// - Parameters:
    ///   - typeId: 商品ID
    ///   - name: 商品名称
    /// - Returns: 商品类型
    private func createCommodityType(typeId: Int) -> CommodityType {
        let volume = getVolume(for: typeId)
        return CommodityType(id: typeId, volume: volume)
    }
    
    /// 获取配方详细信息
    /// - Parameter schematicId: 配方ID
    /// - Returns: 配方对象
    private func getSchematic(for schematicId: Int) -> Schematic? {
        // 如果 schematicId 为 0，直接返回 nil
        if schematicId == 0 {
            return nil
        }
        
        let query = """
            SELECT output_typeid, cycle_time, output_value, input_typeid, input_value
            FROM planetSchematics
            WHERE schematic_id = ?
        """
        let result = DatabaseManager.shared.executeQuery(query, parameters: [schematicId])
        
        if case .success(let rows) = result, let row = rows.first,
           let outputTypeId = row["output_typeid"] as? Int,
           let cycleTime = row["cycle_time"] as? Int,
           let outputValue = row["output_value"] as? Int,
           let inputTypeIds = row["input_typeid"] as? String,
           let inputValues = row["input_value"] as? String {
            
            let inputs = zip(inputTypeIds.split(separator: ","), inputValues.split(separator: ","))
                .compactMap { typeId, value -> (CommodityType, Int64)? in
                    guard let typeId = Int(typeId),
                          let value = Int64(value) else { return nil }
                    return (createCommodityType(typeId: typeId), value)
                }
                .reduce(into: [:]) { $0[$1.0] = $1.1 }
            
            return Schematic(
                id: Int64(schematicId),
                outputType: createCommodityType(typeId: outputTypeId),
                outputQuantity: Int64(outputValue),
                cycleTime: TimeInterval(cycleTime),
                inputs: inputs
            )
        }
        
        // 如果查询失败，返回 nil
        return nil
    }
} 
