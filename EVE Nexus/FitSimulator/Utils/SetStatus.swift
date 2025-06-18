import Foundation

/// 设置模块状态
/// - Parameters:
///   - itemAttributes: 装备的所有属性 [attribute_id: value]
///   - itemAttributesName: 装备的属性名称字典 [name: value]
///   - typeId: 装备的 type_id
///   - typeGroupId: 装备的 group_id
///   - currentModules: 当前已安装的模块列表
///   - currentStatus: 当前状态
///   - maxStatus: 最大可用状态
///   - calculatedAttributesName: 计算后的属性名称字典（可选）
/// - Returns: 设置后的状态
func setStatus(
    itemAttributes: [Int: Double],
    itemAttributesName: [String: Double],
    typeId: Int,
    typeGroupId: Int,
    currentModules: [SimModule],
    currentStatus: Int,
    maxStatus: Int,
    calculatedAttributesName: [String: Double]? = nil
) -> Int {
    // 获取maxGroupOnline和maxGroupActive属性
    // 优先使用计算后的属性，如果没有则使用原始属性
    let attributesToUse = calculatedAttributesName ?? itemAttributesName
    let maxGroupOnline = Int(attributesToUse["maxGroupOnline"] ?? 0)  // 同组装备可以同时在线(online)的最大数量
    let maxGroupActive = Int(attributesToUse["maxGroupActive"] ?? 0)  // 同组装备可以同时激活(active)的最大数量

    Logger.info(
        """
        [setStatus]装备状态检查:
        - 装备ID: \(typeId)
        - 组ID: \(typeGroupId)
        - maxGroupOnline: \(maxGroupOnline)
        - maxGroupActive: \(maxGroupActive)
        - 当前状态: \(currentStatus)
        - 最大可用状态: \(maxStatus)
        """)

    // 使用ModuleGroupManager验证状态
    let validatedStatus = ModuleGroupManager.validateStatus(
        targetStatus: currentStatus,
        groupID: typeGroupId,
        maxGroupOnline: maxGroupOnline,
        maxGroupActive: maxGroupActive,
        currentModules: currentModules
    )

    // 确保新状态不超过最大可用状态
    let finalStatus = min(validatedStatus, maxStatus)

    Logger.info("[setStatus]最终状态: \(finalStatus)")
    return finalStatus
}
