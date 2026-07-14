import Foundation
import SwiftUI

struct RegionSearchView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var regions: [(Int, String, String, String)] = [] // ID, 名称, 英文名, 中文名
    @State private var isLoading = true
    @Binding var selectedRegionID: Int?
    @Binding var selectedRegionName: String?
    @State private var isSearchActive = false
    @State private var sectionedRegions: [String: [(Int, String, String, String)]] = [:]
    @State private var sectionTitles: [String] = []

    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Loading_Regions", comment: "加载星域中..."))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                ZStack(alignment: .trailing) {
                    List {
                        // 添加"所有星域"选项
                        Section {
                            Button(action: {
                                selectedRegionID = nil
                                selectedRegionName = nil
                                dismiss()
                            }) {
                                HStack {
                                    Text(NSLocalizedString("Region_All", comment: "所有星域"))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedRegionID == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }

                        // 按首字母分组显示星域列表
                        ForEach(sectionTitles, id: \.self) { sectionTitle in
                            if let regionsInSection = sectionedRegions[sectionTitle],
                               !regionsInSection.isEmpty
                            {
                                Section(header: Text(sectionTitle).id(sectionTitle)) {
                                    ForEach(regionsInSection, id: \.0) {
                                        regionID, regionName, _, _ in
                                        Button(action: {
                                            selectedRegionID = regionID
                                            selectedRegionName = regionName
                                            dismiss()
                                        }) {
                                            HStack {
                                                Text(regionName)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if selectedRegionID == regionID {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Region_Search_Placeholder", comment: "搜索星域...")
        )
        .onChange(of: searchText) { _, _ in
            updateSections()
        }
        .onChange(of: isSearchActive) { _, _ in
            // 当搜索状态改变时，也需要更新分组
            updateSections()
        }
        .navigationTitle(NSLocalizedString("Region_Search_Title", comment: "选择星域"))
        .onAppear {
            loadRegions()
        }
    }

    /// 更新分组数据
    private func updateSections() {
        var filteredData: [(Int, String, String, String)] = regions

        // 如果有搜索文本，过滤数据
        if !searchText.isEmpty {
            filteredData = regions.filter { region in
                SDEMemoryStore.regionNames[region.0]?.matchesSearch(searchText) == true
            }
        }

        // 按首字母分组
        let grouped = Dictionary(grouping: filteredData) { region -> String in
            // 获取首字母（包括处理中文拼音）
            let name = region.1
            if let firstChar = name.first {
                return getFirstLetter(of: String(firstChar))
            }
            return "#"
        }

        sectionedRegions = grouped
        sectionTitles = grouped.keys.sorted()

        // 对每个组内的数据进行排序
        for (key, _) in sectionedRegions {
            sectionedRegions[key]?.sort { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        }
    }

    /// 获取字符的首字母（包括中文拼音）
    private func getFirstLetter(of char: String) -> String {
        // 转换为大写
        let uppercaseChar = char.uppercased()

        // 判断是否为英文字母
        if uppercaseChar >= "A" && uppercaseChar <= "Z" {
            return uppercaseChar
        }

        // 中文字符转拼音
        let pinyin = NSMutableString(string: char) as CFMutableString
        CFStringTransform(pinyin, nil, kCFStringTransformToLatin, false)
        CFStringTransform(pinyin, nil, kCFStringTransformStripDiacritics, false)

        if let firstPinyinChar = String(pinyin as String).first {
            let letter = String(firstPinyinChar).uppercased()
            if letter >= "A" && letter <= "Z" {
                return letter
            }
        }

        // 其他字符
        return "#"
    }

    /// 加载所有星域
    private func loadRegions() {
        isLoading = true

        regions = SDEMemoryStore.regionNames.compactMap { id, text in
            guard id < 11_000_000 else { return nil }
            let name = text.resolved()
            guard !name.isEmpty else { return nil }
            return (id, name, text.en, text.zh)
        }

        updateSections()
        isLoading = false
    }
}

/// 星系搜索视图
struct SolarSystemSearchView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var solarSystems: [(Int, String, String, String, Double)] = [] // ID, 名称, 英文名, 中文名, 安全等级
    @State private var isLoading = true
    @Binding var selectedSolarSystemID: Int?
    @Binding var selectedSolarSystemName: String?
    @State private var isSearchActive = false
    var regionID: Int?

    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Loading_Systems", comment: "加载星系中..."))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                List {
                    // 添加"所有星系"选项
                    Button(action: {
                        selectedSolarSystemID = nil
                        selectedSolarSystemName = nil
                        dismiss()
                    }) {
                        HStack {
                            Text(
                                regionID == nil
                                    ? NSLocalizedString("System_All", comment: "所有星系")
                                    : NSLocalizedString("System_All_In_Region", comment: "该星域内所有星系")
                            )
                            .foregroundColor(.primary)
                            Spacer()
                            if selectedSolarSystemID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // 过滤并显示星系列表
                    ForEach(filteredSystems, id: \.0) {
                        systemID, systemName, _, _, security in
                        Button(action: {
                            selectedSolarSystemID = systemID
                            selectedSolarSystemName = systemName
                            dismiss()
                        }) {
                            HStack {
                                // 显示安全等级
                                Text(String(format: "%.1f", security))
                                    .foregroundColor(getSecurityColor(security))
                                    .font(.system(.body, design: .monospaced))
                                Text(systemName)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedSolarSystemID == systemID {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("System_Search_Placeholder", comment: "搜索星系...")
        )
        .navigationTitle(NSLocalizedString("System_Search_Title", comment: "选择星系"))
        .onAppear {
            loadSolarSystems()
        }
    }

    /// 过滤后的星系列表
    private var filteredSystems: [(Int, String, String, String, Double)] {
        var result: [(Int, String, String, String, Double)]
        if searchText.isEmpty {
            result = solarSystems
        } else {
            result = solarSystems.filter { system in
                SDEMemoryStore.solarSystemNames[system.0]?.matchesSearch(searchText) == true
            }
        }
        return result.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    /// 加载星系
    private func loadSolarSystems() {
        isLoading = true

        var query = """
            SELECT solarsystem_id, system_security
            FROM universe
            WHERE region_id < 11000000
        """

        var parameters: [Any] = []

        if let regionID = regionID {
            query += " AND region_id = ?"
            parameters.append(regionID)
        }

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
            solarSystems = rows.compactMap { row in
                guard let systemID = row["solarsystem_id"] as? Int,
                      let names = SDEMemoryStore.solarSystemNames[systemID],
                      let security = row["system_security"] as? Double
                else { return nil }
                let name = names.resolved()
                guard !name.isEmpty else { return nil }
                return (systemID, name, names.en, names.zh, security)
            }
            solarSystems.sort { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        }

        isLoading = false
    }
}
