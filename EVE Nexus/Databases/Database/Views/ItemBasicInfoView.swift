import SwiftUI

struct ItemBasicInfoView: View {
    let itemDetails: ItemDetails
    @State private var renderImage: UIImage?
    @ObservedObject var databaseManager: DatabaseManager
    let modifiedAttributes: [Int: Double]?

    // 监听屏幕方向变化
    @State private var orientation = UIDevice.current.orientation

    // 布局状态标识符（用于判断是否需要重新渲染视图）
    @State private var layoutMode: LayoutMode = .portrait

    // 存储市场目录路径
    @State private var marketPath: String = ""

    // 保存图片状态
    @State private var showSaveSuccess = false
    @State private var showSaveError = false

    // 模型可用性状态
    @State private var isModelAvailable: Bool = false

    // iOS 标准圆角半径
    private let cornerRadius: CGFloat = 10
    // 标准边距
    private let standardPadding: CGFloat = 16

    // 判断是否应该使用小图模式（横屏或iPad）
    private var shouldUseCompactLayout: Bool {
        DeviceUtils.shouldUseCompactLayout
    }

    // 获取图片尺寸
    private var imageSize: CGFloat {
        if DeviceUtils.isIPad {
            return 256 // iPad使用256尺寸
        } else if DeviceUtils.isIPhoneLandscape {
            return 128 // 横屏iPhone使用128尺寸
        } else {
            return 128 // 默认尺寸
        }
    }

    // 获取修改后的属性值，如果没有则返回原始值
    private func getAttributeValue(attributeId: Int, originalValue: Double?) -> Double? {
        if let modifiedValue = modifiedAttributes?[attributeId] {
            return modifiedValue
        }
        return originalValue
    }

    // 获取属性值的颜色
    private func getAttributeColor(attributeId: Int, originalValue: Double?) -> Color {
        guard let originalValue = originalValue,
              let modifiedValue = modifiedAttributes?[attributeId]
        else {
            return .secondary
        }

        if abs(modifiedValue - originalValue) < 0.0001 {
            return .secondary // 没有变化
        }

        // 对于 mass 和 capacity，通常值越大越好（capacity）或越小越好（mass）
        // mass(4): 质量，越小越好，所以 highIsGood = false
        // capacity(38): 容量，越大越好，所以 highIsGood = true
        let highIsGood = (attributeId == 38) // capacity 是 highIsGood

        if highIsGood {
            return modifiedValue > originalValue ? .green : .red
        } else {
            return modifiedValue < originalValue ? .green : .red
        }
    }

    // 保存渲染图到相册
    private func saveRenderImageToPhotos() {
        guard let renderImage = renderImage else { return }

        ImageSaver.saveImage(renderImage) { success in
            if success {
                self.showSaveSuccess = true
            } else {
                self.showSaveError = true
            }
        }
    }

    // 获取市场目录路径
    private func fetchMarketPath(for marketGroupID: Int?) {
        guard let marketGroupID = marketGroupID else {
            marketPath = ""
            return
        }

        Task {
            do {
                let path = try await getMarketGroupPath(groupID: marketGroupID)
                await MainActor.run {
                    self.marketPath = path.joined(separator: " / ")
                }
            } catch {
                Logger.error("获取市场目录路径失败: \(error.localizedDescription)")
                await MainActor.run {
                    self.marketPath = ""
                }
            }
        }
    }

