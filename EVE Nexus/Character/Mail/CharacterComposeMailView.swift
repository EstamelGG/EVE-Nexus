import SwiftUI

struct CharacterComposeMailView: View {
    let characterId: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CharacterComposeMailViewModel()
    
    @State private var recipients: String = ""
    @State private var subject: String = ""
    @State private var mailBody: String = ""
    @State private var showingRecipientPicker = false
    
    var body: some View {
        Form {
            Section {
                TextField("收件人", text: $recipients)
                    .onTapGesture {
                        showingRecipientPicker = true
                    }
            } header: {
                Text("收件人")
            }
            
            Section {
                TextField("主题", text: $subject)
            } header: {
                Text("主题")
            }
            
            Section {
                TextEditor(text: $mailBody)
                    .frame(minHeight: 200)
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
            RecipientPickerView(selectedRecipients: $recipients)
        }
    }
}

struct RecipientPickerView: View {
    @Binding var selectedRecipients: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Text("选择收件人") // 这里后续可以实现具体的收件人选择功能
                .navigationTitle("选择收件人")
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
    
    func sendMail(characterId: Int, recipients: String, subject: String, body: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 解析收件人字符串为收件人列表
            // TODO: 这里需要改进收件人的解析逻辑
            let recipientsList = [EVEMailRecipient(recipient_id: Int(recipients) ?? 0, recipient_type: "character")]
            
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