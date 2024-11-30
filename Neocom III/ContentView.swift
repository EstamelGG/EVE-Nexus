import SwiftUI
import SwiftData

// 定义树形结构的节点
class TableRowNode: Identifiable, ObservableObject {
    var id = UUID()
    var title: String
    var iconName: String
    var note: String?
    
    init(title: String, iconName: String, note: String? = nil) {
        self.title = title
        self.iconName = iconName
        self.note = note
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
        TableNode(title: "Character", rows: [
            TableRowNode(title: "Character Sheet", iconName: "charactersheet", note: "This is your character's information."),
            TableRowNode(title: "Jump Clones", iconName: "jumpclones", note: "Manage your jump clones."),
            TableRowNode(title: "Skills", iconName: "skills", note: "Skills progression."),
            TableRowNode(title: "EVE Mail", iconName: "evemail", note: ""),
            TableRowNode(title: "Calendar", iconName: "calendar", note: ""),
            TableRowNode(title: "Wealth", iconName: "Folder", note: "your money"),
            TableRowNode(title: "Loyalty Points", iconName: "lpstore", note: "")
        ]),
        TableNode(title: "Databases", rows: [
            TableRowNode(title: "Database", iconName: "items", note: ""),
            //            TableRowNode(title: "Certificates", iconName: "checkmark.seal.fill", note: ""),
            TableRowNode(title: "Market", iconName: "market", note: ""),
            TableRowNode(title: "NPC", iconName: "criminal", note: ""),
            TableRowNode(title: "Wormholes", iconName: "terminate", note: ""),
            TableRowNode(title: "Incursions", iconName: "incursions", note: "")
        ]),
        TableNode(title: "Business", rows: [
            TableRowNode(title: "Assets", iconName: "assets", note: ""),
            TableRowNode(title: "Market Orders", iconName: "marketdeliveries", note: ""),
            TableRowNode(title: "Contracts", iconName: "contracts", note: ""),
            TableRowNode(title: "Market Transactions", iconName: "journal", note: ""),
            TableRowNode(title: "Wallet Journal", iconName: "wallet", note: ""),
            TableRowNode(title: "Industry Jobs", iconName: "industry", note: "")
//            TableRowNode(title: "Planetaries", iconName: "planets", note: "")
        ]),
        //        TableNode(title: "Fitting", rows: [
        //            TableRowNode(title: "Fitting Editor", iconName: "fitting", note: "")
        //        ]),
        TableNode(title: "", rows: [
            TableRowNode(title: "Setting", iconName: "Settings", note: ""),
            TableRowNode(title: "About", iconName: "info", note: "")
        ])
    ]
    
    var body: some View {
        NavigationSplitView {
            List {
                ForEach(tables) { table in
                    Section(header: Text(table.title)
                        .fontWeight(.bold)
                        .font(.system(size: 16))
                    ) {
                        ForEach(table.rows) { row in
                            NavigationLink(destination: Text("Details for \(row.title)")) {
                                HStack {
                                    // 图标和文本
                                    Image(row.iconName)  // 使用来自 Assets Catalog 的图标
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading) { // 设置两行之间的间距为4像素
                                        // 第一行文本，离单元格顶部4像素
                                        Text(row.title)
                                            .font(.system(size: 15))
                                        // 第二行文本，离单元格底部4像素
                                        if let note = row.note, !note.isEmpty {
                                            Text(note)
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(height: 36) // 确保单元格最大高度为 20
                                    Spacer() // 右侧空白，推动箭头到右边
                                }
                                .frame(height: 36) // 确保每个单元格最大高度为 20
                            }
                        }
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }
}

#Preview {
    ContentView()
}
