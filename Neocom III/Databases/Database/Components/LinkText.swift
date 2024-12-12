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
                        if let categoryID = databaseManager.getCategoryID(for: itemID) {
                            showingSheet = true
                        }
                    }
                }
                .sheet(isPresented: $showingSheet) {
                    if let itemID = itemID,
                       let categoryID = databaseManager.getCategoryID(for: itemID) {
                        NavigationView {
                            ItemInfoMap.getItemInfoView(
                                itemID: itemID,
                                categoryID: categoryID,
                                databaseManager: databaseManager
                            )
                        }
                    }
                }
            
        case .url:
            if let urlString = url,
               let url = URL(string: urlString) {
                Link(text, destination: url)
                    .foregroundColor(.blue)
            } else {
                Text(text)
                    .foregroundColor(.blue)
            }
        }
    }
} 