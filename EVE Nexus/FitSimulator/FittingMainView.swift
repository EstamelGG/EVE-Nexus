import SwiftUI

// 配置来源类型
enum FittingSourceType {
    case local
    case online
}

// 本地配置视图模型
@MainActor
final class LocalFittingViewModel: ObservableObject {
    @Published private(set) var shipGroups: [String: [FittingListItem]] = [:]
    @Published private(set) var shipInfo: [Int: (name: String, iconFileName: String, zh_name: String?, en_name: String?)] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    func loadLocalFittings(forceRefresh: Bool = false) async {
        
        isLoading = true
        errorMessage = nil
        shipGroups = [:]
        shipInfo = [:]
        
        do {
            let localFittings = try FitConvert.loadAllLocalFittings()
            
            // 提取所有飞船类型ID
            let shipTypeIds = localFittings.map { $0.ship_type_id }
            
            if !shipTypeIds.isEmpty {
                // 获取飞船详细信息
                let shipQuery = """
                    SELECT type_id, name, zh_name, en_name, icon_filename, group_name 
                    FROM types 
                    WHERE type_id IN (\(shipTypeIds.map { String($0) }.joined(separator: ",")))
                """
                
                if case let .success(shipRows) = databaseManager.executeQuery(shipQuery) {
                    // 存储飞船信息
                    let shipInfoMap = shipRows.reduce(into: [Int: (name: String, iconFileName: String, zh_name: String?, en_name: String?)]()) { result, row in
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String,
                           let iconFileName = row["icon_filename"] as? String {
                            let zh_name = row["zh_name"] as? String
                            let en_name = row["en_name"] as? String
                            result[typeId] = (name: name, iconFileName: iconFileName, zh_name: zh_name, en_name: en_name)
                        }
                    }
                    
                    // 按组名分组配置数据
                    let groups = localFittings.reduce(into: [String: [FittingListItem]]()) { result, fitting in
                        if let shipRow = shipRows.first(where: { ($0["type_id"] as? Int) == fitting.ship_type_id }),
                           let groupName = shipRow["group_name"] as? String {
                            if result[groupName] == nil {
                                result[groupName] = []
                            }
                            result[groupName]?.append(FittingListItem(
                                fittingId: fitting.fitting_id,
                                name: fitting.name,
                                shipTypeId: fitting.ship_type_id
                            ))
                        }
                    }
                    
                    self.shipInfo = shipInfoMap
                    self.shipGroups = groups
                }
            }
        } catch {
            Logger.error("加载本地配置失败: \(error)")
            self.errorMessage = error.localizedDescription
        }
        
        self.isLoading = false
    }
    
    // 过滤后的分组数据
    func getFilteredShipGroups(searchText: String) -> [String: [FittingListItem]] {
        if searchText.isEmpty {
            return sortGroups(shipGroups)
        }
        return filterAndSortGroups(shipGroups, searchText: searchText)
    }
    
    // 辅助方法：排序分组
    private func sortGroups(_ groups: [String: [FittingListItem]]) -> [String: [FittingListItem]] {
        groups.mapValues { fittings in
            sortFittings(fittings)
        }
    }
    
    // 辅助方法：过滤并排序分组
    private func filterAndSortGroups(_ groups: [String: [FittingListItem]], searchText: String) -> [String: [FittingListItem]] {
        var filtered: [String: [FittingListItem]] = [:]
        for (groupName, fittings) in groups {
            let matchingFittings = filterFittings(fittings, searchText: searchText)
            if !matchingFittings.isEmpty {
                filtered[groupName] = sortFittings(matchingFittings)
            }
        }
        return filtered
    }
    
