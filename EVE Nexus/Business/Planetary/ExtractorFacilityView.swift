import SwiftUI

/// 提取器设施视图
struct ExtractorFacilityView: View {
    let pin: PlanetaryPin
    let extractor: PlanetaryExtractor
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let currentTime: Date

    // 计算属性：判断采集器是否过期
    private var isExpired: Bool {
        guard let expiryTime = pin.expiryTime,
            let expiryDate = ISO8601DateFormatter().date(from: expiryTime)
        else {
            return false
        }
        return currentTime >= expiryDate
    }

    var body: some View {
        // 提取器基本信息
        HStack(alignment: .top, spacing: 12) {
            if let iconName = typeIcons[pin.typeId] {
                Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                // 设施名称
                Text(
                    "[\(PlanetaryFacility(identifier: pin.pinId).name)] \(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))"
                )
                .lineLimit(1)

                // 采集周期进度
                if let cycleTime = extractor.cycleTime, let installTime = pin.installTime {
                    let progress =
                        isExpired
                        ? 0
                        : calculateExtractorProgress(
                            installTime: installTime, cycleTime: cycleTime
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(height: 6)
                            .tint(isExpired ? Color.gray : Color(red: 0.0, green: 0.6, blue: 0.3))

                        // 显示当前周期时间
                        let elapsedTime =
                            isExpired
                            ? 0
                            : calculateElapsedTimeInCurrentCycle(
                                installTime: installTime, cycleTime: cycleTime
                            )
                        Text(
                            "\(formatTimeInterval(elapsedTime)) / \(formatTimeInterval(TimeInterval(cycleTime)))"
                        )
                        .foregroundColor(isExpired ? .gray : .secondary)
                        .font(.system(.footnote, design: .monospaced))
                    }
                }
            }
        }

        // 提取器产量图表
        if let installTime = pin.installTime {
            ExtractorYieldChartView(
                extractor: extractor,
                installTime: installTime,
                expiryTime: pin.expiryTime,
                currentTime: currentTime
            )
        }

        // 产出资源信息
        if let productTypeId = extractor.productTypeId, let qtyPerCycle = extractor.qtyPerCycle,
            let installTime = pin.installTime, let cycleTime = extractor.cycleTime
        {
            // 从ExtractorYieldCalculator获取当前周期的产出
            let currentCycle = ExtractorYieldCalculator.getCurrentCycle(
                installTime: installTime, expiryTime: pin.expiryTime ?? "", cycleTime: cycleTime
            )
            let calculator = ExtractorYieldCalculator(
                quantityPerCycle: qtyPerCycle, cycleTime: cycleTime
            )
            let currentYield =
                isExpired
                ? 0 : (currentCycle >= 0 ? calculator.calculateYield(cycleIndex: currentCycle) : 0)

            NavigationLink(
                destination: ShowPlanetaryInfo(
                    itemID: productTypeId, databaseManager: DatabaseManager.shared
                )
            ) {
                HStack(alignment: .center, spacing: 12) {
                    if let iconName = typeIcons[productTypeId] {
                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(
                                NSLocalizedString("Factory_Output", comment: "")
                                    + " \(typeNames[productTypeId] ?? "")")
                            Spacer()
                            Text("× \(currentYield)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    /// 计算提取器当前周期的进度
    /// - Parameters:
    ///   - installTime: 安装时间
    ///   - cycleTime: 周期时间（秒）
    /// - Returns: 进度值（0-1）
    private func calculateExtractorProgress(installTime: String, cycleTime: Int) -> Double {
        guard let installDate = ISO8601DateFormatter().date(from: installTime) else {
            return 0
        }

        let totalElapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleTimeInterval = TimeInterval(cycleTime)

        // 计算当前周期内已经过去的时间
        let elapsedInCurrentCycle = totalElapsedTime.truncatingRemainder(
            dividingBy: cycleTimeInterval)

        // 计算进度
        return elapsedInCurrentCycle / cycleTimeInterval
    }

    /// 计算当前周期内已经过去的时间
    /// - Parameters:
    ///   - installTime: 安装时间
    ///   - cycleTime: 周期时间（秒）
    /// - Returns: 已经过去的时间（秒）
    private func calculateElapsedTimeInCurrentCycle(installTime: String, cycleTime: Int)
        -> TimeInterval
    {
        guard let installDate = ISO8601DateFormatter().date(from: installTime) else {
            return 0
        }

        let totalElapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleTimeInterval = TimeInterval(cycleTime)

        // 计算当前周期内已经过去的时间
        return totalElapsedTime.truncatingRemainder(dividingBy: cycleTimeInterval)
    }

    /// 格式化时间间隔
    /// - Parameter interval: 时间间隔（秒）
    /// - Returns: 格式化后的字符串
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
