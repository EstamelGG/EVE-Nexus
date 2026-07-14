import SwiftUI

struct ItemBasicInfoView: View {
    let itemDetails: ItemDetails
    @ObservedObject var databaseManager: DatabaseManager
    let modifiedAttributes: [Int: Double]?

    @State private var renderImage: UIImage?
    @State private var orientation = UIDevice.current.orientation
    @State private var marketPath: String = ""
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var isModelAvailable = false
    @State private var itemNameShowsEnglish = false

    private let cornerRadius: CGFloat = 10
    private let standardPadding: CGFloat = 16
    private let rowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

    /// 拥有 3D 渲染图的物品 categoryID 白名单
    private static let renderImageCategories: Set<Int> = [
        2, 3, 6, 11, 18, 22, 23, 40, 41, 46, 65, 87, 91,
    ]

    private var shouldUseCompactLayout: Bool {
        // 引用 orientation 以便设备旋转时触发 body 重新渲染
        _ = orientation
        return DeviceUtils.shouldUseCompactLayout
    }

    private var imageSize: CGFloat {
        DeviceUtils.isIPad ? 256 : 128
    }

    private var itemNameCanToggleEnglish: Bool {
        guard let en = itemDetails.en_name, !en.isEmpty else { return false }
        return en != itemDetails.name
    }

    private var itemTitleDisplayName: String {
        if itemNameCanToggleEnglish, itemNameShowsEnglish, let en = itemDetails.en_name {
            return en
        }
        return itemDetails.name
    }

    private var itemTitleAlternateName: String? {
        guard itemNameCanToggleEnglish, let en = itemDetails.en_name else { return nil }
        return itemNameShowsEnglish ? itemDetails.name : en
    }

    private static let itemNameToggleAnimation = Animation.spring(
        response: 0.38,
        dampingFraction: 0.82
    )

    private var categoryGroupIDText: String {
        "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
    }

    private var hasBasicStats: Bool {
        itemDetails.volume != nil
            || itemDetails.capacity != nil
            || itemDetails.mass != nil
            || itemDetails.repackagedVolume != nil
    }

