import Foundation
import SwiftUI
import SQLite3

class CharacterDatabaseManager: ObservableObject, @unchecked Sendable {
    static let shared = CharacterDatabaseManager()
    @Published var databaseUpdated = false
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.eve.nexus.character.database")
    
    private init() {
        Logger.info("开始初始化角色数据库...")
        // 获取数据库文件路径
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent("character_data.db").path
        Logger.info("角色数据库路径: \(dbPath)")
        
        // 检查数据库文件是否存在
        let dbExists = fileManager.fileExists(atPath: dbPath)
        Logger.info("角色数据库文件\(dbExists ? "已存在" : "不存在")")
        
        // 创建数据库目录（如果不存在）
        try? fileManager.createDirectory(at: documentsPath, withIntermediateDirectories: true)
        
        // 打开/创建数据库
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            // if !dbExists {
            //     Logger.info("创建新的角色数据库: \(dbPath)")
            //     // 创建数据库表
            //     setupBaseTables()
            // } else {
            //     Logger.info("打开已有的角色数据库: \(dbPath)")
            // }
            setupBaseTables()
        } else {
            if let db = db {
                let errmsg = String(cString: sqlite3_errmsg(db))
                Logger.error("角色数据库打开失败: \(errmsg)")
                sqlite3_close(db)
            } else {
                Logger.error("角色数据库打开失败: 未知错误")
            }
        }
        Logger.info("角色数据库初始化完成")
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Management
    
