import Foundation

actor UniverseNameCache {
    static let shared = UniverseNameCache()
    
    private var cache: [Int: String] = [:]
    
    private init() {}
    
    func getName(for id: Int) -> String? {
        return cache[id]
    }
    
    func setName(_ name: String, for id: Int) {
        cache[id] = name
    }
    
    func getNames(for ids: Set<Int>) async throws -> [Int: String] {
        // 过滤出未缓存的ID
        let uncachedIds = ids.filter { cache[$0] == nil }
        
        // 如果所有ID都已缓存，直接返回缓存的结果
        if uncachedIds.isEmpty {
            return ids.reduce(into: [:]) { result, id in
                if let name = cache[id] {
                    result[id] = name
                }
            }
        }
        
        // 请求未缓存的ID
        let url = URL(string: "https://esi.evetech.net/latest/universe/names/?datasource=tranquility")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        let jsonData = try JSONEncoder().encode(Array(uncachedIds))
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let names = try JSONDecoder().decode([UniverseNameResponse].self, from: data)
        
        // 更新缓存
        for name in names {
            cache[name.id] = name.name
        }
        
        // 返回所有请求的ID的名称（包括之前已缓存的）
        return ids.reduce(into: [:]) { result, id in
            if let name = cache[id] {
                result[id] = name
            }
        }
    }
} 