    var body: some View {
        Group {
            Section {
                Group {
                    if let renderImage {
                        if shouldUseCompactLayout {
                            compactLayoutView(renderImage: renderImage)
                        } else {
                            renderImageLayoutView(renderImage: renderImage)
                        }
                    } else {
                        originalLayoutView()
                    }
                }

                if !itemDetails.description.isEmpty {
                    RichTextView(text: itemDetails.description, databaseManager: databaseManager)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            .onAppear {
                loadRenderImage(for: itemDetails.typeId)
                Logger.debug(
                    "物品 \(itemDetails.name) 的 marketGroupID: \(String(describing: itemDetails.marketGroupID))"
                )
                if let marketGroupID = itemDetails.marketGroupID {
                    Logger.debug("显示市场按钮，marketGroupID: \(marketGroupID)")
                    if shouldUseCompactLayout {
                        fetchMarketPath(for: marketGroupID)
                    }
                }
                checkModelAvailability()
                setupOrientationNotification()
            }
            .onDisappear {
                removeOrientationNotification()
            }
            .alert(
                NSLocalizedString("Misc_Save_Render_Image", comment: ""),
                isPresented: $showSaveSuccess
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
            .onChange(of: shouldUseCompactLayout) { _, newValue in
                if newValue && marketPath.isEmpty && itemDetails.marketGroupID != nil {
                    fetchMarketPath(for: itemDetails.marketGroupID)
                }
            }

            if itemDetails.marketGroupID != nil || isModelAvailable {
                Section {
                    if itemDetails.marketGroupID != nil {
                        NavigationLink {
                            MarketItemDetailView(
                                databaseManager: databaseManager,
                                itemID: itemDetails.typeId
                            )
                        } label: {
                            iconTitleRow(
                                icon: "isk",
                                title: NSLocalizedString("Main_Market", comment: "")
                            )
                        }

                        NavigationLink {
                            MarketQuickbarDestinationPickerView(
                                databaseManager: databaseManager,
                                typeID: itemDetails.typeId
                            )
                        } label: {
                            HStack(alignment: .center) {
                                Image("searchmarket")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(
                                    NSLocalizedString(
                                        "Main_Market_Add_To_Watchlist_Button", comment: ""
                                    )
                                )
                                .foregroundColor(.primary)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }

                    if itemDetails.categoryID == 6 {
                        NavigationLink {
                            ShipInsuranceView(
                                typeId: itemDetails.typeId,
                                typeName: itemDetails.name
                            )
                        } label: {
                            iconTitleRow(
                                icon: "insurance",
                                title: NSLocalizedString("Insurance_Title", comment: "保险")
                            )
                        }
                    }

                    if isModelAvailable {
                        Button {
                            if let url = URL(
                                string:
                                "https://estamelgg.github.io/EVE_Model_Gallery/#typeid=\(itemDetails.typeId)&tiny"
                            ) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            iconTitleRow(
                                icon: "ISIS",
                                title: NSLocalizedString("Item_View_Model", comment: "查看模型")
                            )
                        }
                    }
                }
                .listRowInsets(rowInsets)
            }

            if hasBasicStats {
                Section(
                    header: Text(NSLocalizedString("Item_Basic_Info", comment: "")).font(.headline)
                ) {
                    if let volume = itemDetails.volume {
                        basicStatRow(
                            icon: "structure",
                            title: NSLocalizedString("Item_Volume", comment: ""),
                            value: "\(FormatUtil.format(Double(volume))) m3"
                        )
                    }
                    if let repackagedVolume = itemDetails.repackagedVolume {
                        basicStatRow(
                            icon: "packages",
                            title: NSLocalizedString("Item_RepackagesVolume", comment: ""),
                            value: "\(FormatUtil.format(Double(repackagedVolume))) m3"
                        )
                    }
                    if let capacity = itemDetails.capacity {
                        let original = Double(capacity)
                        let final =
                            getAttributeValue(attributeId: 38, originalValue: original) ?? original
                        basicStatRow(
                            icon: "cargo_fit",
                            title: NSLocalizedString("Item_Capacity", comment: ""),
                            value: "\(FormatUtil.format(final)) m3",
                            valueColor: getAttributeColor(attributeId: 38, originalValue: original)
                        )
                    }
                    if let mass = itemDetails.mass {
                        let original = Double(mass)
                        let final =
                            getAttributeValue(attributeId: 4, originalValue: original) ?? original
                        basicStatRow(
                            icon: "hull",
                            title: NSLocalizedString("Item_Mass", comment: ""),
                            value: "\(FormatUtil.format(final)) Kg",
                            valueColor: getAttributeColor(attributeId: 4, originalValue: original)
                        )
                    }
                }
                .listRowInsets(rowInsets)
            }
        }
        .onChange(of: itemDetails.typeId) { _, _ in
            itemNameShowsEnglish = false
        }
    }

    // MARK: - Layout

    private func compactLayoutView(renderImage: UIImage) -> some View {
        HStack(alignment: .center) {
            Image(uiImage: renderImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: imageSize, height: imageSize)
                .cornerRadius(cornerRadius)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 8) {
                itemTitleLabel(lineLimit: 2)
                    .contextMenu { itemNameContextMenu(includeSaveImage: true) }

                Text(
                    "\(NSLocalizedString("Main_Database_Category", comment: "")): \(categoryGroupIDText)"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

                if !marketPath.isEmpty {
                    Text(
                        "\(NSLocalizedString("Main_Database_Market_Category", comment: "")): \(marketPath)"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func renderImageLayoutView(renderImage: UIImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: renderImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .cornerRadius(cornerRadius)
                .padding(.horizontal, standardPadding)
                .padding(.vertical, standardPadding)

            VStack(alignment: .leading, spacing: 4) {
                itemTitleLabel(lineLimit: 2)
                Text(categoryGroupIDText)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu { itemNameContextMenu(includeSaveImage: true) }
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
        .listRowInsets(EdgeInsets())
    }

    private func originalLayoutView() -> some View {
        HStack(alignment: .center) {
            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                itemTitleLabel(lineLimit: nil)
                    .contextMenu { itemNameContextMenu(includeSaveImage: false) }
                Text(categoryGroupIDText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemTitleLabel(lineLimit: Int?) -> some View {
        HStack(spacing: 0) {
            Text(itemTitleDisplayName)
                .font(.title)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .contentTransition(.interpolate)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleItemNameLanguageAnimated)
    }

    @ViewBuilder
    private func itemNameContextMenu(includeSaveImage: Bool) -> some View {
        Button {
            UIPasteboard.general.string = itemTitleDisplayName
        } label: {
            Label(NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc")
        }
        if let alt = itemTitleAlternateName {
            Button {
                UIPasteboard.general.string = alt
            } label: {
                Label(NSLocalizedString("Misc_Copy_Trans", comment: ""), systemImage: "translate")
            }
        }
        if includeSaveImage {
            Button {
                saveRenderImageToPhotos()
            } label: {
                Label(
                    NSLocalizedString("Misc_Save_Render_Image", comment: ""),
                    systemImage: "photo"
                )
            }
        }
    }

    private func iconTitleRow(icon: String, title: String) -> some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(title)
            Spacer()
        }
    }

    private func basicStatRow(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = .secondary
    ) -> some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .frame(alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func toggleItemNameLanguageAnimated() {
        guard itemNameCanToggleEnglish else { return }
        withAnimation(Self.itemNameToggleAnimation) {
            itemNameShowsEnglish.toggle()
        }
    }

    private func getAttributeValue(attributeId: Int, originalValue: Double?) -> Double? {
        modifiedAttributes?[attributeId] ?? originalValue
    }

    private func getAttributeColor(attributeId: Int, originalValue: Double?) -> Color {
        guard let originalValue,
              let modifiedValue = modifiedAttributes?[attributeId]
        else { return .secondary }

        if abs(modifiedValue - originalValue) < 0.0001 {
            return .secondary
        }

        // mass(4): 越小越好；capacity(38): 越大越好
        let highIsGood = attributeId == 38
        if highIsGood {
            return modifiedValue > originalValue ? .green : .red
        }
        return modifiedValue < originalValue ? .green : .red
    }

    private func saveRenderImageToPhotos() {
        guard let renderImage else { return }
        ImageSaver.saveImage(renderImage) { success in
            if success {
                showSaveSuccess = true
            } else {
                showSaveError = true
            }
        }
    }

    private func fetchMarketPath(for marketGroupID: Int?) {
        guard let marketGroupID else {
            marketPath = ""
            return
        }

        Task {
            do {
                let path = try await getMarketGroupPath(groupID: marketGroupID)
                await MainActor.run {
                    marketPath = path.joined(separator: " / ")
                }
            } catch {
                Logger.error("获取市场目录路径失败: \(error.localizedDescription)")
                await MainActor.run {
                    marketPath = ""
                }
            }
        }
    }

    private func getMarketGroupPath(groupID: Int) async throws -> [String] {
        var path: [String] = []
        var currentGroupID = groupID
        var iterations = 0
        let maxIterations = 100

        while currentGroupID != 0, iterations < maxIterations {
            iterations += 1
            guard let group = SDEMemoryStore.marketGroup(for: currentGroupID) else { return path }

            path.insert(group.name, at: 0)

            if let parentGroupID = group.parentGroupID, parentGroupID > 0 {
                if parentGroupID == currentGroupID || path.count >= maxIterations {
                    Logger.warning("检测到可能的循环引用或过深的市场目录路径，中止查询")
                    return path
                }
                currentGroupID = parentGroupID
            } else {
                return path
            }
        }

        if iterations >= maxIterations {
            Logger.warning("市场目录路径查询达到最大迭代次数 \(maxIterations)，可能存在循环引用")
        }
        return path
    }

    private func loadRenderImage(for itemID: Int) {
        guard let categoryID = itemDetails.categoryID,
              Self.renderImageCategories.contains(categoryID) else { return }
        Task {
            do {
                let image = try await ItemRenderAPI.shared.fetchItemRender(
                    typeId: itemID, size: 512
                )
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        renderImage = image
                    }
                }
            } catch {
                Logger.error("加载渲染图失败: \(error.localizedDescription)")
            }
        }
    }

    private func checkModelAvailability() {
        Task {
            do {
                let available = try await AvailableModelsAPI.shared.isModelAvailable(
                    itemDetails.typeId
                )
                await MainActor.run {
                    isModelAvailable = available
                }
            } catch {
                Logger.debug("检查模型可用性失败: \(error.localizedDescription)")
                await MainActor.run {
                    isModelAvailable = false
                }
            }
        }
    }

    private func setupOrientationNotification() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            orientation = UIDevice.current.orientation
        }
    }

    private func removeOrientationNotification() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
}
