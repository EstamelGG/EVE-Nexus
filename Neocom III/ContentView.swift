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
            TableRowNode(title: "Character Sheet", iconName: "star.fill", note: "This is your character's information."),
            TableRowNode(title: "Jump Clones", iconName: "arrow.up.circle.fill", note: "Manage your jump clones."),
            TableRowNode(title: "Skills", iconName: "book.fill", note: "Skills progression."),
            TableRowNode(title: "EVE Mail", iconName: "envelope.fill", note: ""),
            TableRowNode(title: "Calendar", iconName: "calendar.circle.fill", note: ""),
            TableRowNode(title: "Wealth", iconName: "dollarsign.circle.fill", note: "Track your wealth and assets."),
            TableRowNode(title: "Loyalty Points", iconName: "star.lefthalf.fill", note: "")
        ]),
        TableNode(title: "Databases", rows: [
            TableRowNode(title: "Database", iconName: "folder.fill", note: "Access to the main database."),
            TableRowNode(title: "Certificates", iconName: "checkmark.seal.fill", note: ""),
            TableRowNode(title: "Market", iconName: "cart.fill", note: ""),
            TableRowNode(title: "NPC", iconName: "person.fill", note: ""),
            TableRowNode(title: "Wormholes", iconName: "circle.fill", note: ""),
            TableRowNode(title: "Incursions", iconName: "flame.fill", note: "")
        ]),
        TableNode(title: "Business", rows: [
            TableRowNode(title: "Assets", iconName: "cube.fill", note: ""),
            TableRowNode(title: "Market Orders", iconName: "arrow.up.arrow.down.circle.fill", note: ""),
            TableRowNode(title: "Contracts", iconName: "pencil.and.outline", note: ""),
            TableRowNode(title: "Wallet Transactions", iconName: "creditcard.fill", note: ""),
            TableRowNode(title: "Wallet Journal", iconName: "note.text", note: ""),
            TableRowNode(title: "Industry Jobs", iconName: "gearshape.fill", note: ""),
            TableRowNode(title: "Planetaries", iconName: "earth.fill", note: "")
        ]),
        TableNode(title: "", rows: [
            TableRowNode(title: "Setting", iconName: "cube.fill", note: ""),
            TableRowNode(title: "About", iconName: "arrow.up.arrow.down.circle.fill", note: "")
        ])
    ]
    
    var body: some View {
        NavigationSplitView {
            List {
                ForEach(tables) { table in
                    Section(header: Text(table.title)) {
                        ForEach(table.rows) { row in
                            NavigationLink(destination: Text("Details for \(row.title)")) {
                                HStack {
                                    // 图标和文本
                                    Image(systemName: row.iconName)
                                        .frame(width: 28, height: 28)

                                    VStack(alignment: .leading) {
                                        Text(row.title)
                                            .font(.system(size: 17))

                                        if let note = row.note, !note.isEmpty {
                                            Text(note)
                                                .font(.system(size: 13)) // 设置自定义字体大小
                                                .foregroundColor(.gray)
                                        }


                                    }
                                    .padding(.leading, 8)

                                    Spacer() // 右侧空白，推动箭头到右边
                                }
                                .padding(.vertical, 5)
                                .frame(minHeight: 44)
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