    // 辅助方法：过滤配置
    private func filterFittings(_ fittings: [FittingListItem], searchText: String) -> [FittingListItem] {
        fittings.filter { fitting in
            guard let shipInfo = shipInfo[fitting.shipTypeId] else {
                return false
            }
            
            let nameMatch = shipInfo.name.localizedCaseInsensitiveContains(searchText)
            let zhNameMatch = shipInfo.zh_name?.localizedCaseInsensitiveContains(searchText) ?? false
            let enNameMatch = shipInfo.en_name?.localizedCaseInsensitiveContains(searchText) ?? false
            let fittingNameMatch = fitting.name.localizedCaseInsensitiveContains(searchText)
            
            return nameMatch || zhNameMatch || enNameMatch || fittingNameMatch
        }
    }
    
    // 辅助方法：排序配置
    private func sortFittings(_ fittings: [FittingListItem]) -> [FittingListItem] {
        fittings.sorted { fitting1, fitting2 in
            let name1 = shipInfo[fitting1.shipTypeId]?.name ?? ""
            let name2 = shipInfo[fitting2.shipTypeId]?.name ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }
    
    // 添加删除配置的方法
    func deleteFitting(_ fitting: FittingListItem) {
        // 获取文件路径
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        let filePath = fittingsDirectory.appendingPathComponent("local_fitting_\(fitting.fittingId).json")
        
        // 删除文件
        do {
            try FileManager.default.removeItem(at: filePath)
            // 从内存中移除配置
            for (groupName, fittings) in shipGroups {
                if let index = fittings.firstIndex(where: { $0.fittingId == fitting.fittingId }) {
                    var updatedFittings = fittings
                    updatedFittings.remove(at: index)
                    if updatedFittings.isEmpty {
                        shipGroups.removeValue(forKey: groupName)
                    } else {
                        shipGroups[groupName] = updatedFittings
                    }
                    break
                }
            }
        } catch {
            errorMessage = NSLocalizedString("Error_Delete_Fitting", comment: "")
        }
    }
}

// 在线配置视图模型
@MainActor
final class OnlineFittingViewModel: ObservableObject {
    @Published private(set) var shipGroups: [String: [FittingListItem]] = [:]
    @Published private(set) var shipInfo: [Int: (name: String, iconFileName: String, zh_name: String?, en_name: String?)] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var initialLoadDone = false
    private var loadingTask: Task<Void, Never>?
    
    let characterId: Int?
    let databaseManager: DatabaseManager
    
    init(characterId: Int?, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        
        // 在初始化时立即开始加载数据
        if characterId != nil {
            Task {
                await loadOnlineFittings()
            }
        }
    }
    
    deinit {
        loadingTask?.cancel()
    }
    
    func loadOnlineFittings(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone && !forceRefresh {
            return
        }
        
        // 如果没有角色ID，则直接返回
        guard let characterId = characterId else {
            Logger.error("尝试加载在线配置但没有characterId")
            return
        }
        
        // 取消之前的加载任务
        loadingTask?.cancel()
        
        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            shipGroups = [:]
            shipInfo = [:]
            
            do {
                // 获取在线配置数据
                let fittings = try await CharacterFittingAPI.getCharacterFittings(characterID: characterId, forceRefresh: forceRefresh)
                
                if Task.isCancelled {
                    Logger.debug("配置加载任务被取消")
                    return
                }
                
                // 提取所有飞船类型ID
                let shipTypeIds = fittings.map { $0.ship_type_id }
                
                if !shipTypeIds.isEmpty {
                    // 获取飞船详细信息
                    let shipQuery = """
                        SELECT type_id, name, zh_name, en_name, icon_filename, group_name 
                        FROM types 
                        WHERE type_id IN (\(shipTypeIds.map { String($0) }.joined(separator: ",")))
                    """
                    
                    if case let .success(shipRows) = databaseManager.executeQuery(shipQuery) {
                        // 存储飞船信息
                        let shipInfoMap = shipRows.reduce(into: [Int: (name: String, iconFileName: String, zh_name: String?, en_name: String?)]()) { result, row in
                            if let typeId = row["type_id"] as? Int,
                               let name = row["name"] as? String,
                               let iconFileName = row["icon_filename"] as? String {
                                let zh_name = row["zh_name"] as? String
                                let en_name = row["en_name"] as? String
                                result[typeId] = (name: name, iconFileName: iconFileName, zh_name: zh_name, en_name: en_name)
                            }
                        }
                        
                        if Task.isCancelled {
                            Logger.debug("飞船信息处理任务被取消")
                            return
                        }
                        
                        // 按组名分组配置数据
                        let groups = fittings.reduce(into: [String: [FittingListItem]]()) { result, fitting in
                            if let shipRow = shipRows.first(where: { ($0["type_id"] as? Int) == fitting.ship_type_id }),
                               let groupName = shipRow["group_name"] as? String {
                                if result[groupName] == nil {
                                    result[groupName] = []
                                }
                                result[groupName]?.append(FittingListItem(
                                    fittingId: fitting.fitting_id,
                                    name: fitting.name,
                                    shipTypeId: fitting.ship_type_id
                                ))
                            }
                        }
                        
                        if Task.isCancelled {
                            Logger.debug("配置分组任务被取消")
                            return
                        }
                        
                        self.shipInfo = shipInfoMap
                        self.shipGroups = groups
                    }
                }
                
                if !Task.isCancelled {
                    self.initialLoadDone = true
                }
            } catch {
                if !Task.isCancelled {
                    Logger.error("加载配置数据失败: \(error)")
                    self.errorMessage = error.localizedDescription
                } else {
                    Logger.debug("配置加载任务被取消")
                }
            }
            
            if !Task.isCancelled {
                self.isLoading = false
            }
        }
        
