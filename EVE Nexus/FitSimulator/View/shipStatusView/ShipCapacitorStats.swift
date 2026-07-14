import SwiftUI

struct ShipCapacitorStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        if let ship = viewModel.simulationOutput?.ship {
            let capCapacity = ship.attributesByName["capacitorCapacity"] ?? 0

            // 获取电容抗性
            let energyWarfareResistance =
                (1 - (ship.attributesByName["energyWarfareResistance"] ?? 0)) * 100

            // 计算电容稳定性
            let (isCapStable, stableLevel, lastsTime, delta) = calculateCapacitorStability(
                ship: ship
            )

            Section {
                HStack {
                    // 左侧：容量和稳定性
                    HStack {
                        IconManager.shared.loadImage(for: "capacitor")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading) {
                            HStack {
                                Text(
                                    NSLocalizedString("Fitting_cap_capacity", comment: "总容量") + ":"
                                )
                                Text(formatCapacitor(capCapacity, unit: "GJ"))
                            }
                            Divider()
                            HStack {
                                if isCapStable {
                                    Text(
                                        NSLocalizedString("Fitting_cap_stable", comment: "稳定在")
                                            + ":"
                                    )
                                    Text(FormatUtil.formatForUI(stableLevel * 100) + "%")
                                        .foregroundColor(.green)
                                } else {
                                    Text(NSLocalizedString("Fitting_cap_time", comment: "持续") + ":")
                                    Text(formatTime(lastsTime))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 右侧：电容抗性和增减率
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(NSLocalizedString("Fitting_cap_delta", comment: "增减率") + ":")
                                Text(
                                    "\(delta > 0 ? "+" : "")\(formatCapacitor(delta, unit: "GJ/s"))"
                                )
                                .foregroundColor(delta >= 0 ? .green : .red)
                            }
                            Divider()
                            HStack {
                                Text(
                                    NSLocalizedString("Fitting_cap_resistance", comment: "电容抗性")
                                        + ":"
                                )
                                Text(FormatUtil.formatForUI(energyWarfareResistance) + "%")
                            }
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .lineLimit(1)
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text(NSLocalizedString("Fitting_stat_capacitor", comment: "电容"))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .font(.system(size: 18))
                    Spacer()
                }
            }
        }
    }

