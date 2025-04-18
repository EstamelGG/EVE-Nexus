import SwiftUI

// 定义行星资源链视图
struct PIResourceChainView: View {
    let resourceId: Int
    let resourceName: String
    let systemIds: [Int]
    let maxJumps: Int  // 添加最大跳数参数
    let centerSystemId: Int?  // 添加中心星系ID参数

    @State private var resourceChain: [PIResourceChainInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var systemInfo: (name: String, security: Double, region: String)? = nil
    @State private var sovereigntyInfo: (id: Int?, name: String?, icon: Image?)? = nil
    @State private var p0Resources: [(id: Int, name: String, icon: String, quantity: Double)] = []

    private let calculator = PIResourceChainCalculator()

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                        Spacer()
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            } else {
                // 基本信息部分
                Section(
                    header: Text(NSLocalizedString("PI_Production_Plan_BasicInfo", comment: ""))
                ) {
                    // 产品信息
                    HStack {
                        if let chain = resourceChain.first {
                            Text(NSLocalizedString("PI_Production_name", comment: ""))
                                .font(.body)
                            Spacer()
                            Image(uiImage: IconManager.shared.loadUIImage(for: chain.iconFileName))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)

                            Text(chain.resourceName)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 中心星系信息
                    if let systemInfo = systemInfo {
                        HStack {
                            Text(NSLocalizedString("PI_Production_solar", comment: ""))
                                .font(.body)
                            Spacer()
                            Text(formatSystemSecurity(systemInfo.security))
                                .foregroundColor(getSecurityColor(systemInfo.security))
                                .font(.system(.body, design: .monospaced))
                            Text(systemInfo.name)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 跳数信息
                    HStack {
                        Text(NSLocalizedString("PI_Production_Plan_JumpRange", comment: "跳数范围"))
                            .font(.body)

                        Spacer()

                        Text(
                            "\(maxJumps) \(NSLocalizedString("PI_Production_Plan_Systems", comment: "跳"))"
                        )
                        .foregroundColor(.secondary)
                    }

                    // 主权信息
                    if let sovereignty = sovereigntyInfo, let icon = sovereignty.icon,
                        let name = sovereignty.name
                    {
                        HStack {
                            Text(NSLocalizedString("PI_Production_Sov", comment: ""))
                                .font(.body)
                            Spacer()
                            icon
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                            Text(name)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // P0资源需求部分
                if !p0Resources.isEmpty {
                    Section(
                        header: Text(
                            NSLocalizedString(
                                "PI_Production_Plan_P0Requirements", comment: "需求资源与比例"))
                    ) {
                        ForEach(p0Resources, id: \.id) { resource in
                            NavigationLink(
                                destination: P0ResourceDetailView(
                                    resourceId: resource.id, resourceName: resource.name,
                                    systemIds: systemIds)
                            ) {
                                HStack {
                                    Image(
                                        uiImage: IconManager.shared.loadUIImage(for: resource.icon)
                                    )
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)

                                    Text(resource.name)
                                        .font(.body)

                                    Spacer()

                                    Text(String(format: "%.0f", resource.quantity))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("PI_Production_Plan_Title", comment: "生产方案"))
        .onAppear {
            loadResourceChain()
            loadSystemInfo()
            loadSovereigntyInfo()
        }
    }

    private func loadResourceChain() {
        isLoading = true
        errorMessage = nil

        // 改为获取完整资源链
        calculator.calculateFullResourceChain(for: resourceId, in: systemIds) { result in
            DispatchQueue.main.async {
                if let allResources = result, !allResources.isEmpty {
                    self.resourceChain = allResources
                    self.calculateP0Requirements()
                } else {
                    self.errorMessage =
                        NSLocalizedString("PI_Resource_Chain_Error", comment: "无法加载资源链信息")
                        + " (ID: \(resourceId))"
                }
                self.isLoading = false
            }
        }
    }

    private func loadSystemInfo() {
        // 使用centerSystemId作为中心星系，如果为nil则使用systemIds中的第一个ID
        let systemId = centerSystemId ?? systemIds.first
        guard let systemId = systemId else { return }

        // 使用缓存类获取系统信息
        if let systemInfo = PIResourceCache.shared.getSystemInfo(for: systemId) {
            self.systemInfo = (
                name: systemInfo.name, security: systemInfo.security, region: systemInfo.region
            )
        }
    }

    private func loadSovereigntyInfo() {
        guard let systemId = systemIds.first else { return }

        Task {
            do {
                let sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                    forceRefresh: false)
                if let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                    let id = systemData.allianceId ?? systemData.factionId
                    var name: String?

                    if let allianceId = systemData.allianceId {
                        let allianceInfo = try await AllianceAPI.shared.fetchAllianceInfo(
                            allianceId: allianceId)
                        name = allianceInfo.name

                        // 直接获取联盟图标
                        let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                            allianceID: allianceId)
                        if let uiImage = allianceIcon {
                            let image = Image(uiImage: uiImage)
                            DispatchQueue.main.async {
                                self.sovereigntyInfo = (id: allianceId, name: name, icon: image)
                            }
                        } else {
                            self.sovereigntyInfo = (id: allianceId, name: name, icon: nil)
                        }
                    }
                    self.sovereigntyInfo = (id: id, name: name, icon: nil)
                }
            } catch {
                Logger.error("无法加载主权数据: \(error)")
            }
        }
    }

    private func calculateP0Requirements() {
        // 按资源等级分组
        var resourcesByLevel: [Int: [PIResourceChainInfo]] = [:]
        for resource in resourceChain {
            resourcesByLevel[resource.resourceLevel, default: []].append(resource)
        }

        // 获取最高等级
        guard let maxLevel = resourcesByLevel.keys.max() else {
            Logger.warning("没有找到任何资源等级")
            return
        }

        // 计算每个资源需要的数量
        var resourceQuantities: [Int: Double] = [:]

        // 从最高等级开始，初始数量为1
        if let topLevelResources = resourcesByLevel[maxLevel] {
            for resource in topLevelResources {
                resourceQuantities[resource.resourceId] = 1.0
                // Logger.info("P\(maxLevel)资源 \(resource.resourceName) 初始数量: 1.0")
            }
        }

        // 逐级向下计算
        for level in (0..<maxLevel).reversed() {
            if let resources = resourcesByLevel[level] {
                for resource in resources {
                    // 查找需要这个资源的所有上级资源
                    let upperResources = resourceChain.filter { upper in
                        upper.resourceLevel > level
                            && upper.requiredResources.contains(resource.resourceId)
                    }

                    // 计算这个资源需要的总数量
                    var totalRequired = 0.0
                    for upper in upperResources {
                        if let schematic = PIResourceCache.shared.getSchematic(
                            for: upper.resourceId)
                        {
                            let outputValue = Double(schematic.outputValue)
                            let inputIndex =
                                schematic.inputTypeIds.firstIndex(of: resource.resourceId) ?? -1
                            if inputIndex >= 0 {
                                let inputValue = Double(schematic.inputValues[inputIndex])
                                let upperQuantity = resourceQuantities[upper.resourceId] ?? 0.0
                                let required = upperQuantity * (inputValue / outputValue)
                                totalRequired += required
                                // Logger.info("\(resource.resourceName) 需要 \(required) 个来生产 \(upper.resourceName)")
                            }
                        }
                    }

                    if totalRequired > 0 {
                        resourceQuantities[resource.resourceId] = totalRequired
                        // Logger.info("\(resource.resourceName) 总需求量: \(totalRequired)")
                    }
                }
            }
        }

        // 打印资源链信息
        //        Logger.info("资源链信息:")
        //        for level in (0...maxLevel).reversed() {
        //            if let resources = resourcesByLevel[level] {
        //                let resourceInfo = resources.map { resource -> String in
        //                    var name = resource.resourceName
        //                    let quantity = resourceQuantities[resource.resourceId] ?? 0.0
        //                    if let schematic = PIResourceCache.shared.getSchematic(for: resource.resourceId) {
        //                        name += String(format: " (%.1f需要, %d输入/%d输出)",
        //                            quantity,
        //                            schematic.inputValues.reduce(0, +),
        //                            schematic.outputValue)
        //                    }
        //                    return name
        //                }.joined(separator: ",")
        //                Logger.info("P\(level):\(resourceInfo)")
        //            }
        //        }

        // 获取所有P0资源
        //        Logger.info("准备计算P0资源需求")
        let p0s = resourceChain.filter { $0.resourceLevel == 0 }

        //        Logger.info("找到 \(p0s.count) 个P0资源")
        //        for p0 in p0s {
        //            Logger.info("P0资源: ID=\(p0.resourceId), 名称=\(p0.resourceName)")
        //        }

        if p0s.isEmpty {
            Logger.warning("没有找到P0资源，无法计算需求")
            return
        }

        // 计算总数量
        let totalQuantity = p0s.reduce(0.0) { total, p0 in
            total + (resourceQuantities[p0.resourceId] ?? 0.0)
        }

        // Logger.info("P0资源总数量: \(totalQuantity)")

        if totalQuantity > 0 {
            // 保存每个P0资源的实际数量
            p0Resources = p0s.map { p0 in
                let quantity = resourceQuantities[p0.resourceId] ?? 0.0

                // Logger.info("P0资源数量: ID=\(p0.resourceId), 名称=\(p0.resourceName), 数量=\(quantity)")

                return (
                    id: p0.resourceId,
                    name: p0.resourceName,
                    icon: p0.iconFileName,
                    quantity: quantity
                )
            }

            // 按数量从大到小排序
            p0Resources.sort { $0.quantity > $1.quantity }
            // Logger.info("P0资源按数量排序完成")
        } else {
            Logger.warning("P0资源总数量为0")
            p0Resources = []
        }

        Logger.info("P0资源需求计算完成，共 \(p0Resources.count) 个资源")
    }
}
