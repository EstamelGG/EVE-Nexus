import SwiftUI

struct ShipInsuranceView: View {
    let typeId: Int
    let typeName: String

    @State private var insuranceData: InsurancePriceItem?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    centeredProgress
                }
            } else if let errorMessage {
                Section {
                    centeredStatus(
                        systemImage: "exclamationmark.triangle",
                        color: .orange,
                        message: errorMessage
                    )
                }
            } else if let insurance = insuranceData {
                insuranceLevelsSection(insurance: insurance)
            } else {
                Section {
                    centeredStatus(
                        systemImage: "info.circle",
                        color: .gray,
                        message: NSLocalizedString("Insurance_No_Data", comment: "该飞船暂无保险数据")
                    )
                }
            }
        }
        .navigationTitle(NSLocalizedString("Insurance_Title", comment: "保险"))
        .task {
            await loadInsuranceData()
        }
    }

    private var centeredProgress: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func centeredStatus(systemImage: String, color: Color, message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundColor(color)
                Text(message)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func insuranceLevelsSection(insurance: InsurancePriceItem) -> some View {
        Section(
            header: Text(NSLocalizedString("Insurance_Levels", comment: "保险等级")).font(.headline)
        ) {
            ForEach(Array(insurance.levels.enumerated()), id: \.offset) { _, level in
                let netProfit = level.payout - level.cost
                VStack(alignment: .leading, spacing: 6) {
                    Text(level.localizedName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    iskRow(
                        title: NSLocalizedString("Insurance_Cost", comment: "保险费用"),
                        amount: level.cost,
                        color: .red
                    )
                    iskRow(
                        title: NSLocalizedString("Insurance_Payout", comment: "赔付金额"),
                        amount: level.payout,
                        color: .green
                    )
                    iskRow(
                        title: NSLocalizedString("Insurance_Net_Profit", comment: "净收益"),
                        amount: netProfit,
                        color: netProfit >= 0 ? .green : .red
                    )
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
            }
        }

        Section {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text(NSLocalizedString("Insurance_Info_Tip", comment: "保险赔付在飞船被摧毁时发放"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func iskRow(title: String, amount: Double, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Image("isk")
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(FormatUtil.formatISK(amount))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(color)
            }
        }
    }

    private func loadInsuranceData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let insurance = try await InsurancePricesAPI.shared.getInsurancePrice(for: typeId)
            await MainActor.run {
                insuranceData = insurance
                isLoading = false
            }
            if insurance != nil {
                Logger.info(" 成功加载飞船 \(typeName) 的保险数据")
            } else {
                Logger.warning("飞船 \(typeName) 没有保险数据")
            }
        } catch {
            Logger.error("加载飞船保险数据失败: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
