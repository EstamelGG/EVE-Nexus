import SwiftUI
import Foundation

struct CorpMoonMiningView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpMoonMiningViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?
    @State private var showError = false
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CorpMoonMiningViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if viewModel.moonExtractions.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无月矿数据")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                if !viewModel.thisWeekExtractions.isEmpty {
                    Section(NSLocalizedString("Main_Corporation_Moon_Mining_This_Week", comment: "")) {
                        ForEach(viewModel.thisWeekExtractions, id: \.moon_id) { extraction in
                            MoonExtractionRow(
                                extraction: extraction,
                                moonName: viewModel.moonNames[Int(extraction.moon_id)] ?? NSLocalizedString("Main_Corporation_Moon_Mining_Unknown_Moon", comment: "")
                            )
                        }
                    }
                }
                
                if !viewModel.laterExtractions.isEmpty {
                    Section(NSLocalizedString("Main_Corporation_Moon_Mining_Later", comment: "")) {
                        ForEach(viewModel.laterExtractions, id: \.moon_id) { extraction in
                            MoonExtractionRow(
                                extraction: extraction,
                                moonName: viewModel.moonNames[Int(extraction.moon_id)] ?? NSLocalizedString("Main_Corporation_Moon_Mining_Unknown_Moon", comment: "")
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Moon_Mining", comment: ""))
        .refreshable {
            do {
                try await viewModel.fetchMoonExtractions(forceRefresh: true)
            } catch {
                if !(error is CancellationError) {
                    self.error = error
                    self.showError = true
                    Logger.error("刷新月矿提取信息失败: \(error)")
                }
            }
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
                .clipShape(Circle())
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
                Text(NSLocalizedString("Main_Corporation_Moon_Mining_Chunk_Arrival", comment: "") + extraction.chunk_arrival_time.toLocalTime())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // 自然碎裂时间
                Text(NSLocalizedString("Main_Corporation_Moon_Mining_Natural_Decay", comment: "") + extraction.natural_decay_time.toLocalTime())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// ViewModel
@MainActor
class CorpMoonMiningViewModel: ObservableObject {
    @Published var moonExtractions: [MoonExtractionInfo] = []
    @Published var moonNames: [Int: String] = [:]
    @Published private(set) var isLoading = false
    private let characterId: Int
    
    init(characterId: Int) {
        self.characterId = characterId
        // 在初始化时立即开始加载数据
        Task {
            do {
                try await fetchMoonExtractions()
            } catch {
                if !(error is CancellationError) {
                    Logger.error("初始化加载月矿提取信息失败: \(error)")
                }
            }
        }
    }
    
    // 计算属性：本周的月矿
    var thisWeekExtractions: [MoonExtractionInfo] {
        let calendar = Calendar.current
        let now = Date()
        let oneWeekLater = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        return moonExtractions.filter { extraction in
            guard let arrivalDate = extraction.chunk_arrival_time.toUTCDate() else { return false }
            return arrivalDate <= oneWeekLater
        }
    }
    
    // 计算属性：一周后的月矿
    var laterExtractions: [MoonExtractionInfo] {
        let calendar = Calendar.current
        let now = Date()
        let oneWeekLater = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        return moonExtractions.filter { extraction in
            guard let arrivalDate = extraction.chunk_arrival_time.toUTCDate() else { return false }
            return arrivalDate > oneWeekLater
        }
    }
    
    func fetchMoonExtractions(forceRefresh: Bool = false) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        let extractions = try await CorpMoonExtractionAPI.shared.fetchMoonExtractions(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        
        // 获取当前时间
        let now = Date()
        let calendar = Calendar.current
        
        // 过滤并排序月矿数据
        moonExtractions = extractions
            .filter { extraction in
                guard let arrivalDate = extraction.chunk_arrival_time.toUTCDate() else {
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
            // 对moon_id去重
            let uniqueMoonIds = Set(moonExtractions.map { Int($0.moon_id) })
            let moonIds = uniqueMoonIds.map { String($0) }.joined(separator: ",")
            let query = "SELECT itemID, itemName FROM invNames WHERE itemID IN (\(moonIds))"
            
            if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                var names: [Int: String] = [:]
                for row in rows {
                    if let itemId = row["itemID"] as? Int,
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
        guard let date = toUTCDate() else {
            return self
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"  // EEEE 表示完整的星期名称
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: NSLocalizedString("Language_Identifier", comment: ""))  // 根据当前语言设置区域
        return dateFormatter.string(from: date)
    }
    
    func toUTCDate() -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")  // 确保使用UTC时区
        return dateFormatter.date(from: self)
    }
} 
