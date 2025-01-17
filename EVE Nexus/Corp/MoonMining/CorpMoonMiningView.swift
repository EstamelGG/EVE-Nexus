import SwiftUI
import Foundation

struct CorpMoonMiningView: View {
    let characterId: Int
    @StateObject private var viewModel = CorpMoonMiningViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?
    @State private var showError = false
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else {
                ForEach(viewModel.moonExtractions, id: \.moon_id) { extraction in
                    MoonExtractionRow(
                        extraction: extraction,
                        moonName: viewModel.moonNames[extraction.moon_id] ?? "未知月球"
                    )
                }
            }
        }
        .task {
            // 首次加载
            await loadData()
        }
        .navigationTitle("军团月矿作业")
        .refreshable {
            // 下拉刷新时强制刷新
            await loadData(forceRefresh: true)
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text(NSLocalizedString("Common_Error", comment: "")),
                message: Text(error?.localizedDescription ?? NSLocalizedString("Common_Unknown_Error", comment: "")),
                dismissButton: .default(Text(NSLocalizedString("Common_OK", comment: ""))) {
                    dismiss()
                }
            )
        }
    }
    
    private func loadData(forceRefresh: Bool = false) async {
        do {
            try await viewModel.fetchMoonExtractions(characterId: characterId, forceRefresh: forceRefresh)
        } catch {
            self.error = error
            self.showError = true
            Logger.error("获取月矿提取信息失败: \(error)")
        }
    }
}

struct MoonExtractionRow: View {
    let extraction: MoonExtractionInfo
    let moonName: String
    
    var body: some View {
        HStack(spacing: 12) {
            // 月球图标
            IconManager.shared.loadImage(for: "icon_14_64.png")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 44, height: 44)
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 44, height: 44)
                )
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                // 月球名称
                Text(moonName)
                    .font(.headline)
                
                // 矿石抵达时间
                Text("矿石抵达: \(extraction.chunk_arrival_time.toLocalTime())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // 自然碎裂时间
                Text("自然碎裂: \(extraction.natural_decay_time.toLocalTime())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// ViewModel
@MainActor
class CorpMoonMiningViewModel: ObservableObject {
    @Published var moonExtractions: [MoonExtractionInfo] = []
    @Published var moonNames: [Int64: String] = [:]
    @Published private(set) var isLoading = false
    
    func fetchMoonExtractions(characterId: Int, forceRefresh: Bool = false) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        let extractions = try await CorpMoonExtractionAPI.shared.fetchMoonExtractions(
            characterId: characterId
        )
        
        // 获取当前时间
        let now = Date()
        let calendar = Calendar.current
        
        // 过滤并排序月矿数据
        moonExtractions = extractions
            .filter { extraction in
                // 将chunk_arrival_time转换为Date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                
                guard let arrivalDate = dateFormatter.date(from: extraction.chunk_arrival_time) else {
                    return false
                }
                
                // 计算时间差（天数）
                let days = calendar.dateComponents([.day], from: now, to: arrivalDate).day ?? 0
                
                // 只保留未来36天内的数据
                return days >= -1 && days <= 36
            }
            .sorted { first, second in
                first.chunk_arrival_time < second.chunk_arrival_time
            }
        
        // 如果有数据，批量获取月球名称
        if !moonExtractions.isEmpty {
            let moonIds = moonExtractions.map { String($0.moon_id) }.joined(separator: ",")
            let query = "SELECT itemID, itemName FROM invNames WHERE itemID IN (\(moonIds))"
            
            if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                var names: [Int64: String] = [:]
                for row in rows {
                    if let itemId = row["itemID"] as? Int64,
                       let name = row["itemName"] as? String {
                        names[itemId] = name
                    }
                }
                moonNames = names
            }
        } else {
            moonNames.removeAll()
        }
    }
}

// 日期转换扩展
extension String {
    func toLocalTime() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let date = dateFormatter.date(from: self) else {
            return self
        }
        
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.string(from: date)
    }
} 
