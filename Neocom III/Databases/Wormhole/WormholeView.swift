import SwiftUI

struct WormholeView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var wormholes: [String: [WormholeInfo]] = [:]
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
            ForEach(Array(filteredWormholes.keys.sorted()), id: \.self) { target in
                Section(header: Text(target)
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                ) {
                    ForEach(filteredWormholes[target] ?? []) { wormhole in
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
        
        for item in items {
            if tempWormholes[item.target] == nil {
                tempWormholes[item.target] = []
            }
            tempWormholes[item.target]?.append(item)
        }
        
        wormholes = tempWormholes
    }
}

struct WormholeDetailView: View {
    let wormhole: WormholeInfo
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 大图标
                Image(wormhole.icon.replacingOccurrences(of: ".png", with: ""))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 128, maxHeight: 128)
                    .padding()
                
                // 名称
                Text(wormhole.name)
                    .font(.title)
                    .padding(.horizontal)
                
                // 目标分类
                HStack {
                    Text("目标空间：")
                        .foregroundColor(.gray)
                    Text(wormhole.target)
                }
                .padding(.horizontal)
                
                // 基本信息
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(title: "稳定时间", value: wormhole.stableTime)
                    InfoRow(title: "最大稳定质量", value: wormhole.maxStableMass)
                    InfoRow(title: "最大跃迁质量", value: wormhole.maxJumpMass)
                    InfoRow(title: "尺寸类型", value: wormhole.sizeType)
                }
                .padding()
                
                // 描述信息
                VStack(alignment: .leading) {
                    Text("描述")
                        .font(.headline)
                    Text(wormhole.description)
                        .foregroundColor(.gray)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
