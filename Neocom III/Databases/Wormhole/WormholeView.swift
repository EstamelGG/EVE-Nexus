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
                VStack(alignment: .leading, spacing: 12) {
                    // 图标和渲染图
                    HStack(alignment: .top, spacing: 12) {
                        // 图标
                        IconManager.shared.loadImage(for: wormhole.icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(8)
                        
                        // 渲染图
                        if let image = renderImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    // 名称和目标空间
                    VStack(alignment: .leading, spacing: 8) {
                        Text(wormhole.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(wormhole.target)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // 描述
                    Text(wormhole.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
            
            // 详细信息部分
            Section {
                InfoRow(title: "稳定时间", value: wormhole.stableTime)
                InfoRow(title: "最大稳定质量", value: wormhole.maxStableMass)
                InfoRow(title: "最大跃迁质量", value: wormhole.maxJumpMass)
                InfoRow(title: "尺寸类型", value: wormhole.sizeType)
            } header: {
                Text("详细信息")
                    .font(.headline)
                    .textCase(.none)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
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

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
        }
    }
}

#Preview {
    NavigationView {
        WormholeView(databaseManager: DatabaseManager())
    }
} 
