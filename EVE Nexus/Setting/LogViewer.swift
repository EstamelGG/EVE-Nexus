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
    @State private var logLines: [String] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [(lineNumber: Int, line: String)] = []
    @State private var selectedSearchResult: Int?
    private let linesPerPage = 1000
    
    var filteredLines: [String] {
        if searchText.isEmpty {
            return logLines
        }
        return logLines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField(NSLocalizedString("Main_Setting_Logs_Search_Placeholder", comment: ""), text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: searchText) { oldValue, newValue in
                        searchInContent()
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                        selectedSearchResult = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                if !searchResults.isEmpty {
                    Text("\(selectedSearchResult.map { $0 + 1 } ?? 0)/\(searchResults.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack(spacing: 4) {
                        Button(action: { selectPreviousResult() }) {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(selectedSearchResult == nil || selectedSearchResult == 0)
                        
                        Button(action: { selectNextResult() }) {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(selectedSearchResult == nil || selectedSearchResult == searchResults.count - 1)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            // 日志内容
            ScrollView {
                if isLoading && logLines.isEmpty {
                    ProgressView()
                        .padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(isLineHighlighted(index: index) ? .white : .primary)
                                .background(isLineHighlighted(index: index) ? Color.blue : Color.clear)
                                .onAppear {
                                    if index == logLines.count - 100 {
                                        loadMoreContent()
                                    }
                                }
                        }
                        if isLoading {
                            ProgressView()
                                .padding()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(logFile.lastPathComponent)
        .onAppear {
            loadInitialContent()
        }
    }
    
    private func isLineHighlighted(index: Int) -> Bool {
        guard let selectedIndex = selectedSearchResult,
              let _ = searchResults[safe: selectedIndex] else {
            return false
        }
        return filteredLines[index].contains(searchResults[selectedIndex].line)
    }
    
    private func searchInContent() {
        guard !searchText.isEmpty else {
            searchResults = []
            selectedSearchResult = nil
            return
        }
        
        searchResults = logLines.enumerated()
            .filter { $0.element.localizedCaseInsensitiveContains(searchText) }
            .map { (lineNumber: $0.offset, line: $0.element) }
        
        selectedSearchResult = searchResults.isEmpty ? nil : 0
    }
    
    private func selectNextResult() {
        guard let current = selectedSearchResult, current < searchResults.count - 1 else { return }
        selectedSearchResult = current + 1
    }
    
    private func selectPreviousResult() {
        guard let current = selectedSearchResult, current > 0 else { return }
        selectedSearchResult = current - 1
    }
    
    private func loadInitialContent() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileHandle = try FileHandle(forReadingFrom: logFile)
                defer { try? fileHandle.close() }
                
                let lines = try readNextPage(fileHandle: fileHandle)
                DispatchQueue.main.async {
                    logLines = lines
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    logLines = ["Error loading log file: \(error.localizedDescription)"]
                    isLoading = false
                }
            }
        }
    }
    
    private func loadMoreContent() {
        guard !isLoading else { return }
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileHandle = try FileHandle(forReadingFrom: logFile)
                defer { try? fileHandle.close() }
                
                // 跳过已读取的内容
                let offset = UInt64(logLines.joined(separator: "\n").utf8.count)
                try fileHandle.seek(toOffset: offset)
                
                let newLines = try readNextPage(fileHandle: fileHandle)
                if !newLines.isEmpty {
                    DispatchQueue.main.async {
                        logLines.append(contentsOf: newLines)
                        currentPage += 1
                        isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
    
    private func readNextPage(fileHandle: FileHandle) throws -> [String] {
        let chunkSize = 4 * 1024 // 4KB chunks
        var allLines: [String] = []
        let targetLines = 1000 // 每页目标行数
        
        while allLines.count < targetLines {
            guard let data = try fileHandle.read(upToCount: chunkSize) else { break }
            if data.isEmpty { break }
            
            var lines = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines) ?? []
            
            // 如果最后一行不完整，回退文件指针
            if !data.isEmpty && !data.last!.isNewline {
                if let lastLine = lines.last, let lastLineData = lastLine.data(using: .utf8) {
                    try fileHandle.seek(toOffset: fileHandle.offsetInFile - UInt64(lastLineData.count))
                    lines.removeLast()
                }
            }
            
            allLines.append(contentsOf: lines)
            
            // 如果没有更多数据可读，退出循环
            if data.count < chunkSize {
                break
            }
        }
        
        return allLines
    }
}

private extension UInt8 {
    var isNewline: Bool {
        self == 10 // \n
    }
}
