//
//  AboutView.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/11/30.
//

import SwiftUI

struct AboutView: View {
    @State private var aboutItems: [TableRowNode] = [
        TableRowNode(title: "App Version", iconName: "info.circle", note: "1.0.0"),
        TableRowNode(title: "License", iconName: "doc.text", note: "Open Source License"),
        TableRowNode(title: "Contact Us", iconName: "envelope", note: "support@example.com")
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("About").font(.title3).fontWeight(.bold)) {
                    ForEach(aboutItems) { item in
                        HStack {
                            Image(systemName: item.iconName) // SF Symbols 图标
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.body)
                                if let note = item.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("About")
        }
    }
}

#Preview {
    AboutView()
}
