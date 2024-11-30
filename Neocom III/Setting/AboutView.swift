//
//  AboutView.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/11/30.
//

import SwiftUI

struct AboutView: View {
    @State private var aboutItems: [TableRowNode] = [
        TableRowNode(title: "App Version", iconName: "", note: "1.0.0"),
        TableRowNode(title: "Database Version", iconName: "", note: "2024-11-30"),
        TableRowNode(title: "License", iconName: "", note: "Open Source License"),
        TableRowNode(title: "Contact Us", iconName: "", note: "support@example.com")
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text(
                    NSLocalizedString("Main_About_Title", comment: "")
                )) {
                    ForEach(aboutItems) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                    .font(.system(size: 16))
                                if let note = item.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }
                        .frame(height: 36)
                    }
                }
            }
            .navigationTitle(Text(
                NSLocalizedString("Main_About", comment: "")
            ))
        }
    }
}

#Preview {
    AboutView()
}
