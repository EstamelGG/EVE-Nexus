import SwiftUI

/// 剪贴板导入导出 + 数量编辑
extension MarketQuickbarDetailView {
    enum ClipboardImportMergeMode {
        case replace
        case append
    }

    func applyQuantityEditFromAlert() {
        guard let tid = quantityEditTypeID else {
            quantityEditText = ""
            return
        }
        let trimmed = quantityEditText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int64(trimmed), value >= 1, value <= 999_999_999 else {
            quantityEditTypeID = nil
            quantityEditText = ""
            return
        }
        if let idx = quickbar.items.firstIndex(where: { $0.typeID == tid }) {
            quickbar.items[idx].quantity = value
            itemQuantities[tid] = value
        }
        MarketQuickbarManager.shared.saveQuickbar(quickbar)
        quantityEditTypeID = nil
        quantityEditText = ""
        Task {
            await loadAllMarketOrders()
        }
    }

    /// 准备从剪贴板导入物品（显示确认对话框）
    func prepareImportFromClipboard() {
        guard let clipboardContent = UIPasteboard.general.string else {
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
            return
        }

        // 检查剪贴板内容是否为空
        if clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
            return
        }

        // 存储剪贴板内容
        clipboardContentToImport = clipboardContent

        if quickbar.items.isEmpty {
            importFromClipboard(mode: .replace)
        } else {
            showClipboardImportModeDialog = true
        }
    }

    /// 从剪贴板导入物品
    func importFromClipboard(mode: ClipboardImportMergeMode) {
        guard !clipboardContentToImport.isEmpty else {
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
            return
        }

        let importResult = MarketClipboardParser.parseClipboardContent(
            clipboardContentToImport,
            databaseManager: databaseManager
        )

        // 根据解析结果处理不同情况
        if importResult.successCount == 0, importResult.failedItems.isEmpty {
            // 情况1: 剪贴板内容为空或无有效内容
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
        } else if importResult.successCount == 0, importResult.failedItems.count > 0 {
            // 情况2: 全部解析失败
            clipboardResult = NSLocalizedString(
                "Main_Market_Clipboard_All_Failed", comment: "全部解析失败"
            )
            isShowingClipboardAlert = true
        } else if importResult.successCount > 0 {
            let mergedItems: [QuickbarItem] = {
                switch mode {
                case .replace:
                    return importResult.updatedItems
                case .append:
                    return MarketQuickbarDestinationPicker.mergeQuickbarItems(
                        existing: quickbar.items,
                        imported: importResult.updatedItems
                    )
                }
            }()

            // 情况3和4: 有成功的解析结果，更新列表（若种类超过上限则从末尾裁剪）
            quickbar.items = mergedItems
            let typeLimitTrimmed = MarketQuickbarDestinationPicker.trimToMaxDistinctTypesRemovingFromEnd(
                &quickbar.items
            )

            // 保存更改
            MarketQuickbarManager.shared.saveQuickbar(quickbar)
            // 重新加载物品列表
            loadItems()
            // 重新加载物品体积信息
            loadItemVolumes()
            // 重新加载市场订单
            Task {
                await loadAllMarketOrders()
            }

            if importResult.failedItems.count > 0 {
                // 情况3: 部分成功，部分失败
                var resultMessage = String(
                    format: NSLocalizedString("Main_Market_Clipboard_Partial_Success", comment: ""),
                    importResult.successCount
                )

                // 显示失败的前三行内容
                let failedToShow = Array(importResult.failedItems.prefix(3))
                if !failedToShow.isEmpty {
                    resultMessage +=
                        "\n\n"
                        + NSLocalizedString(
                            "Main_Market_Clipboard_Failed_Items", comment: "解析失败的项目:"
                        )
                    resultMessage += "\n" + failedToShow.joined(separator: "\n")

                    // 如果失败项目超过3个，显示省略提示
                    if importResult.failedItems.count > 3 {
                        resultMessage += "\n..."
                        resultMessage += String(
                            format: NSLocalizedString(
                                "Main_Market_Clipboard_More_Failed", comment: ""
                            ),
                            importResult.failedItems.count - 3
                        )
                    }
                }

                clipboardResult = resultMessage
            } else {
                // 情况4: 全部成功
                clipboardResult = String(
                    format: NSLocalizedString("Main_Market_Clipboard_All_Success", comment: ""),
                    importResult.successCount
                )
            }

            if typeLimitTrimmed {
                clipboardResult += "\n\n"
                    + String(
                        format: NSLocalizedString(
                            "Main_Market_Watch_List_Type_Limit_Message",
                            comment: ""
                        ),
                        MarketQuickbarDestinationPicker.maxDistinctTypeCount
                    )
            }

            isShowingClipboardAlert = true
        }

        clipboardContentToImport = "" // 清空临时存储的内容
    }

    /// 导出到剪贴板
    func exportToClipboard() {
        // 构建导出内容：物品名称和数量，以\t分割
        var exportLines: [String] = []

        for quickbarItem in quickbar.items {
            // 查找对应的物品信息
            if let item = items.first(where: { $0.id == quickbarItem.typeID }) {
                let line = "\(item.name)\t\(quickbarItem.quantity)"
                exportLines.append(line)
            }
        }

        // 将所有行合并为一个字符串，以换行符分隔
        let exportContent = exportLines.joined(separator: "\n")

        // 复制到剪贴板
        UIPasteboard.general.string = exportContent

        // 显示导出结果
        exportResult = String(
            format: NSLocalizedString("Main_Market_Clipboard_Export_Success", comment: ""),
            exportLines.count
        )
        isShowingExportAlert = true

        Logger.success("成功导出 \(exportLines.count) 个物品到剪贴板")
    }
}
