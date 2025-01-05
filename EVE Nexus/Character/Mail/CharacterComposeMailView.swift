import SwiftUI

struct CharacterComposeMailView: View {
    let characterId: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CharacterComposeMailViewModel()
    
    @State private var recipients: [MailRecipient] = []
    @State private var subject: String = ""
    @State private var mailBody: String = ""
    @State private var showingRecipientPicker = false
    
    var body: some View {
        Form {
            Section {
                // 收件人列表
                ForEach(recipients) { recipient in
                    HStack {
                        CharacterPortrait(characterId: recipient.id, size: 32)
                        VStack(alignment: .leading) {
                            Text(recipient.name)
                            Text(recipient.type.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            recipients.removeAll(where: { $0.id == recipient.id })
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // 添加收件人按钮
                Button {
                    showingRecipientPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("添加收件人")
                    }
                }
            } header: {
                Text("收件人")
            }
            
            Section {
                TextField("主题", text: $subject)
                    .textInputAutocapitalization(.none)
            } header: {
                Text("主题")
            }
            
            Section {
                TextEditor(text: $mailBody)
                    .frame(minHeight: 200)
                    .textInputAutocapitalization(.none)
            } header: {
                Text("正文")
            }
        }
        .navigationTitle("新邮件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("发送") {
                    Task {
                        await viewModel.sendMail(
                            characterId: characterId,
                            recipients: recipients,
                            subject: subject,
                            body: mailBody
                        )
                        dismiss()
                    }
                }
                .disabled(recipients.isEmpty || subject.isEmpty || mailBody.isEmpty)
            }
        }
        .sheet(isPresented: $showingRecipientPicker) {
            RecipientPickerView(characterId: characterId) { recipient in
                if !recipients.contains(where: { $0.id == recipient.id }) {
                    recipients.append(recipient)
                }
            }
        }
    }
}

// 邮件收件人数据结构
struct MailRecipient: Identifiable {
    let id: Int
    let name: String
    let type: RecipientType
    
    enum RecipientType: String {
        case character = "角色"
        case corporation = "军团"
        case alliance = "联盟"
    }
}

struct RecipientPickerView: View {
    let characterId: Int
    let onSelect: (MailRecipient) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RecipientPickerViewModel()
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("搜索中...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if viewModel.error != nil {
                    HStack {
                        Spacer()
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text("搜索失败:\(viewModel.error)")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else if searchText.isEmpty {
                    Text("请输入要搜索的角色、军团或联盟名称")
                        .foregroundColor(.secondary)
                } else if viewModel.searchResults.isEmpty {
                    Text("未找到相关结果")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { result in
                        Button {
                            onSelect(MailRecipient(id: result.id, name: result.name, type: result.type))
                            dismiss()
                        } label: {
                            HStack {
                                CharacterPortrait(characterId: result.id, size: 32)
                                VStack(alignment: .leading) {
                                    Text(result.name)
                                    Text(result.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索角色、军团或联盟")
            .onChange(of: searchText) { newValue in
                Task {
                    await viewModel.search(characterId: characterId, searchText: newValue)
                }
            }
            .navigationTitle("添加收件人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
class CharacterComposeMailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    
    func sendMail(characterId: Int, recipients: [MailRecipient], subject: String, body: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 转换收件人格式
            let recipientsList = recipients.map { recipient in
                EVEMailRecipient(
                    recipient_id: recipient.id,
                    recipient_type: recipient.type == .character ? "character" :
                                  recipient.type == .corporation ? "corporation" : "alliance"
                )
            }
            
            try await CharacterMailAPI.shared.sendMail(
                characterId: characterId,
                recipients: recipientsList,
                subject: subject,
                body: body
            )
            Logger.info("邮件发送成功")
        } catch {
            Logger.error("发送邮件失败: \(error)")
            self.error = error
        }
    }
}

@MainActor
class RecipientPickerViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var error: Error?
    
    struct SearchResult: Identifiable {
        let id: Int
        let name: String
        let type: MailRecipient.RecipientType
    }
    
    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.character, .corporation, .alliance],
                searchText: searchText
            )
            
            // 解析搜索结果
            if let searchResponse = try? JSONDecoder().decode(SearchResponse.self, from: data) {
                var results: [SearchResult] = []
                
                // 处理角色搜索结果
                if let characters = searchResponse.character {
                    let characterNames = try await UniverseAPI.shared.getNamesWithFallback(ids: characters)
                    results.append(contentsOf: characters.compactMap { id in
                        guard let info = characterNames[id] else { return nil }
                        return SearchResult(id: id, name: info.name, type: .character)
                    })
                }
                
                // 处理军团搜索结果
                if let corporations = searchResponse.corporation {
                    let corpNames = try await UniverseAPI.shared.getNamesWithFallback(ids: corporations)
                    results.append(contentsOf: corporations.compactMap { id in
                        guard let info = corpNames[id] else { return nil }
                        return SearchResult(id: id, name: info.name, type: .corporation)
                    })
                }
                
                // 处理联盟搜索结果
                if let alliances = searchResponse.alliance {
                    let allianceNames = try await UniverseAPI.shared.getNamesWithFallback(ids: alliances)
                    results.append(contentsOf: alliances.compactMap { id in
                        guard let info = allianceNames[id] else { return nil }
                        return SearchResult(id: id, name: info.name, type: .alliance)
                    })
                }
                
                searchResults = results
            }
        } catch {
            Logger.error("搜索收件人失败: \(error)")
            self.error = error
        }
    }
}

// 搜索响应数据结构
private struct SearchResponse: Codable {
    let character: [Int]?
    let corporation: [Int]?
    let alliance: [Int]?
}

#Preview {
    NavigationView {
        CharacterComposeMailView(characterId: 123456)
    }
} 
