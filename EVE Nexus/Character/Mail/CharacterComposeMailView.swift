import SwiftUI

struct CharacterComposeMailView: View {
    let characterId: Int
    let initialRecipients: [MailRecipient]
    let initialSubject: String
    let initialBody: String
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CharacterComposeMailViewModel()
    
    @State private var recipients: [MailRecipient] = []
    @State private var subject: String = ""
    @State private var mailBody: String = ""
    @State private var showingRecipientPicker = false
    @State private var showingMailListPicker = false
    
    init(
        characterId: Int,
        initialRecipients: [MailRecipient] = [],
        initialSubject: String = "",
        initialBody: String = ""
    ) {
        self.characterId = characterId
        self.initialRecipients = initialRecipients
        self.initialSubject = initialSubject
        self.initialBody = initialBody
        
        // 初始化状态变量
        _recipients = State(initialValue: initialRecipients)
        _subject = State(initialValue: initialSubject)
        _mailBody = State(initialValue: initialBody)
    }
    
    var body: some View {
        Form {
            Section {
                // 收件人列表
                ForEach(recipients) { recipient in
                    HStack {
                        if recipient.type != .mailingList {
                            UniversePortrait(id: recipient.id, type: recipient.type, size: 32)
                        }
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
                        Text(NSLocalizedString("Main_EVE_Mail_Add_Recipient", comment: ""))
                    }
                }
                
                // 添加邮件列表按钮
                Button {
                    showingMailListPicker = true
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.circle.fill")
                        Text(NSLocalizedString("Main_EVE_Mail_Add_Mailing_List", comment: ""))
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Recipients", comment: ""))
            }
            
            Section {
                TextField(NSLocalizedString("Main_EVE_Mail_Subject", comment: ""), text: $subject)
                    .textInputAutocapitalization(.none)
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Subject", comment: ""))
            }
            
            Section {
                TextEditor(text: $mailBody)
                    .frame(minHeight: 200)
                    .textInputAutocapitalization(.none)
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Body", comment: ""))
            }
        }
        .navigationTitle(NSLocalizedString("Main_EVE_Mail_Add_Recipient", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: "")) {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Main_EVE_Mail_Send", comment: "")) {
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
        .sheet(isPresented: $showingMailListPicker) {
            MailListPickerView(characterId: characterId) { mailList in
                if !recipients.contains(where: { $0.id == mailList.mailing_list_id }) {
                    recipients.append(MailRecipient(
                        id: mailList.mailing_list_id,
                        name: mailList.name,
                        type: .mailingList
                    ))
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
        case character
        case corporation
        case alliance
        case mailingList
        
        var rawValue: String {
            switch self {
            case .character:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Character", comment: "")
            case .corporation:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Corporation", comment: "")
            case .alliance:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Alliance", comment: "")
            case .mailingList:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Mailing_List", comment: "")
            }
        }
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
                            Text("搜索失败:\(String(describing: viewModel.error))")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else if searchText.isEmpty {
                    Text("")
                        .foregroundColor(.secondary)
                } else if searchText.count <= 2 {
                    Text(NSLocalizedString("Main_EVE_Mail_Min_Search_Length", comment: ""))
                        .foregroundColor(.secondary)
                } else if viewModel.searchResults.isEmpty {
                    Text(NSLocalizedString("Main_EVE_Mail_No_Results", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { result in
                        Button {
                            onSelect(MailRecipient(id: result.id, name: result.name, type: result.type))
                            dismiss()
                        } label: {
                            HStack {
                                UniversePortrait(id: result.id, type: result.type, size: 32)
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
            .searchable(text: $searchText, prompt: NSLocalizedString("Main_EVE_Mail_Search_Recipients", comment: ""))
            .onChange(of: searchText) { _, _ in
                // 如果搜索文本为空或长度小于等于2，直接清空结果
                if searchText.isEmpty || searchText.count <= 2 {
                    viewModel.searchResults = []
                    if !searchText.isEmpty {
                        viewModel.error = nil
                        viewModel.isSearching = false
                    }
                } else {
                    // 使用防抖搜索
                    viewModel.debounceSearch(characterId: characterId, searchText: searchText)
                }
            }
            .navigationTitle(NSLocalizedString("Main_EVE_Mail_Add_Recipient", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 邮件列表选择视图
struct MailListPickerView: View {
    let characterId: Int
    let onSelect: (EVEMailList) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MailListPickerViewModel()
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(NSLocalizedString("Main_EVE_Mail_Loading", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let error = viewModel.error {
                    HStack {
                        Spacer()
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(NSLocalizedString("Main_EVE_Mail_Error", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else if viewModel.mailLists.isEmpty {
                    Text(NSLocalizedString("Main_EVE_Mail_No_Mailing_Lists", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.mailLists, id: \.mailing_list_id) { mailList in
                        Button {
                            onSelect(mailList)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(mailList.name)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_EVE_Mail_Select_Mailing_List", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.fetchMailLists(characterId: characterId)
        }
    }
}

@MainActor
class MailListPickerViewModel: ObservableObject {
    @Published var mailLists: [EVEMailList] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    func fetchMailLists(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            mailLists = try await CharacterMailAPI.shared.fetchMailLists(characterId: characterId)
            Logger.info("成功获取 \(mailLists.count) 个邮件列表")
        } catch {
            Logger.error("获取邮件列表失败: \(error)")
            self.error = error
        }
    }
}

#Preview {
    NavigationView {
        CharacterComposeMailView(characterId: 123456)
    }
}

// 搜索响应数据结构
private struct SearchResponse: Codable {
    let character: [Int]?
    let corporation: [Int]?
    let alliance: [Int]?
}

@MainActor
class RecipientPickerViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var error: Error?
    
    // 用于防抖的任务
    private var searchTask: Task<Void, Never>?
    
    struct SearchResult: Identifiable {
        let id: Int
        let name: String
        let type: MailRecipient.RecipientType
    }
    
    func debounceSearch(characterId: Int, searchText: String) {
        // 取消之前的搜索任务
        searchTask?.cancel()
        
        // 创建新的搜索任务，延迟500毫秒
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // 如果任务被取消了，就直接返回
            if Task.isCancelled { return }
            
            // 执行实际的搜索
            await search(characterId: characterId, searchText: searchText)
        }
    }
    
    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        // 如果已经在搜索中，就不要重复搜索
        guard !isSearching else {
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            // 清除之前的错误
            error = nil
            
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.character, .corporation, .alliance],
                searchText: searchText
            )
            
            Logger.debug("收到搜索响应数据: \(String(data: data, encoding: .utf8) ?? "无法解码")")
            
            // 解析搜索结果
            let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
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
            
            // 按名称排序结果
            results.sort { $0.name < $1.name }
            
            // 更新搜索结果
            searchResults = results
            Logger.info("搜索完成，找到 \(results.count) 个结果")
            
        } catch {
            Logger.error("搜索收件人失败: \(error)")
            self.error = error
            // 保持旧的搜索结果，而不是清空
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
                    recipient_type: recipient.type == .mailingList ? "mailing_list" :
                                  recipient.type == .character ? "character" :
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
