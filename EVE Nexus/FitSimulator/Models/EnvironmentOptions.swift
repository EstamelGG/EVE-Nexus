import Foundation

struct EnvironmentOptions: Codable {
    let wormhole: [Int]
    let abyssal: [Int]
    let other: [Int]

    enum Category: String, CaseIterable, Identifiable {
        case wormhole
        case abyssal
        case other

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .wormhole:
                return "Environment_Category_Wormhole"
            case .abyssal:
                return "Environment_Category_Abyssal"
            case .other:
                return "Environment_Category_Other"
            }
        }

        var iconAssetName: String {
            switch self {
            case .wormhole:
                return "wormhole"
            case .abyssal:
                return "plasma"
            case .other:
                return "location"
            }
        }

        func typeIds(from options: EnvironmentOptions) -> [Int] {
            switch self {
            case .wormhole:
                return options.wormhole
            case .abyssal:
                return options.abyssal
            case .other:
                return options.other
            }
        }
    }

    static let shared: EnvironmentOptions = {
        guard let url = Bundle.main.url(forResource: "environment_options", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let options = try? JSONDecoder().decode(EnvironmentOptions.self, from: data)
        else {
            Logger.error("无法加载 environment_options.json")
            return EnvironmentOptions(wormhole: [], abyssal: [], other: [])
        }
        return options
    }()
}
