import SwiftUI

struct AboutView: View {
    @Environment(\.locale) private var locale
    
    private var appIcon: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return UIImage(named: "DefaultAppIcon")
    }
    
    private let aboutItems: [AboutItem] = [
        AboutItem(title: NSLocalizedString("Main_About_Version", comment: ""), value: "1.0-b", icon: "app.badge", url: nil),
        AboutItem(title: NSLocalizedString("Main_About_Database_Version", comment: ""), value: "2025-01-01", icon: "server.rack", url: nil),
        AboutItem(title: NSLocalizedString("Main_About_Github", comment: ""), value: "https://github.com/EstamelGG/EVE-Nexus-Public", icon: "link", url: URL(string: "https://github.com/EstamelGG/EVE-Nexus-Public"))
    ]
    
    private var privacyText: String {
        NSLocalizedString("Main_About_Privacy_Statement", comment: "")
    }
    
    private var privacyTitle: String {
        NSLocalizedString("Main_About_Privacy_Title", comment: "")
    }
    
    var body: some View {
        List {
            // App Logo Section
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        if let icon = appIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .cornerRadius(20)
                                .shadow(radius: 5)
                        }
                        
                        Text("EVE Nexus")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 20)
            }
            
            // Information Section
            Section {
                ForEach(aboutItems) { item in
                    if let url = item.url {
                        Link(destination: url) {
                            AboutItemRow(item: item)
                        }
                    } else {
                        AboutItemRow(item: item)
                    }
                }
            }
            
            // Privacy Section
            Section(header: Text(privacyTitle).fontWeight(.bold)) {
                Text(privacyText)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
            }
            
            // Copyright Section
            Section {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Main_About_Copyright", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(NSLocalizedString("Main_About", comment: "")))
    }
}

struct AboutItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let url: URL?
}

struct AboutItemRow: View {
    let item: AboutItem
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16))
                Text(item.value)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationView {
        AboutView()
    }
}
