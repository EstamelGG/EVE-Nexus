//
//  ContentView.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/11/28.
//

import SwiftUI
import SwiftData

// 定义树形结构的节点
class TableRowNode: Identifiable, ObservableObject {
    var id = UUID()
    var title: String
    var iconName: String
    var note: String?
    var destination: AnyView? // 增加目标视图属性
    
    init(title: String, iconName: String, note: String? = nil, destination: AnyView? = nil) {
        self.title = title
        self.iconName = iconName
        self.note = note
        self.destination = destination
    }
}

class TableNode: Identifiable, ObservableObject {
    var id = UUID()
    var title: String
    @Published var rows: [TableRowNode]
    
    init(title: String, rows: [TableRowNode]) {
        self.title = title
        self.rows = rows
    }
}

struct ContentView: View {
    @State private var tables: [TableNode] = [
        TableNode(
            title: "Character",
            rows: [
                TableRowNode(
                    title: "Character Sheet",
                    iconName: "charactersheet",
                    note: "This is your character's information."
                ),
                TableRowNode(
                    title: "Jump Clones",
                    iconName: "jumpclones",
                    note: "Manage your jump clones."
                ),
                TableRowNode(
                    title: "Skills",
                    iconName: "skills",
                    note: "Skills progression."
                ),
                TableRowNode(
                    title: "EVE Mail",
                    iconName: "evemail"
                ),
                TableRowNode(
                    title: "Calendar",
                    iconName: "calendar"
                ),
                TableRowNode(
                    title: "Wealth",
                    iconName: "Folder",
                    note: "your money"
                ),
                TableRowNode(
                    title: "Loyalty Points",
                    iconName: "lpstore"
                )
            ]
        ),
        TableNode(
            title: "Databases",
            rows: [
                TableRowNode(
                    title: "Database",
                    iconName: "items"
                ),
                TableRowNode(
                    title: "Market",
                    iconName: "market"
                ),
                TableRowNode(
                    title: "NPC",
                    iconName: "criminal"
                ),
                TableRowNode(
                    title: "Wormholes",
                    iconName: "terminate"
                ),
                TableRowNode(
                    title: "Incursions",
                    iconName: "incursions"
                )
            ]
        ),
        TableNode(
            title: "Business",
            rows: [
                TableRowNode(
                    title: "Assets",
                    iconName: "assets"
                ),
                TableRowNode(
                    title: "Market Orders",
                    iconName: "marketdeliveries"
                ),
                TableRowNode(
                    title: "Contracts",
                    iconName: "contracts"
                ),
                TableRowNode(
                    title: "Market Transactions",
                    iconName: "journal"
                ),
                TableRowNode(
                    title: "Wallet Journal",
                    iconName: "wallet"
                ),
                TableRowNode(
                    title: "Industry Jobs",
                    iconName: "industry"
                )
            ]
        ),
        TableNode(
            title: "Other",
            rows: [
                TableRowNode(
                    title: "Setting",
                    iconName: "Settings",
                    destination: AnyView(SettingView())
                ),
                TableRowNode(
                    title: "About",
                    iconName: "info",
                    destination: AnyView(AboutView())
                )
            ]
        )
    ]
    
    // 使用 @AppStorage 来读取存储的主题设置
    @AppStorage("selectedTheme") private var selectedTheme: String = "system" // 默认为系统模式
    func getDestination(for row: TableRowNode) -> some View {
        if let destination = row.destination {
            return destination
        } else {
            return AnyView(Text("Details for \(row.title)"))
        }
    }
    
    var body: some View {
        // 根据 selectedTheme 的值应用主题
        NavigationSplitView {
            List {
                ForEach(tables) { table in
                    Section(header: Text(table.title)
                        .fontWeight(.bold)
                        .font(.system(size: 16))
                    ) {
                        ForEach(table.rows) { row in
                            NavigationLink(destination: getDestination(for: row)) {
                                HStack {
                                    // 图标和文本
                                    Image(row.iconName)  // 使用来自 Assets Catalog 的图标
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                    
                                    VStack(alignment: .leading) {
                                        Text(row.title)
                                            .font(.system(size: 15))
                                        if let note = row.note, !note.isEmpty {
                                            Text(note)
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(height: 36) // 确保单元格最大高度为 36
                                    Spacer() // 右侧空白，推动箭头到右边
                                }
                                .frame(height: 36) // 确保每个单元格最大高度为 36
                            }
                        }
                    }
                }
            }
            .navigationTitle("Neocom")
        } detail: {
            Text("Select an item")
        }
        // 设置颜色方案，根据 selectedTheme 的值动态调整
        .preferredColorScheme(selectedTheme == "light" ? .light : (selectedTheme == "dark" ? .dark : nil))
    }
}

#Preview {
    ContentView()
}
