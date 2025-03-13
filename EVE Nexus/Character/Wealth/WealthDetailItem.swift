import Foundation

struct WealthDetailItem: Identifiable {
    let id = UUID()
    let typeId: Int
    let name: String
    let quantity: Int
    let value: Double
    let iconFileName: String

    var formattedValue: String {
        return FormatUtil.formatISK(value)
    }
}
