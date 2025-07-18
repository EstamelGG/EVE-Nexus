import SwiftUI

// 删除缓存项，包含删除时间信息
struct DeletedFittingItem {
    let fittingId: Int
    let deletedAt: Date
    
    /// 检查是否已过期（超过5分钟）
    var isExpired: Bool {
        Date().timeIntervalSince(deletedAt) > 300 // 5分钟 = 300秒
    }
}

// 删除缓存管理器 - 单例模式，在应用生命周期中持久化
@MainActor
final class FittingDeletionCacheManager: ObservableObject {
    static let shared = FittingDeletionCacheManager()
    
    // 存储已删除配置的信息，按角色ID分组
    private var deletedFittingItems: [Int: [DeletedFittingItem]] = [:]
    
    private init() {}
    
    /// 添加已删除的配置ID
    func addDeletedFitting(fittingId: Int, characterId: Int) {
        let deletedItem = DeletedFittingItem(fittingId: fittingId, deletedAt: Date())
        
        if deletedFittingItems[characterId] == nil {
            deletedFittingItems[characterId] = []
        }
        
        // 移除已存在的相同ID（如果有的话）
        deletedFittingItems[characterId]?.removeAll { $0.fittingId == fittingId }
        
        // 添加新的删除记录
        deletedFittingItems[characterId]?.append(deletedItem)
    }
    
    /// 检查配置是否已被删除且未过期
    func isDeleted(fittingId: Int, characterId: Int) -> Bool {
        guard let items = deletedFittingItems[characterId] else {
            return false
        }
        
        // 先清理过期项
        cleanExpiredItems(for: characterId)
        
        // 查找匹配的删除记录，且未过期
        return items.contains { $0.fittingId == fittingId && !$0.isExpired }
    }
    
    /// 清理指定角色的过期缓存项
    private func cleanExpiredItems(for characterId: Int) {
        deletedFittingItems[characterId]?.removeAll { $0.isExpired }
        
        // 如果数组为空，移除整个角色的记录
        if deletedFittingItems[characterId]?.isEmpty == true {
            deletedFittingItems[characterId] = nil
        }
    }
    
    /// 获取缓存统计信息（用于调试）
    func getCacheStats() -> [Int: Int] {
        var stats: [Int: Int] = [:]
        for (characterId, _) in deletedFittingItems {
            // 先清理过期项
            cleanExpiredItems(for: characterId)
            
            // 获取清理后的有效项数量
            if let items = deletedFittingItems[characterId], !items.isEmpty {
                stats[characterId] = items.count
            }
        }
        return stats
    }
    
