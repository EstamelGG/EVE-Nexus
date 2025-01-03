import SwiftUI

struct AboutView: View {
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
        AboutItem(title: "App Version", value: "1.0-b", icon: "app.badge"),
        AboutItem(title: "Database Version", value: "2025-01-01", icon: "server.rack"),
        AboutItem(title: "GitHub", value: "https://github.com/EstamelGG/EVE-Nexus-Public", icon: "link")
    ]
    
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
            
            // Copyright Section
            Section {
                HStack {
                    Spacer()
                    Text("© 2025 EVE Nexus. All rights reserved.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
    }
}

struct AboutItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
}

#Preview {
    NavigationView {
        AboutView()
    }
}
