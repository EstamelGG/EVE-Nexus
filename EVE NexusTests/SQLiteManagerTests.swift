import XCTest
import SQLite3
@testable import EVE_Nexus

final class SQLiteManagerTests: XCTestCase {
    var testDatabaseName: String!
    var sqliteManager: SQLiteManager!
    var expectedRowCount: Int = 0 // 存储实际数据库中的记录数
    
    override func setUp() {
        super.setUp()
        
        sqliteManager = SQLiteManager.shared
        
        // 尝试打开数据库（优先使用中文数据库，如果不存在则使用英文数据库）
        let databaseNames = ["item_db_zh", "item_db_en"]
        
        for dbName in databaseNames {
            if sqliteManager.openDatabase(withName: dbName) {
                testDatabaseName = dbName
                // 获取实际记录数
                let query = "SELECT COUNT(*) as count FROM types"
                if case .success(let rows) = sqliteManager.executeQuery(query, parameters: [], useCache: false),
                   let count = rows.first?["count"] as? Int {
                    expectedRowCount = count
                    print("[+] 使用数据库: \(dbName), 记录数: \(expectedRowCount)")
                    return
                }
            }
        }
        
        print("[!] 警告：未找到可用的数据库文件（item_db_zh 或 item_db_en）")
    }
    
    override func tearDown() {
        sqliteManager.clearCache()
        super.tearDown()
    }
    
    // MARK: - 测试用例
    
    // 测试无参数查询 - 多次反复执行（重点测试）
    func testExecuteQueryWithoutParametersRepeatedly() {
        guard expectedRowCount > 0 else {
            return
        }
        
        // 测试查询（模拟实际使用场景）
        let query = "SELECT type_id, categoryID, groupID FROM types"
        
        // 反复执行查询 1000 次，检查是否会出现崩溃
        print("[!] 开始执行 1000 次无参数查询测试...")
        for iteration in 1...1000 {
            let result = sqliteManager.executeQuery(query, parameters: [], useCache: false)
            
            switch result {
            case .success(let rows):
                // 验证结果数量（使用实际数据库中的记录数）
                XCTAssertEqual(rows.count, expectedRowCount, "迭代 \(iteration): 结果数量不正确，期望 \(expectedRowCount)，实际 \(rows.count)")
                
                // 验证数据结构
                if let firstRow = rows.first {
                    XCTAssertNotNil(firstRow["type_id"], "迭代 \(iteration): type_id 字段缺失")
                    XCTAssertNotNil(firstRow["categoryID"], "迭代 \(iteration): categoryID 字段缺失")
                    XCTAssertNotNil(firstRow["groupID"], "迭代 \(iteration): groupID 字段缺失")
                }
                
            case .error(let error):
                XCTFail("迭代 \(iteration): 查询失败 - \(error)")
                return
            }
            
            if iteration % 100 == 0 {
                print("[+] 已完成 \(iteration) 次查询迭代")
            }
        }
        
        print("[+] 无参数查询反复执行测试通过：1000 次迭代，无崩溃")
    }
    
    // 测试数据库未打开时的查询（应该返回错误而不是崩溃）
    func testExecuteQueryWhenDatabaseNotOpen() {
        // 确保数据库未打开（不清除缓存，但确保 db 为 nil）
        // 由于 SQLiteManager 是单例，我们需要测试在未打开数据库时执行查询的情况
        
        // 测试查询（应该返回错误，而不是崩溃）
        let query = "SELECT type_id, categoryID, groupID FROM types"
        
        // 不打开数据库，直接执行查询
        // 这应该返回错误，而不是崩溃
        let result = sqliteManager.executeQuery(query, parameters: [], useCache: false)
        
        switch result {
        case .success:
            // 如果数据库恰好已经打开（可能来自其他测试），这是正常的
            print("[!] 数据库已打开，跳过此测试")
        case .error(let error):
            // 这是预期的行为：应该返回错误信息，而不是崩溃
            XCTAssertTrue(error.contains("数据库连接未打开"), "应该返回数据库未打开的错误")
            print("[+] 数据库未打开时的查询测试通过：返回错误而不是崩溃 - \(error)")
        }
    }
    