    /// 打印缓存统计信息（用于调试）
    func printCacheStats() {
        let stats = getCacheStats()
        if stats.isEmpty {
            Logger.debug("删除缓存为空")
        } else {
            for (characterId, count) in stats {
                Logger.debug("角色 \(characterId) 有 \(count) 个有效的删除缓存项")
            }
        }
    }
    

}

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
                        
                        // 按组名分组配置数据，过滤掉已删除的配置
                        let groups = fittings.reduce(into: [String: [FittingListItem]]()) { result, fitting in
                            // 跳过已删除的配置
                            if FittingDeletionCacheManager.shared.isDeleted(fittingId: fitting.fitting_id, characterId: characterId) {
                                Logger.debug("跳过已删除的配置 ID: \(fitting.fitting_id)")
                                return
                            }
                            
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
                        
                        // 打印缓存统计信息（调试用）
                        FittingDeletionCacheManager.shared.printCacheStats()
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
    
    /// 删除在线装配配置
    func deleteFitting(_ fitting: FittingListItem) {
        guard let characterId = characterId else {
            Logger.error("尝试删除在线配置但没有characterId")
            return
        }
        
        // 异步执行删除请求
        Task {
            do {
                // 先调用远程API执行真正的删除操作
                try await CharacterFittingAPI.deleteCharacterFitting(
                    characterID: characterId,
                    fittingID: fitting.fittingId
                )
                
                // 删除成功后，添加到删除标记容器中
                FittingDeletionCacheManager.shared.addDeletedFitting(fittingId: fitting.fittingId, characterId: characterId)
                
                // 立即刷新界面显示
                refreshDisplayedFittings()
                
                Logger.info("成功删除在线装配配置 - ID: \(fitting.fittingId)，已添加到5分钟删除缓存")
            } catch {
                Logger.error("删除在线装配配置失败: \(error)")
                // 删除失败时不添加删除标记，保持界面状态不变
            }
        }
    }
    
    /// 刷新显示的配置列表（基于删除标记过滤）
    func refreshDisplayedFittings() {
        guard let characterId = characterId else { return }
        
        // 重新构建shipGroups，过滤掉已删除的配置
        var newShipGroups: [String: [FittingListItem]] = [:]
        
        for (groupName, fittings) in shipGroups {
            let filteredFittings = fittings.filter { !FittingDeletionCacheManager.shared.isDeleted(fittingId: $0.fittingId, characterId: characterId) }
            if !filteredFittings.isEmpty {
                newShipGroups[groupName] = filteredFittings
            }
        }
        
        shipGroups = newShipGroups
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
    
    // 导入错误状态管理
    @State private var showingImportErrorAlert = false
    @State private var importErrorMessage = ""
    
    // 飞船选择状态管理
    @State private var showingShipSelectionAlert = false
    @State private var shipSelectionOptions: [(typeId: Int, name: String, iconFileName: String?)] = []
    @State private var pendingEftText = ""
    
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
    
    // 处理从剪贴板导入配置
    private func importFromClipboard() {
        Logger.info("从剪贴板导入配置功能被触发")
        
        // 获取剪贴板内容
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            Logger.warning("剪贴板为空或无文本内容")
            return
        }
        
        Logger.info("获取到剪贴板内容，长度: \(clipboardText.count) 字符")
        
        // 尝试解析EFT格式
        do {
            let localFitting = try FitConvert.eftToLocalFitting(
                eftText: clipboardText,
                databaseManager: localViewModel.databaseManager
            )
            
            Logger.info("EFT格式解析成功 - 飞船ID: \(localFitting.ship_type_id), 配置名称: \(localFitting.name)")
            
            // 保存到本地
            try FitConvert.saveLocalFitting(localFitting)
            Logger.info("配置已保存到本地，ID: \(localFitting.fitting_id)")
            
            // 刷新本地配置列表
            Task {
                await localViewModel.loadLocalFittings(forceRefresh: true)
                
                // 在主线程上进行导航
                await MainActor.run {
                    // 准备导航到装配页面
                    selectedFittingId = localFitting.fitting_id
                    selectedFittingSourceType = .local
                    navigateToExistingFitting = true
                    
                    Logger.info("导入成功，直接打开配置详情页面，ID: \(localFitting.fitting_id)")
                }
            }
            
        } catch let error as NSError {
            Logger.error("从剪贴板导入配置失败: \(error.localizedDescription)")
            
            // 检查是否是多个同名飞船的错误
            if error.code == 7, 
               let shipOptions = error.userInfo["shipOptions"] as? [(typeId: Int, name: String, iconFileName: String?)] {
                // 显示飞船选择弹窗
                shipSelectionOptions = shipOptions
                pendingEftText = clipboardText
                showingShipSelectionAlert = true
                Logger.info("检测到多个同名飞船，显示选择弹窗，选项数量: \(shipOptions.count)")
            } else {
                // 显示普通错误提示
                importErrorMessage = String(format: NSLocalizedString("Fitting_Import_Failed_Message", comment: "导入失败"), error.localizedDescription)
                showingImportErrorAlert = true
            }
        }
    }
    
    // 处理用户选择的飞船并重新导入
    private func importWithSelectedShip(selectedShipTypeId: Int) {
        Logger.info("用户选择了飞船ID: \(selectedShipTypeId)，重新导入配置")
        
        do {
            let localFitting = try FitConvert.eftToLocalFitting(
                eftText: pendingEftText,
                databaseManager: localViewModel.databaseManager,
                selectedShipTypeId: selectedShipTypeId
            )
            
            Logger.info("使用选定飞船重新解析成功 - 飞船ID: \(localFitting.ship_type_id), 配置名称: \(localFitting.name)")
            
            // 保存到本地
            try FitConvert.saveLocalFitting(localFitting)
            Logger.info("配置已保存到本地，ID: \(localFitting.fitting_id)")
            
            // 刷新本地配置列表
            Task {
                await localViewModel.loadLocalFittings(forceRefresh: true)
                
                // 在主线程上进行导航
                await MainActor.run {
                    // 准备导航到装配页面
                    selectedFittingId = localFitting.fitting_id
                    selectedFittingSourceType = .local
                    navigateToExistingFitting = true
                    
                    Logger.info("导入成功，直接打开配置详情页面，ID: \(localFitting.fitting_id)")
                }
            }
            
        } catch {
            Logger.error("使用选定飞船重新导入失败: \(error.localizedDescription)")
            
            // 显示错误提示
            importErrorMessage = String(format: NSLocalizedString("Fitting_Import_Failed_Message", comment: "导入失败"), error.localizedDescription)
            showingImportErrorAlert = true
        }
        
        // 清理状态
        pendingEftText = ""
        shipSelectionOptions = []
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
                
                Spacer()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 只为在线配置添加删除按钮
            if sourceType == .online {
                Button(role: .destructive) {
                    onlineViewModel.deleteFitting(fitting)
                } label: {
                    Label(NSLocalizedString("Delete", comment: "删除"), systemImage: "trash")
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
                    HStack {
                        Button(action: {
                            importFromClipboard()
                        }) {
                            Image(systemName: "doc.on.clipboard")
                        }
                        
                        Button(action: {
                            showShipSelector = true
                        }) {
                            Image(systemName: "plus")
                        }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshOnlineFittings"))) { notification in
            // 当收到刷新在线配置的通知时，刷新在线配置列表
            if let userInfo = notification.userInfo,
               let notificationCharacterId = userInfo["characterId"] as? Int,
               notificationCharacterId == onlineViewModel.characterId {
                
                Logger.info("收到刷新在线配置通知，开始刷新配置列表")
                
                // 只有当前显示在线配置时才刷新
                if sourceType == .online {
                    // 使用OnlineFittingViewModel的刷新方法
                    onlineViewModel.refreshDisplayedFittings()
                }
            }
        }
        .alert(NSLocalizedString("Fitting_Import_Failed_Title", comment: "导入失败"), isPresented: $showingImportErrorAlert) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) { }
        } message: {
            Text(importErrorMessage)
        }
        .sheet(item: Binding<ShipSelectionItem?>(
            get: { showingShipSelectionAlert ? ShipSelectionItem(options: shipSelectionOptions, eftText: pendingEftText) : nil },
            set: { _ in 
                showingShipSelectionAlert = false
                pendingEftText = ""
                shipSelectionOptions = []
            }
        )) { item in
            ShipSelectionView(
                shipOptions: item.options,
                onShipSelected: { selectedShipTypeId in
                    showingShipSelectionAlert = false
                    importWithSelectedShip(selectedShipTypeId: selectedShipTypeId)
                },
                onCancel: {
                    showingShipSelectionAlert = false
                    pendingEftText = ""
                    shipSelectionOptions = []
                }
            )
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

// 飞船选择项模型
struct ShipSelectionItem: Identifiable {
    let id = UUID()
    let options: [(typeId: Int, name: String, iconFileName: String?)]
    let eftText: String
}

// 飞船选择弹窗视图
struct ShipSelectionView: View {
    let shipOptions: [(typeId: Int, name: String, iconFileName: String?)]
    let onShipSelected: (Int) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(shipOptions, id: \.typeId) { option in
                        HStack(spacing: 12) {
                            // 飞船图标
                            Image(uiImage: IconManager.shared.loadUIImage(for: option.iconFileName ?? ""))
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("ID: \(option.typeId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onShipSelected(option.typeId)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Fitting_Import_Multiple_Ships_Header", comment: "选择飞船"))
                        .font(.headline)
                }
            }
            .navigationTitle(NSLocalizedString("Fitting_Import_Ship_Selection_Title", comment: "选择飞船"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Common_Cancel", comment: "取消")) {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
