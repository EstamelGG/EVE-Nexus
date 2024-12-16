import SwiftUI

struct WormholeView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var wormholes: [String: [WormholeInfo]] = [:]
    @State private var targetOrder: [String] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    
    var filteredWormholes: [String: [WormholeInfo]] {
        if searchText.isEmpty {
            return wormholes
        }
        
        var filtered: [String: [WormholeInfo]] = [:]
        for (target, items) in wormholes {
            let matchingItems = items.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.target.localizedCaseInsensitiveContains(searchText) ||
                $0.sizeType.localizedCaseInsensitiveContains(searchText)
            }
            if !matchingItems.isEmpty {
                filtered[target] = matchingItems
            }
        }
        return filtered
    }
    
    var body: some View {
        List {
            ForEach(searchText.isEmpty ? targetOrder : Array(filteredWormholes.keys.sorted()), id: \.self) { target in
                Section(header: Text(target)
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                ) {
                    ForEach(filteredWormholes[target] ?? wormholes[target] ?? []) { wormhole in
                        NavigationLink(destination: WormholeDetailView(wormhole: wormhole)) {
                            HStack(spacing: 12) {
                                // 左侧图标
                                IconManager.shared.loadImage(for: wormhole.icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                
                                // 右侧文本
                                VStack(alignment: .leading) {
                                    Text(wormhole.name)
                                        .font(.body)
                                    Text(wormhole.sizeType)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                            }
                            .frame(height: 36)
                            .padding(.vertical, 0)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .navigationTitle(NSLocalizedString("Main_Market_WH_info", comment: ""))
        .onAppear {
            loadWormholes()
        }
    }
    
    private func loadWormholes() {
        let items = databaseManager.loadWormholes()
        var tempWormholes: [String: [WormholeInfo]] = [:]
        var tempTargetOrder: [String] = []
        
        for item in items {
            if tempWormholes[item.target] == nil {
                tempWormholes[item.target] = []
                tempTargetOrder.append(item.target)
            }
            tempWormholes[item.target]?.append(item)
        }
        
        wormholes = tempWormholes
        targetOrder = tempTargetOrder
    }
}

struct WormholeDetailView: View {
    let wormhole: WormholeInfo
    @State private var renderImage: UIImage? = nil
    
    var body: some View {
        List {
            // 基本信息部分
            Section {
                WormholeBasicInfoView(wormhole: wormhole)
            }
            
            // 详细信息部分
            Section {
                InfoRow(title: NSLocalizedString("Main_Market_WH_Leadsto", comment: ""), 
                        value: wormhole.target,
                       iconName: "items_7_64_4.png")
                InfoRow(title: NSLocalizedString("Main_Market_WH_MaxStableTime", comment: ""),
                       value: wormhole.stableTime,
                       iconName: "items_22_32_16.png")
                InfoRow(title: NSLocalizedString("Main_Market_WH_MaxStableMass", comment: ""),
                       value: wormhole.maxStableMass,
                       iconName: "icon_1333_64.png")
                InfoRow(title: NSLocalizedString("Main_Market_WH_MaxJumpMass", comment: ""),
                       value: wormhole.maxJumpMass,
                       iconName: "items_9_64_5.png")
                InfoRow(title: NSLocalizedString("Main_Market_WH_Size", comment: ""),
                       value: wormhole.sizeType,
                        iconName: "items_22_32_15.png")
            } header: {
                Text(NSLocalizedString("Main_Market_WH_Details", comment: ""))
                    .font(.headline)
                    .textCase(.none)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoRow: View { // 虫洞详情
    let title: String
    let value: String
    let iconName: String?
    
    init(title: String, value: String, iconName: String? = nil) {
        self.title = title
        self.value = value
        self.iconName = iconName
    }
    
    var body: some View {
        HStack {
            if let iconName = iconName {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .aspectRatio(contentMode: .fit)
            }
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

// 虫洞基本信息视图
struct WormholeBasicInfoView: View {
    let wormhole: WormholeInfo
    @State private var renderImage: UIImage? = nil
    // iOS 标准圆角半径
    private let cornerRadius: CGFloat = 10
    // 标准边距
    private let standardPadding: CGFloat = 16
    var body: some View {
        Section {
            if let image = renderImage {
                // 大图布局
                ZStack(alignment: .bottomLeading) {
                    // 渲染图
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(cornerRadius)
                        .padding(.horizontal, standardPadding)
                        .padding(.vertical, standardPadding)
                    
                    // 信息覆盖层
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wormhole.name)
                            .font(.title)
                        Text("\(wormhole.target) / ID:\(wormhole.id)" )
                            .font(.subheadline)
                    }
                    .padding(.horizontal, standardPadding * 2)
                    .padding(.vertical, standardPadding)
                    .background(
                        Color.black.opacity(0.5)
                            .cornerRadius(cornerRadius, corners: [.bottomLeft, .topRight])
                    )
                    .foregroundColor(.white)
                    .padding(.horizontal, standardPadding)
                    .padding(.bottom, standardPadding)
                }
                .listRowInsets(EdgeInsets())  // 移除 List 的默认边距
            } else {
                // 小图标布局
                HStack(alignment: .top, spacing: 12) {
                    // 图标
                    IconManager.shared.loadImage(for: wormhole.icon)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                    
                    // 名称和目录
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wormhole.name)
                            .font(.title)
                        Text("\(wormhole.target) / ID:\(wormhole.id)" )
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // 描述
            Text(wormhole.description)
                .font(.body)
                .foregroundColor(.primary)
        }
        .task {
            await loadRenderImage()
        }
    }
    
    private func loadRenderImage() async {
        do {
            renderImage = try await NetworkManager.shared.fetchEVEItemRender(typeID: wormhole.id)
        } catch {
            Logger.error("Failed to load render image: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationView {
        WormholeView(databaseManager: DatabaseManager())
    }
} 
