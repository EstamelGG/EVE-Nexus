import SwiftUI

// 添加关闭键盘的 ViewModifier
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
    }
}

// 扩展 View 以便更方便地使用这个 modifier
extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}

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
        .dismissKeyboardOnTap()
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
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            List {
                Text("搜索功能开发中...")
            }
            .searchable(text: $searchText, prompt: "搜索角色、军团或联盟")
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

#Preview {
    NavigationView {
        CharacterComposeMailView(characterId: 123456)
    }
} 