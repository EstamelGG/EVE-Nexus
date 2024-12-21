import SwiftUI

struct LogViewer: View {
    @State private var logFiles: [URL] = []
    @State private var selectedLogFile: URL?
    @State private var logContent: String = ""
    @State private var showingDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(logFiles, id: \.self) { file in
                    LogFileRow(file: file, isSelected: file == selectedLogFile) {
                        if selectedLogFile == file {
                            selectedLogFile = nil
                            logContent = ""
                        } else {
                            selectedLogFile = file
                            logContent = Logger.readLogFile(file)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Setting_Logs_Title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            if let _ = selectedLogFile {
                ScrollView {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .textSelection(.enabled)
                }
            } else {
                Text(NSLocalizedString("Main_Setting_Logs_Select_Hint", comment: ""))
                    .foregroundColor(.gray)
            }
        }
        .alert(NSLocalizedString("Main_Setting_Logs_Delete_Title", comment: ""), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("Main_Setting_Delete", comment: ""), role: .destructive) {
                Logger.clearAllLogs()
                loadLogFiles()
                selectedLogFile = nil
                logContent = ""
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Logs_Delete_Message", comment: ""))
        }
        .onAppear {
            loadLogFiles()
        }
    }
    
    private func loadLogFiles() {
        logFiles = Logger.getAllLogFiles()
    }
}

struct LogFileRow: View {
    let file: URL
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(file.lastPathComponent)
                        .font(.headline)
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                       let size = attributes[.size] as? Int64,
                       let modificationDate = attributes[.modificationDate] as? Date {
                        Text(formatFileInfo(size: size, date: modificationDate))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .foregroundColor(.primary)
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