import SwiftUI

struct MarketItemDetailView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let itemID: Int
    @State private var showFullItemInfo = false
    @State private var marketPath: [String] = []
    @State private var itemDetails: ItemDetails?
    
    var body: some View {
        List {
            // 基本信息部分
            Section {
                if let details = itemDetails {
                    HStack {
                        // 物品图标
                        IconManager.shared.loadImage(for: details.iconFileName)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // 物品名称
                            Text(details.name)
                                .font(.headline)
                            
                            // 分类路径
                            Text(marketPath.joined(separator: " > "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        // 查看详情按钮
                        Button {
                            showFullItemInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title2)
                        }
                        .sheet(isPresented: $showFullItemInfo) {
                            if let categoryID = itemDetails?.categoryID {
                                ItemInfoMap.getItemInfoView(
                                    itemID: itemID,
                                    categoryID: categoryID,
                                    databaseManager: databaseManager
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadItemDetails()
            loadMarketPath()
        }
    }
    
    private func loadItemDetails() {
        itemDetails = databaseManager.loadItemDetails(for: itemID)
    }
    
    private func loadMarketPath() {
        // 从数据库加载市场路径
        if let path = databaseManager.getMarketPath(for: itemID) {
            marketPath = path
        }
    }
}

#Preview {
    MarketItemDetailView(databaseManager: DatabaseManager(), itemID: 34)
} 