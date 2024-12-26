import Foundation
import CoreData

class CoreDataManager {
    static let shared = CoreDataManager()
    
    private let containerName = "EVENexus"
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: containerName)
        container.loadPersistentStores { description, error in
            if let error = error {
                Logger.error("CoreData 初始化失败: \(error)")
            }
        }
        return container
    }()
    
    private var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    private init() {}
    
    // MARK: - UserDefaults 风格的接口
    
    func set(_ value: Any?, forKey key: String) {
        guard let value = value else {
            removeValue(forKey: key)
            return
        }
        
        do {
            // 将值转换为 Data
            let data: Data
            if let dataValue = value as? Data {
                data = dataValue
            } else {
                data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
            }
            
            // 检查是否存在现有条目
            let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "key == %@", key)
            
            let existingEntries = try context.fetch(fetchRequest)
            
            if let existingEntry = existingEntries.first {
                // 更新现有条目
                existingEntry.data = data
                existingEntry.timestamp = Date()
            } else {
                // 创建新条目
                let newEntry = CacheEntry(context: context)
                newEntry.key = key
                newEntry.data = data
                newEntry.timestamp = Date()
            }
            
            try context.save()
            Logger.debug("CoreData 保存成功 - Key: \(key), 数据大小: \(data.count) bytes")
        } catch {
            Logger.error("CoreData 保存失败 - Key: \(key), 错误: \(error)")
        }
    }
    
    func object(forKey key: String) -> Any? {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "key == %@", key)
        
        do {
            let entries = try context.fetch(fetchRequest)
            guard let entry = entries.first,
                  let data = entry.data else {
                return nil
            }
            
            return try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSData.self], from: data)
        } catch {
            Logger.error("CoreData 读取失败 - Key: \(key), 错误: \(error)")
            return nil
        }
    }
    
    func data(forKey key: String) -> Data? {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "key == %@", key)
        
        do {
            let entries = try context.fetch(fetchRequest)
            return entries.first?.data
        } catch {
            Logger.error("CoreData 读取失败 - Key: \(key), 错误: \(error)")
            return nil
        }
    }
    
    func removeValue(forKey key: String) {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "key == %@", key)
        
        do {
            let entries = try context.fetch(fetchRequest)
            entries.forEach { context.delete($0) }
            try context.save()
            Logger.debug("CoreData 删除成功 - Key: \(key)")
        } catch {
            Logger.error("CoreData 删除失败 - Key: \(key), 错误: \(error)")
        }
    }
    
    func removeAll() {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(fetchRequest)
            entries.forEach { context.delete($0) }
            try context.save()
            Logger.debug("CoreData 清除所有数据成功")
        } catch {
            Logger.error("CoreData 清除所有数据失败: \(error)")
        }
    }
    
    // MARK: - 辅助方法
    
    func getValue<T: Codable>(forKey key: String) -> T? {
        guard let data = data(forKey: key) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.error("CoreData 解码失败 - Key: \(key), 错误: \(error)")
            return nil
        }
    }
    
    func setValue<T: Codable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            set(data, forKey: key)
        } catch {
            Logger.error("CoreData 编码失败 - Key: \(key), 错误: \(error)")
        }
    }
    
    // MARK: - 统计方法
    
    func getCacheStats() -> (count: Int, totalSize: Int) {
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(fetchRequest)
            let totalSize = entries.reduce(0) { $0 + ($1.data?.count ?? 0) }
            return (entries.count, totalSize)
        } catch {
            Logger.error("CoreData 获取统计信息失败: \(error)")
            return (0, 0)
        }
    }
} 