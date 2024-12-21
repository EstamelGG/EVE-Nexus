import SwiftUI

struct LogViewer: View {
    @State private var logFiles: [URL] = []
    @State private var selectedLogFile: URL?
    @State private var showingDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                ForEach(logFiles, id: \.self) { file in
                    NavigationLink {
                        LogContentView(logFile: file)
                    } label: {
                        LogFileRow(file: file)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Logs_Title", comment: ""))
        .navigationBarItems(trailing: Button(action: {
            showingDeleteAlert = true
        }) {
            Image(systemName: "trash")
                .foregroundColor(.red)
        })
        .alert(NSLocalizedString("Main_Setting_Logs_Delete_Title", comment: ""), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("Main_Setting_Delete", comment: ""), role: .destructive) {
                Logger.clearAllLogs()
                loadLogFiles()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Logs_Delete_Message", comment: ""))
        }
        .onAppear {
            loadLogFiles()
        }
    }
    
    private func loadLogFiles() {
        DispatchQueue.global(qos: .userInitiated).async {
            let files = Logger.getAllLogFiles()
            DispatchQueue.main.async {
                logFiles = files
            }
        }
    }
}

struct LogFileRow: View {
    let file: URL
    @State private var fileInfo: (size: Int64, date: Date)?
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(file.lastPathComponent)
                .font(.headline)
            if let info = fileInfo {
                Text(formatFileInfo(size: info.size, date: info.date))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            loadFileInfo()
        }
    }
    
    private func loadFileInfo() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? Int64,
               let modificationDate = attributes[.modificationDate] as? Date {
                DispatchQueue.main.async {
                    fileInfo = (size, modificationDate)
                }
            }
        }
    }
    
    private func formatFileInfo(size: Int64, date: Date) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: size)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: date)
        
        return "\(sizeString) • \(dateString)"
    }
}

struct LogContentView: View {
    let logFile: URL
    @State private var logContent: String = ""
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else {
                Text(logContent)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(logFile.lastPathComponent)
        .onAppear {
            loadLogContent()
        }
    }
    
    private func loadLogContent() {
        DispatchQueue.global(qos: .userInitiated).async {
            let content = Logger.readLogFile(logFile)
            DispatchQueue.main.async {
                logContent = content
                isLoading = false
            }
        }
    }
}
