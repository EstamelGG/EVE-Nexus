import SwiftUI
import UIKit

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isSearching: Bool
    var onCancel: (() -> Void)?
    var onSearch: (() -> Void)?

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = NSLocalizedString("Main_Database_Search", comment: "")
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.showsCancelButton = true
        searchBar.returnKeyType = .done
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context _: Context) {
        uiView.text = text
        if let searchField = uiView.value(forKey: "searchField") as? UITextField {
            searchField.returnKeyType = .done
            searchField.reloadInputViews()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isSearching: $isSearching, onCancel: onCancel, onSearch: onSearch)
    }

    class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String
        @Binding var isSearching: Bool
        var onCancel: (() -> Void)?
        var onSearch: (() -> Void)?
        private var isComposing = false

        init(
            text: Binding<String>, isSearching: Binding<Bool>, onCancel: (() -> Void)?,
            onSearch: (() -> Void)?
        ) {
            _text = text
            _isSearching = isSearching
            self.onCancel = onCancel
            self.onSearch = onSearch
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            if let searchField = searchBar.value(forKey: "searchField") as? UITextField {
                isComposing = searchField.markedTextRange != nil
            }

            if !isComposing {
                text = searchText
                isSearching = true
            }
        }

        func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
            if let searchField = searchBar.value(forKey: "searchField") as? UITextField {
                searchField.returnKeyType = .done
                searchField.reloadInputViews()
            }
            return true
        }

        func searchBar(
            _ searchBar: UISearchBar, shouldChangeTextIn _: NSRange,
            replacementText text: String
        ) -> Bool {
            if text == "\n" {
                searchBar.resignFirstResponder()
                return false
            }
            return true
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            isComposing = false
            if let finalText = searchBar.text {
                text = finalText
            }
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            text = ""
            isSearching = false
            onCancel?()
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            if let searchField = searchBar.value(forKey: "searchField") as? UITextField {
                searchField.returnKeyType = .done
                searchField.reloadInputViews()
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var text = ""
        @State private var isSearching = false

        var body: some View {
            SearchBar(text: $text, isSearching: $isSearching)
        }
    }

    return PreviewWrapper()
}
