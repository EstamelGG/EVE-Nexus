import Foundation

struct StationInfoResponse: Codable {
    let station_id: Int
    let name: String
    let owner: Int
    let position: Position
    let race_id: Int?
    let type_id: Int
    let system_id: Int
    let reprocessing_efficiency: Double?
    let reprocessing_stations_take: Double?
    let max_dockable_ship_volume: Double?
    let office_rental_cost: Double?
    let services: [String]?

    struct Position: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
}

@MainActor
class StationInfoAPI {
    static let shared = StationInfoAPI()
    private var cache: [Int: StationInfoResponse] = [:]

    private init() {}

    func fetchStationInfo(stationId: Int) async throws -> StationInfoResponse {
        // 检查缓存
        if let cachedInfo = cache[stationId] {
            Logger.debug("使用缓存的空间站信息 - 空间站ID: \(stationId)")
            return cachedInfo
        }

        // 构建URL
        let urlString =
            "https://esi.evetech.net/latest/universe/stations/\(stationId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("无效的空间站URL: \(urlString)")
            throw NetworkError.invalidURL
        }

        do {
            Logger.debug("开始获取空间站信息 - 空间站ID: \(stationId)")
            let data = try await NetworkManager.shared.fetchData(from: url)
            let stationInfo = try JSONDecoder().decode(StationInfoResponse.self, from: data)

            // 保存到缓存
            cache[stationId] = stationInfo

            Logger.debug("成功获取空间站信息 - 空间站ID: \(stationId), 名称: \(stationInfo.name)")
            return stationInfo

        } catch {
            Logger.error("获取空间站信息失败 - 空间站ID: \(stationId), 错误: \(error)")
            throw error
        }
    }

    func clearCache() {
        cache.removeAll()
        Logger.debug("已清除空间站信息缓存")
    }
}