        // 等待任务完成
        await loadingTask?.value
    }
    
    // 过滤后的分组数据
    func getFilteredShipGroups(searchText: String) -> [String: [FittingListItem]] {
        if searchText.isEmpty {
            return sortGroups(shipGroups)
        }
        return filterAndSortGroups(shipGroups, searchText: searchText)
    }
    
    // 辅助方法：排序分组
    private func sortGroups(_ groups: [String: [FittingListItem]]) -> [String: [FittingListItem]] {
        groups.mapValues { fittings in
            sortFittings(fittings)
        }
    }
    
    // 辅助方法：过滤并排序分组
    private func filterAndSortGroups(_ groups: [String: [FittingListItem]], searchText: String) -> [String: [FittingListItem]] {
        var filtered: [String: [FittingListItem]] = [:]
        for (groupName, fittings) in groups {
            let matchingFittings = filterFittings(fittings, searchText: searchText)
            if !matchingFittings.isEmpty {
                filtered[groupName] = sortFittings(matchingFittings)
            }
        }
        return filtered
    }
    
    // 辅助方法：过滤配置
    private func filterFittings(_ fittings: [FittingListItem], searchText: String) -> [FittingListItem] {
        fittings.filter { fitting in
            guard let shipInfo = shipInfo[fitting.shipTypeId] else {
                return false
            }
            
            let nameMatch = shipInfo.name.localizedCaseInsensitiveContains(searchText)
            let zhNameMatch = shipInfo.zh_name?.localizedCaseInsensitiveContains(searchText) ?? false
            let enNameMatch = shipInfo.en_name?.localizedCaseInsensitiveContains(searchText) ?? false
            let fittingNameMatch = fitting.name.localizedCaseInsensitiveContains(searchText)
            
            return nameMatch || zhNameMatch || enNameMatch || fittingNameMatch
        }
    }
    
    // 辅助方法：排序配置
    private func sortFittings(_ fittings: [FittingListItem]) -> [FittingListItem] {
        fittings.sorted { fitting1, fitting2 in
            let name1 = shipInfo[fitting1.shipTypeId]?.name ?? ""
            let name2 = shipInfo[fitting2.shipTypeId]?.name ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }
}

// 配置列表视图
struct FittingMainView: View {
    @State private var sourceType: FittingSourceType = .local
    @State private var searchText = ""
    @State private var showShipSelector = false
    @State private var selectedShip: DatabaseListItem? = nil
    @State private var navigateToShipFitting = false
    @State private var navigateToExistingFitting = false
    @State private var selectedFittingId: Int? = nil
    @State private var selectedFittingSourceType: FittingSourceType = .local
    @State private var selectedOnlineFitting: CharacterFitting? = nil
    
