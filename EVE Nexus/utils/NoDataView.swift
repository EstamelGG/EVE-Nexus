import SwiftUI

struct NoDataSection: View {
    var icon: String = "exclamationmark.triangle"
    var text: String = NSLocalizedString("Misc_No_Data", comment: "")

    var body: some View {
        Section {
            ContentUnavailableView {
                Label(text, systemImage: icon)
            }
        }
    }
}
