import Foundation
import SwiftUI

// MARK: - PreferenceKey for frame tracking

/// ID 为 phantom type：通过泛型实参区分不同用途的 preference key（periphery:ignore:all）
struct AppendPreferenceKey<Value, ID>: PreferenceKey {
    static var defaultValue: [Value] {
        []
    }

    static func reduce(value: inout [Value], nextValue: () -> [Value]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - View extensions for frame tracking

extension View {
    func framePreference<ID>(in coordinateSpace: CoordinateSpace, _: ID.Type = ID.self)
        -> some View
    {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AppendPreferenceKey<CGRect, ID>.self,
                    value: [geometry.frame(in: coordinateSpace)]
                )
            }
        )
    }

    func onFrameChange<ID>(_: ID.Type = ID.self, perform action: @escaping ([CGRect]) -> Void)
        -> some View
    {
        onPreferenceChange(AppendPreferenceKey<CGRect, ID>.self, perform: action)
    }
}

extension View {
    @ViewBuilder
    func isHidden(_ hidden: Bool) -> some View {
        if !hidden {
            self
        }
    }
}
