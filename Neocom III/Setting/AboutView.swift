import SwiftUI

struct AboutView: View {
    @State private var aboutItems: [TableRowNode] = [
        TableRowNode(title: "App Version", iconName: "", note: "1.0.0"),
        TableRowNode(title: "Database Version", iconName: "", note: "2024-12-06"),
        TableRowNode(title: "License", iconName: "", note: "Open Source License"),
        TableRowNode(title: "Contact Us", iconName: "", note: "support@example.com")
    ]
    
    var body: some View {
        List {
            Section(header: Text(
                NSLocalizedString("Main_About_Title", comment: "")
            )
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
            ) {
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
        .listStyle(.plain)
        .navigationTitle(Text(
            NSLocalizedString("Main_About", comment: "")
        ))
    }
}

#Preview {
    AboutView()
}
