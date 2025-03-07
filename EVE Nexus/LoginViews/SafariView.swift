import SafariServices
import SwiftUI

// 创建一个ObservableObject来管理Safari视图的状态
final class SafariViewModel: ObservableObject {
    @Published var characterInfo: EVECharacterInfo?
    @Published var isLoggedIn: Bool = false
    @Published var showingError: Bool = false
    @Published var errorMessage: String = ""

    func handleLoginSuccess(character: EVECharacterInfo) {
        DispatchQueue.main.async {
            self.characterInfo = character
            self.isLoggedIn = true
        }
    }

    func handleLoginError(_ error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.showingError = true
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = SafariViewModel()

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {
        // 只在必要时更新
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariView

        init(_ parent: SafariView) {
            self.parent = parent
        }

        func safariViewControllerDidFinish(_: SFSafariViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func safariViewController(
            _: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool
        ) {
            if !didLoadSuccessfully {
                Logger.error("SafariView: 加载失败")
            }
        }
    }
}
