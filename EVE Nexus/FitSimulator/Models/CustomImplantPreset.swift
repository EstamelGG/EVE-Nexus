import Foundation

// 自定义植入体预设数据模型
struct CustomImplantPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    let implantTypeIds: [Int] // 包含植入体和增效剂的 typeId 列表

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date(), implantTypeIds: [Int]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.implantTypeIds = implantTypeIds
    }
}

// 自定义预设管理器
class CustomImplantPresetManager {
    static let shared = CustomImplantPresetManager()

    private let fileName = "custom_implant_presets.json"
    private var cacheDirectory: URL {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsPath.appendingPathComponent("ImplantPresets", isDirectory: true)

        // 如果目录不存在，创建它
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        return cacheDir
    }

    private var filePath: URL {
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private init() {}

    // 加载所有预设
    func loadPresets() -> [CustomImplantPreset] {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("自定义预设文件不存在，返回空列表")
            return []
        }

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let presets = try decoder.decode([CustomImplantPreset].self, from: data)
            Logger.info("成功加载 \(presets.count) 个自定义预设")
            return presets
        } catch {
            Logger.error("加载自定义预设失败: \(error)")
            return []
        }
    }

    // 保存所有预设
    func savePresets(_ presets: [CustomImplantPreset]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presets)
            try data.write(to: filePath)
            Logger.info("成功保存 \(presets.count) 个自定义预设到: \(filePath.path)")
        } catch {
            Logger.error("保存自定义预设失败: \(error)")
        }
    }

    // 添加预设
    func addPreset(_ preset: CustomImplantPreset) {
        var presets = loadPresets()
        presets.append(preset)
        savePresets(presets)
    }

    // 删除预设
    func deletePreset(_ presetId: UUID) {
        var presets = loadPresets()
        presets.removeAll { $0.id == presetId }
        savePresets(presets)
        Logger.info("删除预设: \(presetId)")
    }
}