    // 使用两个独立的视图模型
    @StateObject private var localViewModel: LocalFittingViewModel
    @StateObject private var onlineViewModel: OnlineFittingViewModel
    
    init(characterId: Int? = nil, databaseManager: DatabaseManager) {
        let localVM = LocalFittingViewModel(databaseManager: databaseManager)
        let onlineVM = OnlineFittingViewModel(characterId: characterId, databaseManager: databaseManager)
        _localViewModel = StateObject(wrappedValue: localVM)
        _onlineViewModel = StateObject(wrappedValue: onlineVM)
    }
    
    // 添加一个计算属性来获取过滤后的分组数据
    private var filteredGroups: [String: [FittingListItem]] {
        switch sourceType {
        case .local:
            return localViewModel.getFilteredShipGroups(searchText: searchText)
        case .online:
            return onlineViewModel.getFilteredShipGroups(searchText: searchText)
        }
    }
    
    // 添加一个计算属性检查是否正在加载
    private var isLoading: Bool {
        switch sourceType {
        case .local:
            return localViewModel.isLoading
        case .online:
            return onlineViewModel.isLoading
        }
    }
    
    // 添加一个计算属性获取当前视图模型的飞船信息
    private var currentShipInfo: [Int: (name: String, iconFileName: String, zh_name: String?, en_name: String?)] {
        switch sourceType {
        case .local:
            return localViewModel.shipInfo
        case .online:
            return onlineViewModel.shipInfo
        }
    }
    
