import SwiftUI

// 星系选择器Sheet - 复用JumpNavigationView中的SystemSelectorSheet
struct PISolarSystemSelectorSheet: View {
    let title: String
    let onSelect: (Int, String) -> Void  // 接收星系ID和名称
    let onCancel: () -> Void
    let currentSelection: Int?
    
    // 使用懒加载的星系数据
    @State private var allSystems: [JumpSystemData] = []
    @State private var isLoadingData = true

    private let databaseManager = DatabaseManager.shared

    init(
        title: String, currentSelection: Int? = nil, onSelect: @escaping (Int, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.currentSelection = currentSelection
    }

    var body: some View {
        if isLoadingData {
            VStack {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("PI_Output_Loading_Systems", comment: ""))
                    .foregroundColor(.gray)
            }
            .onAppear {
                loadAllSystemsData()
            }
        } else {
            // 复用SystemSelectorSheet，但包装选择回调
            SystemSelectorSheet(
                title: title,
                currentSelection: currentSelection,
                onlyLowSec: false,  // PI可以在所有星系进行
                jumpSystems: allSystems,
                onSelect: { systemId in
                    // 找到对应的星系名称
                    if let system = allSystems.first(where: { $0.id == systemId }) {
                        onSelect(systemId, system.name)
                    } else {
                        onSelect(systemId, "Unknown System")
                    }
                },
                onCancel: onCancel
            )
        }
    }
    
    // 加载所有星系数据
    private func loadAllSystemsData() {
        DispatchQueue.global(qos: .userInitiated).async {
            // 查询所有星系，包含中英文名称，不限制跳跃门条件
            let query = """
                SELECT u.solarsystem_id, s.solarSystemName, s.solarSystemName_en, s.solarSystemName_zh,
                       u.system_security, r.regionName, u.x, u.y, u.z
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                JOIN regions r ON r.regionID = u.region_id
                ORDER BY s.solarSystemName
            """

            var systems: [JumpSystemData] = []
            
            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let id = row["solarsystem_id"] as? Int,
                        let name = row["solarSystemName"] as? String,
                        let nameEN = row["solarSystemName_en"] as? String,
                        let security = row["system_security"] as? Double,
                        let region = row["regionName"] as? String,
                        let x = row["x"] as? Double,
                        let y = row["y"] as? Double,
                        let z = row["z"] as? Double
                    {
                        // 获取中文名，如果为nil则使用英文名
                        let nameZH = (row["solarSystemName_zh"] as? String) ?? nameEN

                        // 计算显示安全等级
                        let displaySec = calculateDisplaySecurity(security)

                        systems.append(
                            JumpSystemData(
                                id: id,
                                name: name,
                                nameEN: nameEN,
                                nameZH: nameZH,
                                security: displaySec,
                                region: region,
                                x: x,
                                y: y,
                                z: z
                            )
                        )
                    }
                }
            }

            // 在主线程更新UI
            DispatchQueue.main.async {
                allSystems = systems
                isLoadingData = false
            }
        }
    }
}
