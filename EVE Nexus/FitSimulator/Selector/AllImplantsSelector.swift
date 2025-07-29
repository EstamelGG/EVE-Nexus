import SwiftUI

// 全部植入体选择器
struct AllImplantsSelector: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var implantItems: [DatabaseListItem] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    // 存储植入体ID对应的槽位号
    @State private var implantSlotMapping: [Int: Int] = [:]
    
    // 存储多语言名称用于搜索
    @State private var multiLanguageNames: [Int: MultiLanguageNames] = [:]
    
    let onSelect: (DatabaseListItem, Int) -> Void // 选择回调，包含物品和槽位号

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .padding()
                } else {
                    List {
                        if filteredItems.isEmpty {
                            Section {
                                ContentUnavailableView {
                                    Label(
                                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                                        systemImage: "exclamationmark.triangle")
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .listRowBackground(Color.clear)
                            }
                        } else {
                            // 按槽位分组展示
                            ForEach(groupedBySlot.keys.sorted(), id: \.self) { slotNumber in
                                if let items = groupedBySlot[slotNumber] {
                                    Section(header: Text(String(format: NSLocalizedString("Implant_Slot_Num", comment: "植入体槽位 %d"), slotNumber))) {
                                        // 按typeID排序展示
                                        ForEach(items.sorted { $0.id < $1.id }) { item in
                                            ItemRowWithInfo(item: item, databaseManager: databaseManager) {
                                                if let actualSlotNumber = implantSlotMapping[item.id] {
                                                    onSelect(item, actualSlotNumber)
                                                }
                                                dismiss()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("Main_Search", comment: "搜索")
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Implant_Select_Implants", comment: "选择植入体"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .onAppear {
            loadAllImplants()
        }
    }
    
    // 根据搜索文本过滤物品
    private var filteredItems: [DatabaseListItem] {
        if searchText.isEmpty {
            return implantItems
        } else {
            return implantItems.filter { item in
                // 首先检查默认名称
                if item.name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // 然后检查多语言名称
                if let multiLangNames = multiLanguageNames[item.id] {
                    return multiLangNames.matchesSearchText(searchText)
                }
                
                return false
            }
        }
    }
    
    // 按槽位分组的过滤后物品
    private var groupedBySlot: [Int: [DatabaseListItem]] {
        var grouped: [Int: [DatabaseListItem]] = [:]
        
        for item in filteredItems {
            if let slotNumber = implantSlotMapping[item.id] {
                if grouped[slotNumber] == nil {
                    grouped[slotNumber] = []
                }
                grouped[slotNumber]?.append(item)
            }
        }
        
        return grouped
    }
    

    
    // 加载所有植入体物品
    private func loadAllImplants() {
        isLoading = true
        
        // 获取所有植入体信息和槽位号以及多语言名称
        let query = """
            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.group_name as groupName,
                   ta.value as slotNumber,
                   t.de_name, t.en_name, t.es_name, t.fr_name, 
                   t.ja_name, t.ko_name, t.ru_name, t.zh_name
            FROM types t
            JOIN typeAttributes ta ON t.type_id = ta.type_id
            WHERE ta.attribute_id = 331
            AND t.published = 1
            AND t.marketGroupID IS NOT NULL
            ORDER BY t.name
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            var items: [DatabaseListItem] = []
            var slotMapping: [Int: Int] = [:]
            var multiLangNames: [Int: MultiLanguageNames] = [:]
            
            for row in rows {
                if let id = row["id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String,
                   let categoryId = row["categoryID"] as? Int,
                   let slotNumber = row["slotNumber"] as? Double
                {
                    let iconFileName = (row["iconFileName"] as? String) ?? "not_found"
                    let published = (row["published"] as? Int) ?? 0
                    let groupID = row["groupID"] as? Int
                    let groupName = row["groupName"] as? String
                    let slotNum = Int(slotNumber)
                    
                    // 存储槽位映射
                    slotMapping[id] = slotNum
                    
                    // 存储多语言名称
                    let multiLangName = MultiLanguageNames(
                        deName: row["de_name"] as? String,
                        enName: row["en_name"] as? String,
                        esName: row["es_name"] as? String,
                        frName: row["fr_name"] as? String,
                        jaName: row["ja_name"] as? String,
                        koName: row["ko_name"] as? String,
                        ruName: row["ru_name"] as? String,
                        zhName: row["zh_name"] as? String
                    )
                    multiLangNames[id] = multiLangName
                    
                    let item = DatabaseListItem(
                        id: id,
                        name: name,
                        enName: enName,
                        iconFileName: iconFileName,
                        published: published == 1,
                        categoryID: categoryId,
                        groupID: groupID,
                        groupName: groupName,
                        pgNeed: nil,
                        cpuNeed: nil,
                        rigCost: nil,
                        emDamage: nil,
                        themDamage: nil,
                        kinDamage: nil,
                        expDamage: nil,
                        highSlot: nil,
                        midSlot: nil,
                        lowSlot: nil,
                        rigSlot: nil,
                        gunSlot: nil,
                        missSlot: nil,
                        metaGroupID: nil,
                        marketGroupID: nil,
                        navigationDestination: AnyView(EmptyView())
                    )
                    
                    items.append(item)
                }
            }
            
            implantItems = items
            implantSlotMapping = slotMapping
            multiLanguageNames = multiLangNames
            Logger.info("加载了 \(implantItems.count) 个植入体")
        } else {
            Logger.error("加载植入体信息失败")
        }
        
        isLoading = false
    }
} 

// 多语言名称数据结构
struct MultiLanguageNames {
    let deName: String?
    let enName: String?
    let esName: String?
    let frName: String?
    let jaName: String?
    let koName: String?
    let ruName: String?
    let zhName: String?
    
    func matchesSearchText(_ searchText: String) -> Bool {
        let names = [deName, enName, esName, frName, jaName, koName, ruName, zhName]
        return names.compactMap { $0 }.contains { name in
            name.localizedCaseInsensitiveContains(searchText)
        }
    }
} 
