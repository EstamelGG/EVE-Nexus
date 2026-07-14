import SwiftUI

struct OptimalAttributesSectionHeader: View {
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("Main_Skills_Optimal_Attributes", comment: ""))
            Spacer(minLength: 0)
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Main_Skills_Optimal_Attributes_Info_Title", comment: ""))
        }
        .sheet(isPresented: $showInfo) {
            OptimalAttributesInfoSheet()
        }
    }
}

struct OptimalAttributesInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(NSLocalizedString("Main_Skills_Optimal_Attributes_Info", comment: ""))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(NSLocalizedString("Main_Skills_Optimal_Attributes_Info_Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