    /// 计算电容稳定性
    private func calculateCapacitorStability(ship: SimShipOutput) -> (
        isStable: Bool, stableLevel: Double, lastsTime: Double, delta: Double
    ) {
        // 获取必要的属性
        let capCapacity = ship.attributesByName["capacitorCapacity"] ?? 0
        let capRechargeTimeMs = ship.attributesByName["rechargeRate"] ?? 0

        // 将毫秒转换为秒
        let capRechargeTime = capRechargeTimeMs / 1000.0

        Logger.info(
            "【电容计算】飞船电容量: \(capCapacity) GJ, 充能时间: \(capRechargeTimeMs) ms (\(capRechargeTime) s)"
        )

        // 计算模块的电容使用量
        var moduleData: [(cycleTime: Double, capNeed: Double, powerTransferAmount: Double)] = []
        var totalCapUse: Double = 0
        // 添加电容回充装置的总回充速度
        var totalCapBoost: Double = 0

        Logger.info("【电容计算】模块电容消耗详情:")

        // 使用simulationOutput中的模块数据而不是simulationInput
        for (index, module) in viewModel.simulationOutput?.modules.enumerated() ?? [].enumerated() {
            if module.status > 1 {
                // 检查是否为电容回充装置(groupID=76)
                if module.groupID == 76, module.charge != nil {
                    // 处理电容回充装置
                    let boostRate = setCapRebooster(module: module)
                    totalCapBoost += boostRate
                    Logger.info("  模块 \(index + 1): \(module.name) - 电容回充装置，每秒回充: \(boostRate) GJ/s")
                    continue // 注电器带来的电容回充量需单独计算
                }

                // 获取模块属性
                let capNeed = module.attributesByName["capacitorNeed"] ?? 0

                // 只有能量转移装置(groupID=68)才获取powerTransferAmount属性
                let selfPowerTransferAmount =
                    module.groupID == 68 ? (module.attributesByName["powerTransferAmount"] ?? 0) : 0

                // 记录能量转移装置信息
                if module.groupID == 68, selfPowerTransferAmount > 0 {
                    Logger.info(
                        "  模块 \(index + 1): \(module.name) - 能量吸取装置，能量转移量: \(selfPowerTransferAmount) GJ"
                    )
                }

                // max ("speed", "duration", "durationHighisGood", "durationSensorDampeningBurstProjector", "durationTargetIlluminationBurstProjector", "durationECMJammerBurstProjector", "durationWeaponDisruptionBurstProjector")
                let speedMs = module.attributesByName["speed"] ?? 0
                let durationMs = module.attributesByName["duration"] ?? 0
                let durationHighisGoodMs = module.attributesByName["durationHighisGood"] ?? 0
                let durationSensorDampeningBurstProjectorMs =
                    module.attributesByName["durationSensorDampeningBurstProjector"] ?? 0
                let durationTargetIlluminationBurstProjectorMs =
                    module.attributesByName["durationTargetIlluminationBurstProjector"] ?? 0
                let durationECMJammerBurstProjectorMs =
                    module.attributesByName["durationECMJammerBurstProjector"] ?? 0
                let durationWeaponDisruptionBurstProjectorMs =
                    module.attributesByName["durationWeaponDisruptionBurstProjector"] ?? 0
                let module_round_speed = max( // 不同装备使用不同的属性来表达运转时间
                    speedMs,
                    durationMs,
                    durationHighisGoodMs,
                    durationSensorDampeningBurstProjectorMs,
                    durationTargetIlluminationBurstProjectorMs,
                    durationECMJammerBurstProjectorMs,
                    durationWeaponDisruptionBurstProjectorMs
                )
                let reactivationDelayMs = module.attributesByName["moduleReactivationDelay"] ?? 0

                // 将毫秒转换为秒
                let duration = module_round_speed / 1000.0
                let reactivationDelay = reactivationDelayMs / 1000.0

                if duration > 0 {
                    let fullCycleTime = duration + reactivationDelay
                    let capConsumePerSecond = capNeed / fullCycleTime
                    let selfPowerTransferPerSecond = selfPowerTransferAmount / fullCycleTime

                    // 净电容变化 = 能量转移 - 电容消耗
                    let netCapChangePerSecond = selfPowerTransferPerSecond - capConsumePerSecond

                    totalCapUse += capConsumePerSecond
                    totalCapBoost += selfPowerTransferPerSecond

                    // 保存模块数据用于详细模拟 - 分别存储消耗和转移量
                    moduleData.append(
                        (
                            cycleTime: fullCycleTime, capNeed: capNeed,
                            powerTransferAmount: selfPowerTransferAmount
                        )
                    )
                    Logger.info(
                        "  模块 \(index + 1): \(module.name) - 单次消耗: \(capNeed) GJ, 能量转移: \(selfPowerTransferAmount) GJ, 净变化: \(selfPowerTransferAmount - capNeed) GJ, 周期: \(module_round_speed) ms (\(duration) s), 重激活延迟: \(reactivationDelayMs) ms (\(reactivationDelay) s), 每秒净变化: \(netCapChangePerSecond) GJ/s"
                    )
                }
            }
        }

        Logger.info("【电容计算】总电容消耗率: \(totalCapUse) GJ/s")
        Logger.info("【电容计算】电容回充装置回充率: \(totalCapBoost) GJ/s")

        // 计算最大电容充能率（在25%电容时）
        let peakRechargePercent = 0.25
        let capRecharge = calculateCapRecharge(
            capacity: capCapacity, rechargeTime: capRechargeTime, percent: peakRechargePercent
        )

        Logger.info("【电容计算】峰值电容充能率(25%): \(capRecharge) GJ/s")

        // 计算净增减率（包含电容回充装置的贡献）
        let delta = capRecharge + totalCapBoost - totalCapUse

        Logger.info("【电容计算】电容净增减率: \(delta) GJ/s")

        // 判断是否稳定
        let isStable = delta >= 0

        Logger.info("【电容计算】电容是否稳定: \(isStable)")

        // 如果稳定，计算稳定水平
        var stableLevel: Double = 0
        var lastsTime: Double = 0

        if isStable {
            // 使用二分法查找稳定水平
            stableLevel = findStableCapLevel(
                capacity: capCapacity, rechargeTime: capRechargeTime,
                capUse: totalCapUse - totalCapBoost
            )
            Logger.info("【电容计算】稳定电容水平: \(stableLevel * 100)%")
        } else {
            // 如果不稳定，使用更精确的模拟计算持续时间
            lastsTime = simulateCapacitorDepletion(
                capacity: capCapacity,
                rechargeTime: capRechargeTime,
                moduleData: moduleData,
                startingPercent: 1.0, // 从100%开始
                capBoostRate: totalCapBoost // 传入电容回充装置的回充率
            )
            Logger.info("【电容计算】电容持续时间: \(formatTime(lastsTime))")
        }

        return (isStable, stableLevel, lastsTime, delta)
    }