    // 递归获取市场目录路径
    private func getMarketGroupPath(groupID: Int) async throws -> [String] {
        var path: [String] = []
        var currentGroupID = groupID
        var iterations = 0
        let maxIterations = 100 // 设置最大递归深度，避免无限循环

        while currentGroupID != 0, iterations < maxIterations {
            iterations += 1 // 增加迭代计数

            // 查询市场组信息
            let query = "SELECT name, parentgroup_id FROM marketGroups WHERE group_id = ?"
            let result = databaseManager.executeQuery(query, parameters: [currentGroupID])

            switch result {
            case let .success(rows):
                guard let row = rows.first,
                      let name = row["name"] as? String
                else {
                    return path // 如果找不到数据，直接返回当前路径
                }

                // 添加当前组名称到路径
                path.insert(name, at: 0)

                // 获取父组ID，如果为nil或0则结束循环
                if let parentGroupID = row["parentgroup_id"] as? Int, parentGroupID > 0 {
                    // 检查是否形成循环引用（子项引用了已经在路径中的父项）
                    if parentGroupID == currentGroupID || path.count >= maxIterations {
                        Logger.warning("检测到可能的循环引用或过深的市场目录路径，中止查询")
                        return path
                    }
                    currentGroupID = parentGroupID
                } else {
                    return path // 找到了顶级分类，返回路径
                }
            case let .error(error):
                Logger.error("查询市场组信息失败: \(error)")
                return path // 查询出错，返回已收集的路径
            }
        }

        // 如果达到最大迭代次数，记录警告
        if iterations >= maxIterations {
            Logger.warning("市场目录路径查询达到最大迭代次数 \(maxIterations)，可能存在循环引用")
        }

        return path
    }

    // MARK: - 布局视图函数

