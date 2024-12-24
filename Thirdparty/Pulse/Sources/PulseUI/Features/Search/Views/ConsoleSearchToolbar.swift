// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(visionOS)

import SwiftUI
import Pulse
import CoreData
import Combine

@available(iOS 16, visionOS 1, *)
struct ConsoleSearchToolbar: View {
    @EnvironmentObject private var viewModel: ConsoleSearchViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(viewModel.toolbarTitle)
                .foregroundColor(.secondary)
                .font(.subheadline.weight(.medium))
            if viewModel.isSpinnerNeeded {
                ProgressView()
                    .padding(.leading, 8)
            }
            Spacer()
            searchOptionsView
        }
        .buttonStyle(.plain)
    }

    private var searchOptionsView: some View {
#if os(iOS) || os(visionOS)
            HStack(spacing: 14) {
                ConsoleSearchContextMenu()
            }
#else
        StringSearchOptionsMenu(options: $viewModel.options)
            .fixedSize()
#endif
    }
}

@available(iOS 16, visionOS 1, *)
struct ConsoleSearchScopesPicker: View {
    @ObservedObject var viewModel: ConsoleSearchViewModel

    var body: some View {
        ForEach(viewModel.allScopes, id: \.self) { scope in
            Checkbox(isOn: Binding(get: {
                viewModel.scopes.contains(scope)
            }, set: { isOn in
                if isOn {
                    viewModel.scopes.insert(scope)
                } else {
                    viewModel.scopes.remove(scope)
                }
            }), label: { Text(scope.title).lineLimit(1) })
        }
    }
}
#endif
