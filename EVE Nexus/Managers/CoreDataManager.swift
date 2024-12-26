import CoreData
import Foundation

class CoreDataManager {
    static let shared = CoreDataManager()
    
    private init() {}
    
    // MARK: - Core Data stack
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "EVENexus")
        container.loadPersistentStores { description, error in
            if let error = error {
                Logger.error("Core Data 加载失败: \(error.localizedDescription)")
            }
        }
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - CRUD Operations
    
    /// 保存数据到缓存
    /// - Parameters:
    ///   - value: 要保存的值
    ///   - key: 缓存键
    func setValue<T: Codable>(_ value: T, forKey key: String) {
        do {
            // 将值编码为数据
            let data = try JSONEncoder().encode(value)
            
            // 检查是否存在现有条目
            let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "key == %@", key)
            
            let existingEntries = try context.fetch(fetchRequest)
            let entry: CacheEntry
            
            if let existingEntry = existingEntries.first {
                // 更新现有条目
                entry = existingEntry
            } else {
                // 创建新条目
                entry = CacheEntry(context: context)
                entry.key = key
            }
            
            entry.data = data
            entry.timestamp = Date()
            
            // 记录数据大小
            Logger.debug("正在写入 Core Data，键: \(key), 数据大小: \(data.count) bytes")
            
            try context.save()
            
        } catch {
            Logger.error("保存到 Core Data 失败 - 键: \(key), 错误: \(error.localizedDescription)")
        }
    }
    
    /// 从缓存读取数据
    /// - Parameter key: 缓存键
    /// - Returns: 解码后的值，如果不存在或解码失败则返回 nil
    func getValue<T: Codable>(forKey key: String) -> T? {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "key == %@", key)
        
        do {
            let entries = try context.fetch(fetchRequest)
            guard let entry = entries.first, let data = entry.data else {
                return nil
            }
            
            // 记录读取操作
            Logger.debug("正在从 Core Data 读取，键: \(key), 数据大小: \(data.count) bytes")
            
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.error("从 Core Data 读取失败 - 键: \(key), 错误: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 删除缓存
    /// - Parameter key: 缓存键
    func removeValue(forKey key: String) {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "key == %@", key)
        
        do {
            let entries = try context.fetch(fetchRequest)
            entries.forEach { context.delete($0) }
            try context.save()
            Logger.debug("已从 Core Data 删除键: \(key)")
        } catch {
            Logger.error("从 Core Data 删除失败 - 键: \(key), 错误: \(error.localizedDescription)")
        }
    }
    
    /// 清理所有缓存
    func clearAllCache() {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(fetchRequest)
            entries.forEach { context.delete($0) }
            try context.save()
            Logger.info("已清理所有 Core Data 缓存")
        } catch {
            Logger.error("清理 Core Data 缓存失败: \(error.localizedDescription)")
        }
    }
    
    /// 获取缓存统计信息
    func getCacheStats() {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(fetchRequest)
            var totalSize = 0
            
            for entry in entries {
                if let data = entry.data {
                    totalSize += data.count
                    Logger.debug("缓存项 - 键: \(entry.key ?? "unknown"), 大小: \(data.count) bytes, 时间: \(entry.timestamp ?? Date())")
                }
            }
            
            let totalSizeInMB = Double(totalSize) / (1024 * 1024)
            Logger.info("Core Data 缓存统计 - 总条目: \(entries.count), 总大小: \(String(format: "%.2f", totalSizeInMB))MB")
            
        } catch {
            Logger.error("获取缓存统计失败: \(error.localizedDescription)")
        }
    }
} 