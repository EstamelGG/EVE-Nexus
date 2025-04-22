import SafariServices
import SwiftUI

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.presentationMode) var presentationMode

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
