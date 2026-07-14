import SwiftUI

// MARK: - 横向缩放浮层（贴底部）

struct StarMapZoomOverlay: View {
    @ObservedObject var zoom: StarMapZoomController

    var body: some View {
        HStack(spacing: 12) {
            Text("\(zoom.percent)%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 38, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { zoom.relativeZoom },
                    set: { zoom.setRelativeZoom($0) }
                ),
                in: zoom.minRelative ... max(zoom.maxRelative, zoom.minRelative + 0.01)
            )
            .tint(StarMapTheme.chipAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule(style: .continuous))
    }
}

// MARK: - 搜索结果模型

struct StarMapSearchResult: Identifiable {
    let id: Int
    /// 全星域图上要高亮的星域；星域结果可不填（默认用 id）
    var highlightRegionId: Int?
    let title: String
    let subtitle: String
    let accent: Color

    var regionToHighlight: Int {
        highlightRegionId ?? id
    }
}

// MARK: - 搜索结果浮层（配合系统 .searchable 使用）

struct StarMapSearchResultsOverlay: View {
    var results: [StarMapSearchResult]
    var onSelect: (StarMapSearchResult) -> Void

    var body: some View {
        if results.isEmpty {
            Text(NSLocalizedString("StarMap_No_Results", comment: "No matching results"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.prefix(8).enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack {
                            Text(item.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.subtitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < min(results.count, 8) - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
