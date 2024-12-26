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
            removeObject(forKey: key)
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
    
    func removeObject(forKey key: String) {
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
    
    // MARK: - 便捷方法
    
    func integer(forKey key: String) -> Int {
        return object(forKey: key) as? Int ?? 0
    }
    
    func float(forKey key: String) -> Float {
        return object(forKey: key) as? Float ?? 0.0
    }
    
    func double(forKey key: String) -> Double {
        return object(forKey: key) as? Double ?? 0.0
    }
    
    func bool(forKey key: String) -> Bool {
        return object(forKey: key) as? Bool ?? false
    }
    
    func string(forKey key: String) -> String? {
        return object(forKey: key) as? String
    }
    
    func array(forKey key: String) -> [Any]? {
        return object(forKey: key) as? [Any]
    }
    
    func dictionary(forKey key: String) -> [String: Any]? {
        return object(forKey: key) as? [String: Any]
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
    
    // MARK: - 同步方法
    
    func synchronize() -> Bool {
        do {
            if context.hasChanges {
                try context.save()
            }
            return true
        } catch {
            Logger.error("CoreData 同步失败: \(error)")
            return false
        }
    }
} 