import SwiftUI

struct KillMailYearListView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailYearListViewModel
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailYearListViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            // 年月选择和检索按钮
            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                } else {
                    HStack {
                        Text("选择年份")
                        Spacer()
                        Picker("", selection: $viewModel.selectedYear) {
                            Text("请选择年份").tag(nil as Int?)
                            ForEach(viewModel.yearSections.reversed(), id: \.self) { year in
                                Text(String(format: "%d年", year)).tag(year as Int?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    HStack {
                        Text("选择月份")
                        Spacer()
                        Picker("", selection: $viewModel.selectedMonth) {
                            Text("请选择月份").tag(nil as Int?)
                            if let year = viewModel.selectedYear {
                                ForEach(viewModel.getAvailableMonths(for: year), id: \.self) { month in
                                    Text(String(format: "%d月", month)).tag(month as Int?)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(viewModel.selectedYear == nil)
                    }
                    
                    Button {
                        Task {
                            await viewModel.fetchKillMails()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Text("开始检索")
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.selectedYear == nil || viewModel.selectedMonth == nil || viewModel.isLoading)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            // 击杀记录列表
            if !viewModel.killMails.isEmpty {
                Section {
                    ForEach(viewModel.killMails, id: \.killmail_id) { killmail in
                        KillMailCell(killmail: killmail)
                            .onAppear {
                                // 当显示最后一条记录时，加载更多
                                if killmail.killmail_id == viewModel.killMails.last?.killmail_id {
                                    Task {
                                        await viewModel.loadMoreKillMails()
                                    }
                                }
                            }
                    }
                    
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                } header: {
                    if let year = viewModel.selectedYear, let month = viewModel.selectedMonth {
                        Text("\(year)年\(month)月的击杀记录")
                    }
                }
            }
        }
        .navigationTitle("按月查看")
        .task {
            await viewModel.loadYears()
        }
    }
}

@MainActor
class KillMailYearListViewModel: ObservableObject {
    @Published private(set) var yearSections: [Int] = []
    @Published private(set) var killMails: [KillMailInfo] = []
    @Published var selectedYear: Int?
    @Published var selectedMonth: Int?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    private let characterId: Int
    private var currentPage = 1
    private var hasMorePages = true
    private var birthday: Date?
    private var existingKillMailIds: Set<Int> = []
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    func loadYears() async {
        isLoading = true
        defer { isLoading = false }
        
        // 获取角色生日
        let query = "SELECT birthday FROM character_info WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId])
        
        guard case .success(let rows) = result,
              let row = rows.first,
              let birthdayString = row["birthday"] as? String else {
            errorMessage = "无法获取角色生日信息"
            Logger.error("无法获取角色生日信息")
            return
        }
        
        // 解析生日字符串
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withTimeZone, .withDashSeparatorInDate, .withColonSeparatorInTime]
        
        guard let birthday = dateFormatter.date(from: birthdayString) else {
            errorMessage = "无法解析生日日期"
            Logger.error("无法解析生日日期: \(birthdayString)")
            return
        }
        
        self.birthday = birthday
        
        // 获取生日年份和当前年份
        let calendar = Calendar.current
        let birthdayYear = calendar.component(.year, from: birthday)
        let currentYear = calendar.component(.year, from: Date())
        
        // 生成年份列表
        yearSections = Array(birthdayYear...currentYear)
        
        Logger.debug("生成年份列表：从 \(birthdayYear) 到 \(currentYear)，共 \(yearSections.count) 个年份")
    }
    
    func getAvailableMonths(for year: Int) -> [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        guard let birthday = birthday else {
            return []
        }
        
        let birthdayYear = calendar.component(.year, from: birthday)
        let birthdayMonth = calendar.component(.month, from: birthday)
        
        // 如果是出生年份，从出生月份开始
        if year == birthdayYear {
            // 如果同时也是当前年份，取出生月份到当前月份
            if year == currentYear {
                return Array(birthdayMonth...currentMonth)
            }
            // 否则取出生月份到年底
            return Array(birthdayMonth...12)
        }
        
        // 如果是当前年份，只显示到当前月份
        if year == currentYear {
            return Array(1...currentMonth)
        }
        
        // 其他年份显示全年
        return Array(1...12)
    }
    
    func fetchKillMails() async {
        guard let year = selectedYear,
              let month = selectedMonth else {
            return
        }
        
        isLoading = true
        currentPage = 1
        hasMorePages = true
        killMails.removeAll()
        existingKillMailIds.removeAll()
        
        do {
            let newKillMails = try await ZKillMailsAPI.shared.fetchMonthlyKillMails(
                characterId: characterId,
                year: year,
                month: month,
                saveToDatabase: false
            )
            
            // 更新已存在的ID集合
            existingKillMailIds = Set(newKillMails.map { $0.killmail_id })
            killMails = newKillMails
            
            // 如果获取的记录数小于预期，说明没有更多页了
            hasMorePages = !newKillMails.isEmpty
            
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("获取击杀记录失败: \(error)")
        }
        
        isLoading = false
    }
    
    func loadMoreKillMails() async {
        guard !isLoadingMore,
              hasMorePages,
              let year = selectedYear,
              let month = selectedMonth else {
            return
        }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            let newKillMails = try await ZKillMailsAPI.shared.fetchMonthlyKillMails(
                characterId: characterId,
                year: year,
                month: month,
                saveToDatabase: false
            )
            
            // 过滤掉已经存在的记录
            let uniqueNewKillMails = newKillMails.filter { !existingKillMailIds.contains($0.killmail_id) }
            
            if uniqueNewKillMails.isEmpty {
                hasMorePages = false
            } else {
                // 更新已存在的ID集合
                existingKillMailIds.formUnion(uniqueNewKillMails.map { $0.killmail_id })
                killMails.append(contentsOf: uniqueNewKillMails)
            }
            
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("加载更多击杀记录失败: \(error)")
        }
        
        isLoadingMore = false
    }
} 