    /// 补丁函数，处理电容回充装置
    private func setCapRebooster(module: SimModuleOutput) -> Double {
        guard let charge = module.charge else { return 0 }

        // 获取必要的属性
        let capacitorBonus = charge.attributesByName["capacitorBonus"] ?? 0 // 单个电容回充量
        let chargeQuantity = charge.chargeQuantity ?? 0 // 弹药数量，解包可选类型

        // 获取周期时间
        let speedMs = module.attributesByName["speed"] ?? 0
        let durationMs = module.attributesByName["duration"] ?? 0
        let module_round_speed = max(speedMs, durationMs) // 运转时间
        let reloadTimeMs = module.attributesByName["reloadTime"] ?? 0 // 装填时间

        // 获取每次消耗的弹药数量
        let chargeRate = module.attributesByName["chargeRate"] ?? 1.0 // 默认为1，表示每次消耗1个弹药

        // 将毫秒转换为秒，并考虑弹药数量
        let duration = module_round_speed / 1000.0 // 单次运转时间（秒）

        // 计算实际可用的弹药循环次数
        let actualCycles = Double(chargeQuantity) / chargeRate

        // 总周期时间 = 运转时间*实际循环次数 + 装填时间
        let cycleTime = (duration * actualCycles) + (reloadTimeMs / 1000.0)

        // 计算回充速度
        let totalBoost = Double(chargeQuantity) * capacitorBonus // 总回充量，确保类型一致
        let boostRate = totalBoost / cycleTime // 每秒回充率

        Logger.info(
            "【电容注入器】名称: \(module.name), 弹药: \(charge.name), 单次回充: \(capacitorBonus) GJ, 弹药数量: \(chargeQuantity), 每次消耗: \(chargeRate) 个, 实际循环次数: \(actualCycles), 单次运转: \(duration) s, 总周期: \(cycleTime) s, 每秒回充: \(boostRate) GJ/s"
        )

        return boostRate
    }

    /// 计算电容充能率（使用EVE真实公式）
    private func calculateCapRecharge(
        capacity: Double, rechargeTime: Double, percent: Double = 0.25
    ) -> Double {
        // EVE电容充能公式：GJ/s = 10 * capacity / rechargeTime * sqrt(percent) * (1 - sqrt(percent))
        return 10.0 * capacity / rechargeTime * sqrt(percent) * (1.0 - sqrt(percent))
    }

    /// 使用二分法查找稳定的电容水平
    private func findStableCapLevel(capacity: Double, rechargeTime: Double, capUse: Double)
        -> Double
    {
        var low = 0.0
        var high = 1.0
        let epsilon = 0.0001

        // 记录二分查找过程
        Logger.info("【电容计算】开始二分查找稳定点:")

        // 二分查找稳定点
        var iterations = 0
        while high - low > epsilon && iterations < 50 {
            let mid = (low + high) / 2
            let recharge = calculateCapRecharge(
                capacity: capacity, rechargeTime: rechargeTime, percent: mid
            )

            Logger.info(
                "  迭代 \(iterations + 1): 电容水平 \(mid * 100)%, 充能率 \(recharge) GJ/s, 消耗率 \(capUse) GJ/s"
            )

            if recharge > capUse {
                low = mid
            } else if recharge < capUse {
                high = mid
            } else {
                Logger.info("  找到精确解: \(mid * 100)%")
                return mid
            }

            iterations += 1
        }

        let result = (low + high) / 2
        Logger.info("  二分查找结果: \(result * 100)%")
        return result
    }