    /// 加载数据库
    func loadDatabase() {
        Logger.info("开始加载角色数据库...")
        if let db = db {
            // 验证数据库连接
            var statement: OpaquePointer?
            let query = "SELECT name FROM sqlite_master WHERE type='table' LIMIT 1"
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                Logger.info("角色数据库连接验证成功")
                sqlite3_finalize(statement)
                DispatchQueue.main.async {
                    self.databaseUpdated.toggle()
                }
            } else {
                let errmsg = String(cString: sqlite3_errmsg(db))
                Logger.error("角色数据库验证失败: \(errmsg)")
            }
        } else {
            Logger.error("角色数据库未打开")
        }
    }
    
    /// 关闭数据库
    func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    /// 清除查询缓存
    func clearCache() {
        // 不再需要缓存管理
    }
    
    /// 获取查询日志
    func getQueryLogs() -> [(query: String, parameters: [Any], timestamp: Date)] {
        // 如果需要查询日志，可以自己实现
        return []
    }
    
    /// 重置数据库
    func resetDatabase() {
        Logger.info("开始重置角色数据库...")
        
        // 关闭当前数据库连接
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
        
        // 获取数据库文件路径
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent("character_data.db").path
        
        // 删除现有数据库文件
        do {
            if fileManager.fileExists(atPath: dbPath) {
                try fileManager.removeItem(atPath: dbPath)
                Logger.info("已删除现有数据库文件")
            }
        } catch {
            Logger.error("删除数据库文件失败: \(error)")
        }
        
        // 重新打开/创建数据库
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            Logger.info("创建新的角色数据库: \(dbPath)")
            // 重新创建数据库表
            setupBaseTables()
            
            // 通知UI更新
            DispatchQueue.main.async {
                self.databaseUpdated.toggle()
            }
            Logger.info("数据库重置完成")
        } else {
            if let db = db {
                let errmsg = String(cString: sqlite3_errmsg(db))
                Logger.error("重置数据库失败: \(errmsg)")
                sqlite3_close(db)
            } else {
                Logger.error("重置数据库失败: 未知错误")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBaseTables() {
        let createTablesSQL = """
            -- 角色当前状态表
            CREATE TABLE IF NOT EXISTS character_current_state (
                character_id INTEGER NOT NULL PRIMARY KEY,
                solar_system_id INTEGER,
                station_id INTEGER,
                structure_id INTEGER,
                location_status TEXT,
                ship_item_id INTEGER,
                ship_type_id INTEGER,
                ship_name TEXT,
                online_status INTEGER DEFAULT 0,
                last_update INTEGER
            );
            
            -- 邮箱表
            CREATE TABLE IF NOT EXISTS mailbox (
                mail_id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                from_id INTEGER NOT NULL,
                is_read BOOLEAN NOT NULL DEFAULT 0,
                subject TEXT NOT NULL,
                recipients TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (mail_id, character_id)
            );

            -- 邮件内容表
            CREATE TABLE IF NOT EXISTS mail_content (
                mail_id INTEGER NOT NULL PRIMARY KEY,
                body TEXT NOT NULL,
                from_id INTEGER NOT NULL,
                subject TEXT NOT NULL,
                recipients TEXT NOT NULL,
                labels TEXT NOT NULL,
                timestamp TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_mail_content_from_id ON mail_content(from_id);

            -- 邮件标签关系表
            CREATE TABLE IF NOT EXISTS mail_labels (
                mail_id INTEGER NOT NULL,
                label_id INTEGER NOT NULL,
                PRIMARY KEY (mail_id, label_id),
                FOREIGN KEY (mail_id) REFERENCES mailbox(mail_id)
            );

            -- 创建邮箱相关索引
            CREATE INDEX IF NOT EXISTS idx_mailbox_character_id ON mailbox(character_id);
            CREATE INDEX IF NOT EXISTS idx_mailbox_timestamp ON mailbox(timestamp);
            CREATE INDEX IF NOT EXISTS idx_mailbox_from_id ON mailbox(from_id);
            CREATE INDEX IF NOT EXISTS idx_mail_labels_label_id ON mail_labels(label_id);
            
            -- 通用名称缓存表
            CREATE TABLE IF NOT EXISTS universe_names (
                id INTEGER NOT NULL PRIMARY KEY,
                category TEXT NOT NULL,
                name TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_universe_names_category ON universe_names(category);
        
            -- 邮件订阅列表
            CREATE TABLE IF NOT EXISTS mail_lists (
                list_id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (list_id, character_id)
            );
            CREATE INDEX IF NOT EXISTS idx_mail_lists_character_id ON mail_lists(character_id);
        
            -- 钱包日志表
            CREATE TABLE IF NOT EXISTS wallet_journal (
                id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                amount REAL,
                balance REAL,
                context_id INTEGER,
                context_id_type TEXT,
                date TEXT,
                description TEXT,
                first_party_id INTEGER,
                reason TEXT,
                ref_type TEXT,
                second_party_id INTEGER,
                tax REAL,
                tax_receiver_id INTEGER,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (character_id, id)
            );

            -- 军团钱包日志表
            CREATE TABLE IF NOT EXISTS corp_wallet_journal (
                id INTEGER NOT NULL,
                corporation_id INTEGER NOT NULL,
                division INTEGER NOT NULL,
                amount REAL,
                balance REAL,
                context_id INTEGER,
                context_id_type TEXT,
                date TEXT,
                description TEXT,
                first_party_id INTEGER,
                reason TEXT,
                ref_type TEXT,
                second_party_id INTEGER,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (corporation_id, division, id)
            );
            CREATE INDEX IF NOT EXISTS idx_corp_wallet_journal_date ON corp_wallet_journal(date);
            CREATE INDEX IF NOT EXISTS idx_corp_wallet_journal_division ON corp_wallet_journal(corporation_id, division);

            -- 钱包交易记录表
            CREATE TABLE IF NOT EXISTS wallet_transactions (
                transaction_id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                client_id INTEGER,
                date TEXT,
                is_buy BOOLEAN,
                is_personal BOOLEAN,
                journal_ref_id INTEGER,
                location_id INTEGER,
                quantity INTEGER,
                type_id INTEGER,
                unit_price REAL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (character_id, transaction_id)
            );

            -- 军团钱包交易记录表
            CREATE TABLE IF NOT EXISTS corp_wallet_transactions (
                transaction_id INTEGER NOT NULL,
                corporation_id INTEGER NOT NULL,
                division INTEGER NOT NULL,
                client_id INTEGER,
                date TEXT,
                is_buy BOOLEAN,
                is_personal BOOLEAN,
                journal_ref_id INTEGER,
                location_id INTEGER,
                quantity INTEGER,
                type_id INTEGER,
                unit_price REAL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (corporation_id, division, transaction_id)
            );

            -- 合同表
            CREATE TABLE IF NOT EXISTS contracts (
                contract_id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                status TEXT,
                acceptor_id INTEGER,
                assignee_id INTEGER,
                availability TEXT,
                buyout REAL,
                collateral REAL DEFAULT NULL,
                date_accepted TEXT,
                date_completed TEXT,
                date_expired TEXT,
                date_issued TEXT,
                days_to_complete INTEGER,
                end_location_id INTEGER,
                for_corporation BOOLEAN,
                issuer_corporation_id INTEGER,
                issuer_id INTEGER,
                price REAL,
                reward REAL,
                start_location_id INTEGER,
                title TEXT,
                type TEXT,
                volume REAL,
                items_fetched BOOLEAN DEFAULT 0,
                PRIMARY KEY (contract_id, character_id)
            );

            -- 军团合同表
            CREATE TABLE IF NOT EXISTS corporation_contracts (
                contract_id INTEGER NOT NULL,
                corporation_id INTEGER NOT NULL,
                status TEXT,
                acceptor_id INTEGER,
                assignee_id INTEGER,
                availability TEXT,
                buyout REAL,
                collateral REAL DEFAULT NULL,
                date_accepted TEXT,
                date_completed TEXT,
                date_expired TEXT,
                date_issued TEXT,
                days_to_complete INTEGER,
                end_location_id INTEGER,
                for_corporation BOOLEAN,
                issuer_corporation_id INTEGER,
                issuer_id INTEGER,
                price REAL,
                reward REAL,
                start_location_id INTEGER,
                title TEXT,
                type TEXT,
                volume REAL,
                items_fetched BOOLEAN DEFAULT 0,
                PRIMARY KEY (contract_id, corporation_id)
            );

            -- 合同物品表
            CREATE TABLE IF NOT EXISTS contract_items (
                record_id INTEGER NOT NULL,
                contract_id INTEGER NOT NULL,
                is_included BOOLEAN,
                is_singleton BOOLEAN,
                quantity INTEGER,
                type_id INTEGER,
                raw_quantity INTEGER,
                PRIMARY KEY (contract_id, record_id)
            );

            -- 创建索引以提高查询性能
            CREATE INDEX IF NOT EXISTS idx_contracts_date ON contracts(date_issued);
            CREATE INDEX IF NOT EXISTS idx_corporation_contracts_date ON corporation_contracts(date_issued);
            CREATE INDEX IF NOT EXISTS idx_corporation_contracts_corp ON corporation_contracts(corporation_id);

            -- 工业制造表
            CREATE TABLE IF NOT EXISTS industry_jobs (
                character_id INTEGER NOT NULL,
                job_id INTEGER NOT NULL,
                activity_id INTEGER NOT NULL,
                blueprint_id INTEGER NOT NULL,
                blueprint_location_id INTEGER NOT NULL,
                blueprint_type_id INTEGER NOT NULL,
                completed_character_id INTEGER,
                completed_date TEXT,
                cost REAL NOT NULL,
                duration INTEGER NOT NULL,
                end_date TEXT NOT NULL,
                facility_id INTEGER NOT NULL,
                installer_id INTEGER NOT NULL,
                licensed_runs INTEGER,
                output_location_id INTEGER NOT NULL,
                pause_date TEXT,
                probability REAL,
                product_type_id INTEGER,
                runs INTEGER NOT NULL,
                start_date TEXT NOT NULL,
                station_id INTEGER NOT NULL,
                status TEXT NOT NULL,
                successful_runs INTEGER,
                last_updated TEXT NOT NULL,
                PRIMARY KEY (character_id, job_id)
            );

            -- 挖矿记录表
            CREATE TABLE IF NOT EXISTS mining_ledger (
                character_id INTEGER NOT NULL,
                date TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                solar_system_id INTEGER NOT NULL,
                type_id INTEGER NOT NULL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (character_id, date, type_id, solar_system_id)
            );

            -- 技能队列缓存表
            CREATE TABLE IF NOT EXISTS character_skill_queue (
                character_id INTEGER NOT NULL PRIMARY KEY,
                queue_data TEXT,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );

            -- 技能数据缓存表
            CREATE TABLE IF NOT EXISTS character_skills (
                character_id INTEGER NOT NULL PRIMARY KEY,
                skills_data TEXT,
                unallocated_sp INTEGER NOT NULL DEFAULT 0,
                total_sp INTEGER NOT NULL DEFAULT 0,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );

            -- 角色信息缓存表
            CREATE TABLE IF NOT EXISTS character_info (
                character_id INTEGER NOT NULL PRIMARY KEY,
                alliance_id INTEGER,
                birthday TEXT NOT NULL,
                bloodline_id INTEGER NOT NULL,
                corporation_id INTEGER NOT NULL,
                faction_id INTEGER,
                gender TEXT NOT NULL,
                name TEXT NOT NULL,
                race_id INTEGER NOT NULL,
                security_status REAL,
                title TEXT,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_character_info_last_updated ON character_info(last_updated);

            -- 克隆体状态表
            CREATE TABLE IF NOT EXISTS clones (
                character_id INTEGER NOT NULL PRIMARY KEY,
                clones_data TEXT NOT NULL,
                home_location_id INTEGER NOT NULL,
                last_clone_jump_date TEXT,
                last_station_change_date TEXT,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_clones_last_updated ON clones(last_updated);

            -- 植入体状态表
            CREATE TABLE IF NOT EXISTS implants (
                character_id INTEGER NOT NULL PRIMARY KEY,
                implants_data TEXT NOT NULL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_implants_last_updated ON implants(last_updated);

            -- 角色属性点表
            CREATE TABLE IF NOT EXISTS character_attributes (
                character_id INTEGER NOT NULL PRIMARY KEY,
                charisma INTEGER NOT NULL,
                intelligence INTEGER NOT NULL,
                memory INTEGER NOT NULL,
                perception INTEGER NOT NULL,
                willpower INTEGER NOT NULL,
                bonus_remaps INTEGER,
                accrued_remap_cooldown_date TEXT,
                last_remap_date TEXT,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_character_attributes_last_updated ON character_attributes(last_updated);

            -- 市场价格表
            CREATE TABLE IF NOT EXISTS market_prices (
                type_id INTEGER NOT NULL PRIMARY KEY,
                adjusted_price REAL,
                average_price REAL
            );

            -- 忠诚点数据表
            CREATE TABLE IF NOT EXISTS loyalty_points (
                character_id INTEGER NOT NULL PRIMARY KEY,
                points_data TEXT NOT NULL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_loyalty_points_last_updated ON loyalty_points(last_updated);

            -- LP商店数据表
            CREATE TABLE IF NOT EXISTS LPStore (
                corporation_id INTEGER NOT NULL PRIMARY KEY,
                offers_data TEXT NOT NULL,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_lpstore_last_updated ON LPStore(last_updated);
            
            -- 创建索引以提高查询性能
            CREATE INDEX IF NOT EXISTS idx_wallet_journal_character_date ON wallet_journal(character_id, date);
            CREATE INDEX IF NOT EXISTS idx_wallet_transactions_character_date ON wallet_transactions(character_id, date);
            CREATE INDEX IF NOT EXISTS idx_industry_jobs_character_date ON industry_jobs(character_id, start_date);
            CREATE INDEX IF NOT EXISTS idx_mining_ledger_character_date ON mining_ledger(character_id, date);
            CREATE INDEX IF NOT EXISTS idx_skill_queue_last_updated ON character_skill_queue(last_updated);
            CREATE INDEX IF NOT EXISTS idx_character_skills_last_updated ON character_skills(last_updated);
            CREATE INDEX IF NOT EXISTS idx_character_current_state_update ON character_current_state(last_update);

            -- 建筑物缓存表
            CREATE TABLE IF NOT EXISTS structure_cache (
                structure_id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                owner_id INTEGER NOT NULL,
                solar_system_id INTEGER NOT NULL,
                type_id INTEGER NOT NULL,
                timestamp INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_structure_cache_timestamp ON structure_cache(timestamp);
        """
        
        // 分割SQL语句并逐个执行
        let statements = createTablesSQL.components(separatedBy: ";")
        for statement in statements {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if case .error(let error) = executeQuery(trimmed) {
                    Logger.error("创建表失败: \(error)\nSQL: \(trimmed)")
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// 检查数据库是否已初始化
    func isDatabaseInitialized() -> Bool {
        return true
    }
    
    // MARK: - Character Methods
    
    /// 保存或更新角色信息
    func saveCharacter(character: CharacterAuth) {
        // 暂时不实现
    }
    
    /// 获取所有角色信息
    func getAllCharacters() -> [EVECharacterInfo] {
        // 暂时返回空数组
        return []
    }
    
    /// 获取指定角色信息
    func getCharacter(id: Int) -> CharacterAuth? {
        // 暂时返回nil
        return nil
    }
    
    /// 删除角色信息
    func deleteCharacter(id: Int) {
        // 暂时不实现
    }
    
    /// 更新角色的钱包余额
    func updateWalletBalance(characterId: Int, balance: Double) {
        // 暂时不实现
    }
    
    /// 更新角色的技能点信息
    func updateSkillPoints(characterId: Int, totalSP: Int, queueLength: Int) {
        // 暂时不实现
    }
    
    /// 更新角色的位置信息
    func updateLocation(characterId: Int, locationId: Int) {
        // 暂时不实现
    }
    
    /// 更新角色显示顺序
    func updateCharacterOrder(characterIds: [Int]) {
        // 暂时不实现
    }
    
    /// 执行查询
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true) -> SQLiteResult {
        Logger.debug("\(query)?#\(parameters)")
        var result: SQLiteResult = .error("未知错误")
        
        dbQueue.sync {
            guard let db = db else {
                result = .error("数据库未打开")
                return
            }
            
            var statement: OpaquePointer?
            var results: [[String: Any]] = []
            
            // 准备语句
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                Logger.error("准备语句失败: \(errmsg)")
                result = .error("准备语句失败: \(errmsg)")
                return
            }
            
            // 绑定参数
            for (index, parameter) in parameters.enumerated() {
                let parameterIndex = Int32(index + 1)
                switch parameter {
                case let value as Int:
                    sqlite3_bind_int64(statement, parameterIndex, Int64(value))
                case let value as Int64:
                    sqlite3_bind_int64(statement, parameterIndex, value)
                case let value as Double:
                    sqlite3_bind_double(statement, parameterIndex, value)
                case let value as String:
                    sqlite3_bind_text(statement, parameterIndex, (value as NSString).utf8String, -1, nil)
                case let value as Data:
                    value.withUnsafeBytes { bytes in
                        _ = sqlite3_bind_blob(statement, parameterIndex, bytes.baseAddress, Int32(value.count), nil)
                    }
                case is NSNull:
                    sqlite3_bind_null(statement, parameterIndex)
                default:
                    sqlite3_finalize(statement)
                    result = .error("index: \(index), value: \(parameters[index]) 不支持的参数类型: \(type(of: parameter))")
                    return
                }
            }
            
            // 执行查询
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let columnCount = sqlite3_column_count(statement)
                
                for i in 0..<columnCount {
                    let columnName = String(cString: sqlite3_column_name(statement, i))
                    let type = sqlite3_column_type(statement, i)
                    
                    switch type {
                    case SQLITE_INTEGER:
                        row[columnName] = sqlite3_column_int64(statement, i)
                    case SQLITE_FLOAT:
                        row[columnName] = sqlite3_column_double(statement, i)
                    case SQLITE_TEXT:
                        if let cString = sqlite3_column_text(statement, i) {
                            row[columnName] = String(cString: cString)
                        }
                    case SQLITE_NULL:
                        row[columnName] = NSNull()
                    case SQLITE_BLOB:
                        if let blob = sqlite3_column_blob(statement, i) {
                            let size = Int(sqlite3_column_bytes(statement, i))
                            row[columnName] = Data(bytes: blob, count: size)
                        }
                    default:
                        break
                    }
                }
                
                results.append(row)
            }
            
            // 释放语句
            sqlite3_finalize(statement)
            
            // 如果是INSERT/UPDATE/DELETE语句，返回成功
            if results.isEmpty && (query.lowercased().hasPrefix("insert") || 
                                 query.lowercased().hasPrefix("update") || 
                                 query.lowercased().hasPrefix("delete")) {
                result = .success([[:]])
            } else {
                result = .success(results)
            }
            Logger.debug("成功执行: \(query)")
        }
        
        return result
    }
    
    // MARK: - Contract Methods
    
    /// 删除指定合同的所有物品
    func deleteContractItems(contractId: Int) -> Bool {
        Logger.debug("开始删除合同物品 - 合同ID: \(contractId)")
        let query = "DELETE FROM contract_items WHERE contract_id = ?"
        
        let result = executeQuery(query, parameters: [contractId])
        switch result {
        case .success(_):
            Logger.debug("成功删除合同物品 - 合同ID: \(contractId)")
            return true
        case .error(let error):
            Logger.error("删除合同物品失败 - 合同ID: \(contractId), 错误: \(error)")
            return false
        }
    }
    
    // 获取角色所在的军团ID
    func getCharacterCorporationId(characterId: Int) async throws -> Int? {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    let query = "SELECT corporation_id FROM character_info WHERE character_id = ?"
                    var statement: OpaquePointer?
                    
                    guard let db = self.db else {
                        continuation.resume(throwing: NSError(domain: "EVENexus", code: -1, userInfo: [NSLocalizedDescriptionKey: "数据库未打开"]))
                        return
                    }
                    
                    if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
                        let errmsg = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: NSError(domain: "EVENexus", code: -1, userInfo: [NSLocalizedDescriptionKey: errmsg]))
                        return
                    }
                    
                    sqlite3_bind_int64(statement, 1, Int64(characterId))
                    
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let corporationId = sqlite3_column_int64(statement, 0)
                        sqlite3_finalize(statement)
                        if corporationId > 0 {
                            continuation.resume(returning: Int(corporationId))
                            return
                        }
                    }
                    
                    sqlite3_finalize(statement)
                    
                    // 如果数据库中没有找到，则尝试从API获取最新数据
                    Task {
                        do {
                            let characterInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterId, forceRefresh: true)
                            continuation.resume(returning: characterInfo.corporation_id)
                        } catch {
                            Logger.error("获取角色军团ID失败: \(error)")
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }
} 