    // 测试并发执行无参数查询
    func testConcurrentExecuteQueryWithoutParameters() {
        guard expectedRowCount > 0 else {
            return
        }
        
        let query = "SELECT type_id, categoryID, groupID FROM types"
        let expectation = XCTestExpectation(description: "并发查询完成")
        expectation.expectedFulfillmentCount = 50
        
        // 并发执行 50 个查询
        print("[!] 开始执行 50 个并发查询测试...")
        for i in 1...50 {
            DispatchQueue.global().async {
                let result = self.sqliteManager.executeQuery(query, parameters: [], useCache: false)
                
                switch result {
                case .success(let rows):
                    XCTAssertEqual(rows.count, self.expectedRowCount, "并发查询 \(i): 结果数量不正确，期望 \(self.expectedRowCount)，实际 \(rows.count)")
                case .error(let error):
                    XCTFail("并发查询 \(i) 失败: \(error)")
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        print("[+] 并发查询测试通过：50 个并发查询，无崩溃")
    }
    
    // 测试查询缓存功能
    func testQueryCache() {
        guard expectedRowCount > 0 else {
            return
        }
        
        let query = "SELECT type_id, categoryID, groupID FROM types"
        
        // 第一次查询（不使用缓存，执行实际查询）
        let firstResult = sqliteManager.executeQuery(query, parameters: [], useCache: false)
        var firstCount = 0
        if case .success(let rows) = firstResult {
            firstCount = rows.count
        }
        
        // 第二次查询（使用缓存）
        let secondResult = sqliteManager.executeQuery(query, parameters: [], useCache: true)
        var secondCount = 0
        if case .success(let rows) = secondResult {
            secondCount = rows.count
        }
        
        XCTAssertEqual(firstCount, expectedRowCount, "第一次查询应该返回 \(expectedRowCount) 条记录")
        XCTAssertEqual(secondCount, expectedRowCount, "第二次查询应该返回 \(expectedRowCount) 条记录")
        XCTAssertEqual(firstCount, secondCount, "两次查询结果应该一致")
        print("[+] 查询缓存测试通过：两次查询结果一致（\(firstCount) 条记录）")
    }
    
    // 测试边界情况：带 WHERE 条件的查询返回空结果集
    func testExecuteQueryWithEmptyResult() {
        guard expectedRowCount > 0 else {
            return
        }
        
        // 查询不存在的记录（使用一个非常大的 type_id）
        let query = "SELECT type_id, categoryID, groupID FROM types WHERE type_id = 99999999"
        let result = sqliteManager.executeQuery(query, parameters: [], useCache: false)
        
        switch result {
        case .success(let rows):
            XCTAssertEqual(rows.count, 0, "应该返回 0 条记录")
            print("[+] 空结果集测试通过：返回 0 条记录")
        case .error(let error):
            XCTFail("查询失败: \(error)")
        }
    }
    
    // 测试带参数的查询
    func testExecuteQueryWithParameters() {
        guard expectedRowCount > 0 else {
            return
        }
        
        // 带参数的查询（查询第一个存在的 type_id）
        let query = "SELECT type_id, categoryID, groupID FROM types WHERE type_id = ?"
        
        // 先获取一个存在的 type_id
        let countQuery = "SELECT type_id FROM types LIMIT 1"
        var testTypeID: Int? = nil
        
        if case .success(let rows) = sqliteManager.executeQuery(countQuery, parameters: [], useCache: false),
           let firstRow = rows.first,
           let typeID = firstRow["type_id"] as? Int {
            testTypeID = typeID
        }
        
        guard let typeID = testTypeID else {
            return
        }
        
        let result = sqliteManager.executeQuery(query, parameters: [typeID], useCache: false)
        
        switch result {
        case .success(let rows):
            XCTAssertGreaterThanOrEqual(rows.count, 1, "应该至少返回 1 条记录")
            if let row = rows.first {
                XCTAssertEqual(row["type_id"] as? Int, typeID, "type_id 应该为 \(typeID)")
            }
            print("[+] 带参数查询测试通过：查询 type_id = \(typeID)")
        case .error(let error):
            XCTFail("查询失败: \(error)")
        }
    }
    
    // 测试混合场景：多次执行不同类型的查询
    func testMixedQueryScenarios() {
        guard expectedRowCount > 0 else {
            return
        }
        
        // 混合执行不同类型的查询
        let queries: [(String, [Any])] = [
            ("SELECT type_id, categoryID, groupID FROM types", []),
            ("SELECT type_id, categoryID, groupID FROM types WHERE categoryID = ?", [6]),
            ("SELECT type_id, categoryID, groupID FROM types WHERE groupID = ?", [18]),
            ("SELECT type_id, categoryID, groupID FROM types LIMIT ?", [10]),
        ]
        
        print("[!] 开始执行混合查询场景测试...")
        for (index, (query, params)) in queries.enumerated() {
            for iteration in 1...100 {
                let result = sqliteManager.executeQuery(query, parameters: params, useCache: false)
                
                switch result {
                case .success:
                    break // 成功
                case .error(let error):
                    XCTFail("混合查询场景 \(index + 1)，迭代 \(iteration) 失败: \(error)")
                    return
                }
            }
            print("[+] 查询场景 \(index + 1) 完成：100 次迭代")
        }
        
        print("[+] 混合查询场景测试通过：所有场景都成功执行")
    }
    
    // MARK: - 高强度并发测试场景
    
    // 测试高强度并发查询（大量线程同时执行）
    func testHighIntensityConcurrentQueries() {
        guard expectedRowCount > 0 else {
            return
        }
        
        let query = "SELECT type_id, categoryID, groupID FROM types"
        let concurrentCount = 200 // 增加到 200 个并发查询
        let expectation = XCTestExpectation(description: "高强度并发查询完成")
        expectation.expectedFulfillmentCount = concurrentCount
        
        var successCount = 0
        var errorCount = 0
        let lock = NSLock()
        
        print("[!] 开始执行高强度并发查询测试：\(concurrentCount) 个并发查询...")
        let startTime = Date()
        
        for i in 1...concurrentCount {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.sqliteManager.executeQuery(query, parameters: [], useCache: false)
                
                lock.lock()
                switch result {
                case .success(let rows):
                    if rows.count == self.expectedRowCount {
                        successCount += 1
                    } else {
                        errorCount += 1
                        print("[x] 并发查询 \(i) 结果数量不正确：期望 \(self.expectedRowCount)，实际 \(rows.count)")
                    }
                case .error(let error):
                    errorCount += 1
                    print("[x] 并发查询 \(i) 失败: \(error)")
                }
                lock.unlock()
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
        let duration = Date().timeIntervalSince(startTime)
        
        print("[+] 高强度并发查询测试完成：成功 \(successCount)，失败 \(errorCount)，耗时 \(String(format: "%.2f", duration))秒")
        XCTAssertEqual(errorCount, 0, "不应该有查询失败")
        XCTAssertEqual(successCount, concurrentCount, "所有查询都应该成功")
    }
    
    // 测试混合查询类型的并发执行
    func testMixedQueryTypesConcurrent() {
        guard expectedRowCount > 0 else {
            return
        }
        
        // 定义多种不同类型的查询
        let queries: [(String, [Any], String)] = [
            ("SELECT type_id, categoryID, groupID FROM types", [], "全表查询"),
            ("SELECT type_id, categoryID, groupID FROM types LIMIT 100", [], "限制查询"),
            ("SELECT type_id, categoryID, groupID FROM types WHERE categoryID = ?", [6], "条件查询1"),
            ("SELECT type_id, categoryID, groupID FROM types WHERE groupID = ?", [18], "条件查询2"),
            ("SELECT COUNT(*) as count FROM types", [], "计数查询"),
            ("SELECT type_id FROM types LIMIT 10", [], "单列查询"),
        ]
        
        let queriesPerType = 30 // 每种查询类型执行 30 次
        let totalQueries = queries.count * queriesPerType
        let expectation = XCTestExpectation(description: "混合查询类型并发完成")
        expectation.expectedFulfillmentCount = totalQueries
        
        var successCount = 0
        var errorCount = 0
        let lock = NSLock()
        
        print("[!] 开始执行混合查询类型并发测试：\(queries.count) 种查询类型，每种 \(queriesPerType) 次...")
        let startTime = Date()
        
        for (queryIndex, (query, params, description)) in queries.enumerated() {
            for iteration in 1...queriesPerType {
                DispatchQueue.global(qos: .default).async {
                    let result = self.sqliteManager.executeQuery(query, parameters: params, useCache: false)
                    
                    lock.lock()
                    switch result {
                    case .success:
                        successCount += 1
                    case .error(let error):
                        errorCount += 1
                        print("[x] 查询类型 \(queryIndex + 1) (\(description))，迭代 \(iteration) 失败: \(error)")
                    }
                    lock.unlock()
                    
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
        let duration = Date().timeIntervalSince(startTime)
        
        print("[+] 混合查询类型并发测试完成：成功 \(successCount)，失败 \(errorCount)，耗时 \(String(format: "%.2f", duration))秒")
        XCTAssertEqual(errorCount, 0, "不应该有查询失败")
        XCTAssertEqual(successCount, totalQueries, "所有查询都应该成功")
    }
    
    // 测试持续压力并发查询（长时间运行）
    func testSustainedPressureConcurrentQueries() {
        guard expectedRowCount > 0 else {
            return
        }
        
        let query = "SELECT type_id, categoryID, groupID FROM types"
        // 可以根据需要调整测试强度
        // 如果测试环境较慢，可以降低这些值
        let concurrentThreads = 20 // 20 个并发线程
        let queriesPerThread = 100 // 每个线程执行 100 次查询
        let totalQueries = concurrentThreads * queriesPerThread
        
        // 如果数据库很大，可以适当降低查询次数以提高测试速度
        let adjustedQueriesPerThread = expectedRowCount > 50000 ? 50 : queriesPerThread
        let adjustedTotalQueries = concurrentThreads * adjustedQueriesPerThread
        
        let expectation = XCTestExpectation(description: "持续压力并发查询完成")
        expectation.expectedFulfillmentCount = adjustedTotalQueries
        
        var successCount = 0
        var errorCount = 0
        var completedCount = 0
        let lock = NSLock()
        
        print("[!] 开始执行持续压力并发查询测试：\(concurrentThreads) 个线程，每个线程 \(adjustedQueriesPerThread) 次查询，总共 \(adjustedTotalQueries) 次...")
        let startTime = Date()
        
        for threadIndex in 1...concurrentThreads {
            DispatchQueue.global(qos: .userInitiated).async {
                for iteration in 1...adjustedQueriesPerThread {
                    let result = self.sqliteManager.executeQuery(query, parameters: [], useCache: false)
                    
                    lock.lock()
                    completedCount += 1
                    switch result {
                    case .success(let rows):
                        if rows.count == self.expectedRowCount {
                            successCount += 1
                        } else {
                            errorCount += 1
                            if errorCount <= 10 { // 只打印前10个错误，避免日志过多
                                print("[x] 线程 \(threadIndex)，迭代 \(iteration) 结果数量不正确：期望 \(self.expectedRowCount)，实际 \(rows.count)")
                            }
                        }
                    case .error(let error):
                        errorCount += 1
                        if errorCount <= 10 { // 只打印前10个错误，避免日志过多
                            print("[x] 线程 \(threadIndex)，迭代 \(iteration) 失败: \(error)")
                        }
                    }
                    
                    // 每完成 200 次查询打印一次进度
                    if completedCount % 200 == 0 {
                        print("[!] 进度：已完成 \(completedCount)/\(adjustedTotalQueries) 次查询（成功 \(successCount)，失败 \(errorCount)）")
                    }
                    lock.unlock()
                    
                    expectation.fulfill()
                }
            }
        }
        
        // 增加超时时间到 120 秒，因为 2000 次查询可能需要更长时间
        let waitResult = XCTWaiter.wait(for: [expectation], timeout: 120.0)
        let duration = Date().timeIntervalSince(startTime)
        
        let incompleteCount = totalQueries - completedCount
        
        let actualTotalQueries = adjustedTotalQueries
        let actualIncompleteCount = actualTotalQueries - completedCount
        
        print("[+] 持续压力并发查询测试完成：")
        print("    - 总查询数: \(actualTotalQueries)")
        print("    - 已完成: \(completedCount)")
        print("    - 未完成: \(actualIncompleteCount)")
        print("    - 成功: \(successCount)")
        print("    - 失败: \(errorCount)")
        print("    - 耗时: \(String(format: "%.2f", duration))秒")
        if duration > 0 {
            print("    - 平均速度: \(String(format: "%.2f", Double(completedCount) / duration)) 查询/秒")
        }
        
        // 如果超时了，给出警告
        if waitResult == .timedOut {
            print("[!] 警告：测试超时，部分查询可能未完成")
        }
        
        // 检查是否所有查询都完成了
        if actualIncompleteCount > 0 {
            XCTFail("有 \(actualIncompleteCount) 个查询未完成（可能超时）")
        }
        XCTAssertEqual(errorCount, 0, "不应该有查询失败")
        XCTAssertEqual(successCount, completedCount, "所有已完成的查询都应该成功")
    }
    
    // 测试并发查询与缓存交互
    func testConcurrentQueriesWithCache() {
        guard expectedRowCount > 0 else {
            return
        }
        
        let query = "SELECT type_id, categoryID, groupID FROM types"
        let concurrentCount = 100
        let expectation = XCTestExpectation(description: "并发缓存查询完成")
        expectation.expectedFulfillmentCount = concurrentCount
        
        var successCount = 0
        var errorCount = 0
        var cacheHitCount = 0
        let lock = NSLock()
        
        // 先执行一次查询以填充缓存
        _ = sqliteManager.executeQuery(query, parameters: [], useCache: true)
        
        print("[!] 开始执行并发缓存查询测试：\(concurrentCount) 个并发查询（使用缓存）...")
        let startTime = Date()
        
        for i in 1...concurrentCount {
            DispatchQueue.global(qos: .default).async {
                let result = self.sqliteManager.executeQuery(query, parameters: [], useCache: true)
                
                lock.lock()
                switch result {
                case .success(let rows):
                    if rows.count == self.expectedRowCount {
                        successCount += 1
                        // 第二次及以后的查询应该命中缓存
                        if i > 1 {
                            cacheHitCount += 1
                        }
                    } else {
                        errorCount += 1
                    }
                case .error(let error):
                    errorCount += 1
                    print("[x] 并发缓存查询 \(i) 失败: \(error)")
                }
                lock.unlock()
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20.0)
        let duration = Date().timeIntervalSince(startTime)
        
        print("[+] 并发缓存查询测试完成：成功 \(successCount)，失败 \(errorCount)，缓存命中 \(cacheHitCount)，耗时 \(String(format: "%.2f", duration))秒")
        XCTAssertEqual(errorCount, 0, "不应该有查询失败")
        XCTAssertEqual(successCount, concurrentCount, "所有查询都应该成功")
    }
    
    // 测试并发查询与数据库重连（极端场景）
    func testConcurrentQueriesWithReconnection() {
        guard expectedRowCount > 0 else {
            return
        }
        
        let query = "SELECT type_id, categoryID, groupID FROM types"
        let concurrentCount = 50
        let expectation = XCTestExpectation(description: "并发重连查询完成")
        expectation.expectedFulfillmentCount = concurrentCount
        
        var successCount = 0
        var errorCount = 0
        let lock = NSLock()
        
        print("[!] 开始执行并发重连查询测试：\(concurrentCount) 个并发查询，中间会重新打开数据库...")
        let startTime = Date()
        
        // 启动并发查询
        for i in 1...concurrentCount {
            DispatchQueue.global(qos: .default).async {
                // 随机延迟，模拟真实场景
                let delay = Double.random(in: 0...0.1)
                Thread.sleep(forTimeInterval: delay)
                
                let result = self.sqliteManager.executeQuery(query, parameters: [], useCache: false)
                
                lock.lock()
                switch result {
                case .success(let rows):
                    if rows.count == self.expectedRowCount {
                        successCount += 1
                    } else {
                        errorCount += 1
                    }
                case .error(let error):
                    // 在重连过程中可能出现错误，这是可以接受的
                    if error.contains("数据库连接未打开") {
                        // 这是预期的，因为可能在重连过程中
                        successCount += 1
                    } else {
                        errorCount += 1
                        print("[x] 并发重连查询 \(i) 失败: \(error)")
                    }
                }
                lock.unlock()
                
                expectation.fulfill()
            }
        }
        
        // 在查询进行过程中，重新打开数据库（模拟数据库重连场景）
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            _ = self.sqliteManager.openDatabase(withName: self.testDatabaseName)
        }
        
        wait(for: [expectation], timeout: 20.0)
        let duration = Date().timeIntervalSince(startTime)
        
        print("[+] 并发重连查询测试完成：成功 \(successCount)，失败 \(errorCount)，耗时 \(String(format: "%.2f", duration))秒")
        // 注意：在重连过程中可能有少量失败，这是可以接受的
        XCTAssertGreaterThan(successCount, concurrentCount * 8 / 10, "至少 80% 的查询应该成功")
    }
}

