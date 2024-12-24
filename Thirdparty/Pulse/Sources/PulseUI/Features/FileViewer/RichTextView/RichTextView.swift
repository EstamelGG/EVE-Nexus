// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(visionOS)

import SwiftUI
import CoreData
import Pulse
import Combine

struct RichTextView: View {
    @ObservedObject var viewModel: RichTextViewModel
    var isTextViewBarItemsHidden = false

    @State private var shareItems: ShareItems?
    @State private var isWebViewOpen = false

    @Environment(\.textViewSearchContext) private var searchContext

    func textViewBarItemsHidden(_ isHidden: Bool) -> RichTextView {
        var copy = self
        copy.isTextViewBarItemsHidden = isHidden
        return copy
    }

    var body: some View {
        contents
            .onAppear { viewModel.prepare(searchContext) }
            .navigationBarItems(trailing: navigationBarTrailingItems)
            .sheet(item: $shareItems, content: ShareView.init)
            .sheet(isPresented: $isWebViewOpen) {
                NavigationView {
                    WebView(data: viewModel.textStorage.string.data(using: .utf8) ?? Data(), contentType: "application/html")
                        .inlineNavigationTitle("Browser Preview")
                        .navigationBarItems(trailing: Button(action: {
                            isWebViewOpen = false
                        }) { Image(systemName: "xmark") })
                }
            }
    }

    @ViewBuilder
    private var contents: some View {
        ContentView(viewModel: viewModel)
            .searchable(text: $viewModel.searchTerm)
            .disableAutocorrection(true)
    }

    private struct ContentView: View {
        @ObservedObject var viewModel: RichTextViewModel
        @Environment(\.isSearching) private var isSearching

        var body: some View {
            WrappedTextView(viewModel: viewModel)
                .edgesIgnoringSafeArea([.bottom])
                .overlay {
                    if isSearching || !viewModel.matches.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                RichTextViewSearchToobar(viewModel: viewModel)
                                    .padding()
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var navigationBarTrailingItems: some View {
        if !isTextViewBarItemsHidden {
            Menu(content: {
                AttributedStringShareMenu(shareItems: $shareItems) {
                    viewModel.textStorage
                }
            }, label: {
                Image(systemName: "square.and.arrow.up")
            })
            // TODO: This should be injected/added outside of the text view
            if viewModel.contentType?.isHTML ?? false {
                Menu(content: {
                    Section {
                        if viewModel.contentType?.isHTML == true {
                            Button(action: { isWebViewOpen = true }) {
                                Label("Open in Browser", systemImage: "safari")
                            }
                        }
                    }
                }, label: {
                    Image(systemName: "ellipsis.circle")
                })
            }
        }
    }
}

#if DEBUG
struct RichTextView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RichTextView(viewModel: makePreviewViewModel())
                .inlineNavigationTitle("Rich Text View")
        }
    }
}

private func makePreviewViewModel() -> RichTextViewModel {
    let json = try! JSONSerialization.jsonObject(with: MockJSON.allPossibleValues)
    let string = TextRenderer().render(json: json)

    return RichTextViewModel(string: string, contentType: "application/json")
}
#endif

#endif