    // 添加一个视图来显示空状态
    private var emptyStateView: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: sourceType == .local ? "archivebox" : "network")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text(sourceType == .local ? 
                        NSLocalizedString("Fitting_No_Local_Fitting", comment: "") :
                        NSLocalizedString("Fitting_Online_No_Data", comment: ""))
                        .foregroundColor(.gray)
                }
                .padding()
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }
    
    // 添加一个视图来显示配置项
    private func fittingItemView(fitting: FittingListItem, shipInfo: (name: String, iconFileName: String, zh_name: String?, en_name: String?)) -> some View {
        Button(action: {
            selectedFittingId = fitting.fittingId
            selectedFittingSourceType = sourceType
            
            // 如果是在线配置，需要获取完整的配置数据
            if sourceType == .online {
                Task {
                    do {
                        let onlineFittings = try await CharacterFittingAPI.getCharacterFittings(characterID: onlineViewModel.characterId ?? 0)
                        if let onlineFitting = onlineFittings.first(where: { $0.fitting_id == fitting.fittingId }) {
                            selectedOnlineFitting = onlineFitting
                            navigateToExistingFitting = true
                        }
                    } catch {
                        Logger.error("获取在线配置详情失败: \(error)")
                    }
                }
            } else {
                // 本地配置直接导航
                navigateToExistingFitting = true
            }
        }) {
            HStack(spacing: 4) {
                Image(uiImage: IconManager.shared.loadUIImage(for: shipInfo.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(shipInfo.name)
                        .foregroundColor(.primary)
                    Text(fitting.name.isEmpty ? 
                        NSLocalizedString("Unnamed", comment: "") : 
                        fitting.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                List {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                List {
                    if filteredGroups.isEmpty {
                        emptyStateView
                    } else {
                        // 显示无搜索结果提示
                        if filteredGroups.isEmpty && !searchText.isEmpty {
                            NoDataSection(icon: "magnifyingglass")
                        } else {
                            // 配置列表部分
                            ForEach(filteredGroups.keys.sorted(), id: \.self) { groupName in
                                Section {
                                    if let fittings = filteredGroups[groupName] {
                                        ForEach(fittings, id: \.fittingId) { fitting in
                                            if let shipInfo = currentShipInfo[fitting.shipTypeId] {
                                                fittingItemView(fitting: fitting, shipInfo: shipInfo)
                                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                        if sourceType == .local {
                                                            Button(role: .destructive) {
                                                                localViewModel.deleteFitting(fitting)
                                                            } label: {
                                                                Label(NSLocalizedString("Main_Setting_Delete", comment: ""), systemImage: "trash")
                                                            }
                                                        }
                                                    }
                                            }
                                        }
                                    }
                                } header: {
                                    Text(groupName)
                                        .fontWeight(.semibold)
                                        .font(.system(size: 18))
                                        .foregroundColor(.primary)
                                        .textCase(.none)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    switch sourceType {
                    case .local:
                        await localViewModel.loadLocalFittings(forceRefresh: true)
                    case .online:
                        await onlineViewModel.loadOnlineFittings(forceRefresh: true)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Fitting", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if sourceType == .local {
                    Button(action: {
                        showShipSelector = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            
            // 添加Picker到toolbar中
            ToolbarItem(placement: .principal) {
                Picker("Fitting Source", selection: $sourceType) {
                    Text(NSLocalizedString("Fitting_Local", comment: ""))
                        .tag(FittingSourceType.local)
                    Text(NSLocalizedString("Fitting_Online", comment: ""))
                        .tag(FittingSourceType.online)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(onlineViewModel.characterId == nil)
            }
        }
        .searchable(text: $searchText, 
                   placement: .navigationBarDrawer(displayMode: .always),
                   prompt: NSLocalizedString("Main_Search_Placeholder", comment: "搜索飞船名称..."))
        .sheet(isPresented: $showShipSelector) {
            NavigationStack {
                FittingShipSelectorView(databaseManager: localViewModel.databaseManager) { selectedItem in
                    selectedShip = selectedItem
                    showShipSelector = false
                    navigateToShipFitting = true
                }
            }
        }
        .navigationDestination(isPresented: $navigateToShipFitting) {
            if let ship = selectedShip {
                ShipFittingView(
                    shipTypeId: ship.id,
                    shipInfo: (name: ship.name, iconFileName: ship.iconFileName),
                    databaseManager: localViewModel.databaseManager
                )
            }
        }
        .navigationDestination(isPresented: $navigateToExistingFitting) {
            if selectedFittingSourceType == .local, let fittingId = selectedFittingId {
                // 本地配置
                ShipFittingView(
                    fittingId: fittingId,
                    databaseManager: localViewModel.databaseManager
                )
            } else if let onlineFitting = selectedOnlineFitting {
                // 在线配置
                ShipFittingView(
                    onlineFitting: onlineFitting,
                    databaseManager: onlineViewModel.databaseManager
                )
            }
        }
        .onChange(of: sourceType) { oldValue, newValue in
            // 如果没有角色但尝试切换到线上，切换回本地
            if newValue == .online && onlineViewModel.characterId == nil {
                sourceType = .local
                return
            }
            
            // 当切换配置来源类型时，加载对应的配置
            Task {
                switch newValue {
                case .local:
                    await localViewModel.loadLocalFittings(forceRefresh: true)
                case .online:
                    await onlineViewModel.loadOnlineFittings()
                }
            }
        }
        .task {
            // 在视图加载时立即刷新配置列表
            switch sourceType {
            case .local:
                await localViewModel.loadLocalFittings(forceRefresh: true)
            case .online:
                await onlineViewModel.loadOnlineFittings()
            }
        }
        .onAppear {
            // 在视图出现时加载当前类型的配置
            Task {
                switch sourceType {
                case .local:
                    await localViewModel.loadLocalFittings(forceRefresh: true)
                case .online:
                    await onlineViewModel.loadOnlineFittings()
                }
            }
        }
    }
}

// 配置列表项模型
struct FittingListItem: Identifiable {
    let fittingId: Int
    let name: String
    let shipTypeId: Int
    
    var id: Int { fittingId }
}
