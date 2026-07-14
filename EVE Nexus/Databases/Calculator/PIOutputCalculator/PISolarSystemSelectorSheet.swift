import SwiftUI

/// 星系选择器Sheet - 复用JumpNavigationView中的SystemSelectorSheet
struct PISolarSystemSelectorSheet: View {
    let title: String
    let onSelect: (Int, String) -> Void // 接收星系ID和名称
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
                onlyLowSec: false, // PI可以在所有星系进行
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

    /// 加载所有星系数据
    private func loadAllSystemsData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let query = """
                SELECT solarsystem_id, system_security, region_id, x, y, z
                FROM universe
            """

            var systems: [JumpSystemData] = []

            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    guard let id = row["solarsystem_id"] as? Int,
                          let security = row["system_security"] as? Double,
                          let regionId = row["region_id"] as? Int,
                          let x = row["x"] as? Double,
                          let y = row["y"] as? Double,
                          let z = row["z"] as? Double
                    else { continue }

                    systems.append(
                        JumpSystemData(
                            id: id,
                            security: calculateDisplaySecurity(security),
                            regionId: regionId,
                            x: x,
                            y: y,
                            z: z
                        )
                    )
                }
            }

            systems.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                allSystems = systems
                isLoadingData = false
            }
        }
    }
}
