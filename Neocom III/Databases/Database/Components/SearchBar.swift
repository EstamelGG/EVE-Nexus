import SwiftUI
import UIKit

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isSearching: Bool
    var onCancel: (() -> Void)?
    
    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = NSLocalizedString("Main_Database_Search", comment:"")
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.showsCancelButton = true
        return searchBar
    }
    
    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isSearching: $isSearching, onCancel: onCancel)
    }
    
    class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String
        @Binding var isSearching: Bool
        var onCancel: (() -> Void)?
        private var isComposing = false
        
        init(text: Binding<String>, isSearching: Binding<Bool>, onCancel: (() -> Void)?) {
            _text = text
            _isSearching = isSearching
            self.onCancel = onCancel
        }
        
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            if !isComposing {
                text = searchText
            }
        }
        
        func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
            isSearching = true
            return true
        }
        
        func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                searchBar.resignFirstResponder()
                isSearching = false
                return false
            }
            
            if text.isEmpty && range.length > 0 {
                isComposing = false
            } else {
                isComposing = true
            }
            return true
        }
        
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            isComposing = false
            if let finalText = searchBar.text {
                text = finalText
            }
            isSearching = false
        }
        
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            text = ""
            isSearching = false
            onCancel?()
        }
        
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            isComposing = false
            isSearching = false
            if searchBar.text?.isEmpty ?? true {
                onCancel?()
            }
        }
        
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            isSearching = true
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
