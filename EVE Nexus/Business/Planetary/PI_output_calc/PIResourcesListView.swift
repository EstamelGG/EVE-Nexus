import SwiftUI

// 添加PIResourcesListView用于显示特定等级的PI资源列表
struct PIResourcesListView: View {
    let title: String
    let resources: [Any]  // 使用Any类型来接受不同类型的资源
    let systemIds: [Int]
    let resourceLevel: Int
    let maxJumps: Int
    let centerSystemId: Int?  // 添加中心星系ID参数

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("PI_Available_production", comment: ""))) {
                ForEach(0..<resources.count, id: \.self) { index in
                    let resource = resources[index]
                    NavigationLink(
                        destination: PIResourceChainView(
                            resourceId: getResourceId(from: resource),
                            resourceName: getResourceName(from: resource),
                            systemIds: systemIds,
                            maxJumps: maxJumps,
                            centerSystemId: centerSystemId  // 传递中心星系ID
                        )
                    ) {
                        HStack {
                            Image(
                                uiImage: IconManager.shared.loadUIImage(
                                    for: getResourceIcon(from: resource))
                            )
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)

                            Text(getResourceName(from: resource))
                                .font(.body)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    // 辅助函数来获取资源信息
    private func getResourceId(from resource: Any) -> Int {
        switch resource {
        case let p0 as P0ResourceInfo: return p0.resourceId
        case let p1 as P1ResourceInfo: return p1.resourceId
        case let p2 as P2ResourceInfo: return p2.resourceId
        case let p3 as P3ResourceInfo: return p3.resourceId
        case let p4 as P4ResourceInfo: return p4.resourceId
        default: return 0
        }
    }

    private func getResourceName(from resource: Any) -> String {
        switch resource {
        case let p0 as P0ResourceInfo: return p0.resourceName
        case let p1 as P1ResourceInfo: return p1.resourceName
        case let p2 as P2ResourceInfo: return p2.resourceName
        case let p3 as P3ResourceInfo: return p3.resourceName
        case let p4 as P4ResourceInfo: return p4.resourceName
        default: return ""
        }
    }

    private func getResourceIcon(from resource: Any) -> String {
        switch resource {
        case let p0 as P0ResourceInfo: return p0.iconFileName
        case let p1 as P1ResourceInfo: return p1.iconFileName
        case let p2 as P2ResourceInfo: return p2.iconFileName
        case let p3 as P3ResourceInfo: return p3.iconFileName
        case let p4 as P4ResourceInfo: return p4.iconFileName
        default: return "not_found"
        }
    }
}
