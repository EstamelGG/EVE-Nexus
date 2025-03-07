import SwiftUI

struct ResearchLevelTimeView: View {
    let title: String
    let rank: Int

    // 每个等级的基础时间乘数
    private let levelMultipliers = [
        105, 250, 595, 1414, 3360, 8000, 19000, 45255, 107_700, 256_000,
    ]

    // 计算特定等级的实际时间
    private func calculateTime(for level: Int) -> Int {
        return levelMultipliers[level - 1] * rank
    }

    var body: some View {
        List {
            ForEach(1...10, id: \.self) { level in
                HStack {
                    Text("Level \(level)")
                    Spacer()
                    Text(formatTime(calculateTime(for: level)))
                        .foregroundColor(.secondary)
                        .frame(alignment: .trailing)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}
