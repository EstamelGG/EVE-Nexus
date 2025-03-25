import SwiftUI

struct LinkText: View {
    let text: String
    let type: LinkType
    let itemID: Int?
    let url: String?
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showingSheet = false

    enum LinkType {
        case showInfo
        case url
    }

    var body: some View {
        switch type {
        case .showInfo:
            Text(text)
                .foregroundColor(.blue)
                .onTapGesture {
                    if let itemID = itemID {
                        if databaseManager.getCategoryID(for: itemID) != nil {
                            showingSheet = true
                        }
                    }
                }
                .sheet(isPresented: $showingSheet) {
                    if let itemID = itemID {
                        NavigationStack {
                            ItemInfoMap.getItemInfoView(
                                itemID: itemID,
                                databaseManager: databaseManager
                            )
                        }
                    }
                }

        case .url:
            if let urlString = url,
                let url = URL(string: urlString)
            {
                SwiftUI.Link(text, destination: url)
                    .foregroundColor(.blue)
            } else {
                Text(text)
                    .foregroundColor(.blue)
            }
        }
    }
}