    // 小图布局（横屏或iPad）
    @ViewBuilder
    private func compactLayoutView(renderImage: UIImage) -> some View {
        HStack(alignment: .center) {
            Image(uiImage: renderImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: imageSize, height: imageSize)
                .cornerRadius(cornerRadius)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(itemDetails.name)
                    .font(.title)
                    .lineLimit(2)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = itemDetails.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                        if let en_detail = itemDetails.en_name, !en_detail.isEmpty,
                           en_detail != itemDetails.name
                        {
                            Button {
                                UIPasteboard.general.string = itemDetails.en_name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                    systemImage: "translate"
                                )
                            }
                        }
                        Button {
                            saveRenderImageToPhotos()
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Save_Render_Image", comment: ""),
                                systemImage: "photo"
                            )
                        }
                    }

                Text(
                    "\(NSLocalizedString("Main_Database_Category", comment: "")): \(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

                // 显示市场目录路径（如果有）
                if !marketPath.isEmpty {
                    Text(
                        "\(NSLocalizedString("Main_Database_Market_Category", comment: "")): \(marketPath)"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                }
            }
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // 渲染图大图布局（竖屏手机）
    @ViewBuilder
    private func renderImageLayoutView(renderImage: UIImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: renderImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .cornerRadius(cornerRadius)
                .padding(.horizontal, standardPadding)
                .padding(.vertical, standardPadding)

            // 物品信息覆盖层
            VStack(alignment: .leading, spacing: 4) {
                Text(itemDetails.name)
                    .font(.title)
                Text(
                    "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                )
                .font(.subheadline)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = itemDetails.name
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc"
                    )
                }
                if let en_detail = itemDetails.en_name, !en_detail.isEmpty,
                   en_detail != itemDetails.name
                {
                    Button {
                        UIPasteboard.general.string = itemDetails.en_name
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Trans", comment: ""),
                            systemImage: "translate"
                        )
                    }
                }
                Button {
                    saveRenderImageToPhotos()
                } label: {
                    Label(
                        NSLocalizedString("Misc_Save_Render_Image", comment: ""),
                        systemImage: "photo"
                    )
                }
            }
            .padding(.horizontal, standardPadding * 2)
            .padding(.vertical, standardPadding)
            .background(
                Color.black.opacity(0.5)
                    .cornerRadius(cornerRadius, corners: [.bottomLeft, .topRight])
            )
            .foregroundColor(.white)
            .padding(.horizontal, standardPadding)
            .padding(.bottom, standardPadding)
        }
        .listRowInsets(EdgeInsets()) // 移除 List 的默认边距
    }

    // 原始布局（无渲染图时的回退布局）
    @ViewBuilder
    private func originalLayoutView() -> some View {
        HStack {
            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(itemDetails.name)
                    .font(.title)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = itemDetails.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                        if let en_name = itemDetails.en_name, en_name != itemDetails.name,
                           !en_name.isEmpty
                        {
                            Button {
                                UIPasteboard.general.string = itemDetails.en_name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                    systemImage: "translate"
                                )
                            }
                        }
                    }
                Text(
                    "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                )
                .font(.subheadline)
                .foregroundColor(.gray)
            }
        }
    }

    var body: some View {
        Group {
            Section {
                if let renderImage = renderImage {
                    if shouldUseCompactLayout {
                        // 小图模式（横屏或iPad）
                        compactLayoutView(renderImage: renderImage)
                    } else {
                        // 渲染图大图布局（竖屏手机）
                        renderImageLayoutView(renderImage: renderImage)
                    }
                } else {
                    // 原始布局（无渲染图时的回退布局）
                    originalLayoutView()
                }

                let desc = itemDetails.description
                if !desc.isEmpty {
                    RichTextView(text: desc, databaseManager: databaseManager)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            .onAppear {
                layoutMode = DeviceUtils.currentLayoutMode
                loadRenderImage(for: itemDetails.typeId)
                // 调试输出移到这里
                Logger.debug(
                    "物品 \(itemDetails.name) 的 marketGroupID: \(String(describing: itemDetails.marketGroupID))"
                )
                if let marketGroupID = itemDetails.marketGroupID {
                    Logger.debug("显示市场按钮，marketGroupID: \(marketGroupID)")
                    // 如果是小图模式，获取市场目录路径
                    if shouldUseCompactLayout {
                        fetchMarketPath(for: marketGroupID)
                    }
                }

                // 检查模型是否可用
                checkModelAvailability()

                // 设置方向变化通知
                setupOrientationNotification()
            }
            .onDisappear {
                // 移除方向变化通知
                removeOrientationNotification()
            }
            .alert(
                NSLocalizedString("Misc_Save_Render_Image", comment: ""), isPresented: $showSaveSuccess
            ) {
                Button("OK") {}
            } message: {
                Text(NSLocalizedString("Misc_Save_Render_Image_Success", comment: ""))
            }
            .alert(
                NSLocalizedString("Misc_Save_Render_Image_Error_Title", comment: ""),
                isPresented: $showSaveError
            ) {
                Button("OK") {}
            } message: {
                Text(NSLocalizedString("Misc_Save_Render_Image_Error", comment: ""))
            }
            // 使用布局模式而非方向作为视图ID
            .id(layoutMode)
            // 当布局模式变化时，决定是否需要获取市场路径
            .onChange(of: shouldUseCompactLayout) { _, newValue in
                if newValue && marketPath.isEmpty && itemDetails.marketGroupID != nil {
                    fetchMarketPath(for: itemDetails.marketGroupID)
                }
            }

            // 市场详情 Section
            if itemDetails.marketGroupID != nil || isModelAvailable {
                Section {
                    if itemDetails.marketGroupID != nil {
                        NavigationLink {
                            MarketItemDetailView(
                                databaseManager: databaseManager,
                                itemID: itemDetails.typeId
                            )
                        } label: {
                            HStack {
                                Image("isk")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(NSLocalizedString("Main_Market", comment: ""))
                                Spacer()
                            }
                        }
                    }

                    if itemDetails.categoryID == 6 {
                        NavigationLink {
                            ShipInsuranceView(
                                typeId: itemDetails.typeId,
                                typeName: itemDetails.name
                            )
                        } label: {
                            HStack {
                                Image("insurance")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(NSLocalizedString("Insurance_Title", comment: "保险"))
                                Spacer()
                            }
                        }
                    }

                    if isModelAvailable {
                        Button {
                            if let url = URL(string: "https://estamelgg.github.io/EVE_Model_Gallery/#typeid=\(itemDetails.typeId)&tiny") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image("ISIS")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(NSLocalizedString("Item_View_Model", comment: "查看模型"))
                                Spacer()
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 基础属性 Section
            if itemDetails.volume != nil || itemDetails.capacity != nil || itemDetails.mass != nil
                || itemDetails.repackagedVolume != nil
            {
                Section(header: Text(NSLocalizedString("Item_Basic_Info", comment: "")).font(.headline)) {
                    if let volume = itemDetails.volume {
                        HStack {
                            Image("structure")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(NSLocalizedString("Item_Volume", comment: ""))
                            Spacer()
                            Text("\(FormatUtil.format(Double(volume))) m3")
                                .foregroundColor(.secondary)
                                .frame(alignment: .trailing)
                        }
                    }

                    if let repackagedVolume = itemDetails.repackagedVolume {
                        HStack {
                            Image("packages")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(NSLocalizedString("Item_RepackagesVolume", comment: ""))
                            Spacer()
                            Text("\(FormatUtil.format(Double(repackagedVolume))) m3")
                                .foregroundColor(.secondary)
                                .frame(alignment: .trailing)
                        }
                    }

                    if let capacity = itemDetails.capacity {
                        let finalCapacity =
                            getAttributeValue(attributeId: 38, originalValue: Double(capacity))
                                ?? Double(capacity)
                        let capacityColor = getAttributeColor(
                            attributeId: 38, originalValue: Double(capacity)
                        )

                        HStack {
                            Image("cargo_fit")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(NSLocalizedString("Item_Capacity", comment: ""))
                            Spacer()
                            Text("\(FormatUtil.format(finalCapacity)) m3")
                                .foregroundColor(capacityColor)
                                .frame(alignment: .trailing)
                        }
                    }

                    if let mass = itemDetails.mass {
                        let finalMass =
                            getAttributeValue(attributeId: 4, originalValue: Double(mass))
                                ?? Double(mass)
                        let massColor = getAttributeColor(attributeId: 4, originalValue: Double(mass))

                        HStack {
                            Image("hull")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(NSLocalizedString("Item_Mass", comment: ""))
                            Spacer()
                            Text("\(FormatUtil.format(finalMass)) Kg")
                                .foregroundColor(massColor)
                                .frame(alignment: .trailing)
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
    }

    // 加载渲染图
    private func loadRenderImage(for itemID: Int) {
        Task {
            do {
                let image = try await ItemRenderAPI.shared.fetchItemRender(
                    typeId: itemID, size: 512
                )
                await MainActor.run {
                    self.renderImage = image
                }
            } catch {
                Logger.error("加载渲染图失败: \(error.localizedDescription)")
                // 加载失败时保持使用原来的小图显示，不需特殊处理
            }
        }
    }

    // 检查模型是否可用
    private func checkModelAvailability() {
        Task {
            do {
                let available = try await AvailableModelsAPI.shared.isModelAvailable(itemDetails.typeId)
                await MainActor.run {
                    self.isModelAvailable = available
                }
            } catch {
                Logger.debug("检查模型可用性失败: \(error.localizedDescription)")
                await MainActor.run {
                    self.isModelAvailable = false
                }
            }
        }
    }

    // 设置方向变化通知
    private func setupOrientationNotification() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.orientation = UIDevice.current.orientation

            // 只有当布局模式真正发生变化时才更新layoutMode
            let newLayoutMode = DeviceUtils.currentLayoutMode
            if DeviceUtils.shouldUpdateLayout(from: self.layoutMode, to: newLayoutMode) {
                Logger.debug("物品详情布局模式变化: \(self.layoutMode.rawValue) -> \(newLayoutMode.rawValue)")
                self.layoutMode = newLayoutMode
            }
        }
    }

    // 移除方向变化通知
    private func removeOrientationNotification() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
}