    /// 参考Pyfa CapSimulator的电容模拟实现
    private func simulateCapacitorDepletion(
        capacity: Double, rechargeTime: Double,
        moduleData: [(cycleTime: Double, capNeed: Double, powerTransferAmount: Double)],
        startingPercent: Double = 1.0, capBoostRate: Double = 0.0
    ) -> Double {
        let tau = rechargeTime / 5.0
        let maxSimTime = 8.0 * 3600.0 * 1000.0 // 8小时，毫秒单位
        let _ = 300.0 * 1000.0 // 5分钟详细日志

        var currentCap = capacity * startingPercent
        var _ = 0.0 // 毫秒
        var lastTime = 0.0
        var capLowest = currentCap
        var iterations = 0

        // 使用优先队列存储激活事件
        var activationQueue:
            [(
                time: Double, duration: Double, capNeed: Double, shot: Int, moduleIndex: Int,
                powerTransferAmount: Double
            )] = []

        Logger.info(
            "【电容计算】开始电容模拟 - 起始电容: \(FormatUtil.formatForUI(currentCap, maxFractionDigits: 2)) GJ (\(FormatUtil.formatForUI(startingPercent * 100, maxFractionDigits: 2))%)"
        )

        // 初始化模块激活队列
        for (index, module) in moduleData.enumerated() {
            let durationMs = module.cycleTime * 1000.0 // 转换为毫秒
            activationQueue.append(
                (
                    time: 0.0,
                    duration: durationMs,
                    capNeed: module.capNeed,
                    shot: 0,
                    moduleIndex: index,
                    powerTransferAmount: module.powerTransferAmount
                )
            )
        }

        // 按时间排序（优先队列）
        activationQueue.sort { $0.time < $1.time }

        // 主模拟循环
        while !activationQueue.isEmpty && iterations < 100_000 {
            let activation = activationQueue.removeFirst()

            let timeNow = activation.time
            let duration = activation.duration
            let capNeed = activation.capNeed
            let shot = activation.shot
            let moduleIndex = activation.moduleIndex
            let powerTransferAmount = activation.powerTransferAmount

            // 超过最大模拟时间，停止
            if timeNow >= maxSimTime {
                break
            }

            // 从上次时间点恢复电容
            if timeNow > lastTime {
                let timeDeltaSeconds = (timeNow - lastTime) / 1000.0
                let percent = currentCap / capacity
                currentCap =
                    ((1.0 + (sqrt(percent) - 1.0) * exp(-timeDeltaSeconds / tau)) ** 2) * capacity

                // 添加电容回充装置的贡献
                let boostAmount = capBoostRate * timeDeltaSeconds
                currentCap = min(currentCap + boostAmount, capacity)
            }

            lastTime = timeNow
            iterations += 1

            // 记录电容低点（激活前）
            if currentCap < capLowest {
                capLowest = currentCap
            }

            // 简化日志记录（仅前30秒）
            if timeNow <= 30000 {
                Logger.info(
                    "  时间 \(formatTime(timeNow / 1000.0)): 模块 \(moduleIndex + 1) 激活 - 消耗: \(FormatUtil.formatForUI(capNeed, maxFractionDigits: 1)) GJ, 电容: \(FormatUtil.formatForUI(currentCap, maxFractionDigits: 1)) GJ"
                )
            }

            // 应用电容消耗
            currentCap -= capNeed

            // 如果电容不足，模拟结束
            if currentCap < 0.0 {
                Logger.info("【电容计算】电容耗尽，持续时间: \(formatTime(timeNow / 1000.0))")
                return timeNow / 1000.0
            }

            // 记录电容低点（激活后）
            if currentCap < capLowest {
                capLowest = currentCap
            }

            // 处理能量转移（Nosferatu等）- 在激活完成时获得电容
            if powerTransferAmount > 0 {
                let activationEndTime = timeNow + duration

                // 计算到激活结束时的电容恢复
                let endTimeDeltaSeconds = duration / 1000.0
                let percentAtActivation = currentCap / capacity
                let capAtEnd =
                    ((1.0 + (sqrt(percentAtActivation) - 1.0) * exp(-endTimeDeltaSeconds / tau))
                            ** 2) * capacity
                let boostAtEnd = capBoostRate * endTimeDeltaSeconds
                let capBeforeTransfer = min(capAtEnd + boostAtEnd, capacity)

                // 添加能量转移
                let _ = min(capBeforeTransfer + powerTransferAmount, capacity)

                if activationEndTime <= 30000 {
                    Logger.info(
                        "  时间 \(formatTime(activationEndTime / 1000.0)): 模块 \(moduleIndex + 1) 完成 - 获得: \(FormatUtil.formatForUI(powerTransferAmount, maxFractionDigits: 1)) GJ"
                    )
                }
            }

            // 安排下一次激活
            let nextActivationTime = timeNow + duration
            let nextActivation = (
                time: nextActivationTime,
                duration: duration,
                capNeed: capNeed,
                shot: shot + 1,
                moduleIndex: moduleIndex,
                powerTransferAmount: powerTransferAmount
            )

            // 插入到正确位置以保持排序
            var insertIndex = 0
            while insertIndex < activationQueue.count
                && activationQueue[insertIndex].time <= nextActivationTime
            {
                insertIndex += 1
            }
            activationQueue.insert(nextActivation, at: insertIndex)
        }

        Logger.info(
            "【电容计算】模拟完成 - 迭代次数: \(iterations), 最低电容: \(FormatUtil.formatForUI(capLowest, maxFractionDigits: 2)) GJ (\(FormatUtil.formatForUI(capLowest / capacity * 100, maxFractionDigits: 2))%)"
        )

        // 如果电容始终为正，则认为是稳定的
        return capLowest > 0 ? Double.infinity : lastTime / 1000.0
    }

    /// 格式化电容值
    private func formatCapacitor(_ value: Double, unit: String) -> String {
        return FormatUtil.formatForUI(value, maxFractionDigits: 2) + " " + unit
    }

    /// 格式化时间
    private func formatTime(_ seconds: Double) -> String {
        if seconds == Double.infinity {
            return "∞"
        }

        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %02dm", hours, minutes)
        }
    }
}

// 扩展Double以支持平方运算符
infix operator **: MultiplicationPrecedence
extension Double {
    static func ** (lhs: Double, rhs: Double) -> Double {
        return pow(lhs, rhs)
    }
}
