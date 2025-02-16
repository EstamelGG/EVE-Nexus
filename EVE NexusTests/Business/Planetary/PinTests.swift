import XCTest
@testable import EVE_Nexus

final class PinTests: XCTestCase {
    
    func testExtractorTypeIdentification() {
        // 测试采集器
        XCTAssertTrue(Pin(id: 1, typeId: 2409, groupId: 1026, capacity: 1000).isExtractor())
        XCTAssertTrue(Pin(id: 1, typeId: 2412, groupId: 1026, capacity: 1000).isExtractor())
        
        // 测试悬浮等离子采集器
        XCTAssertTrue(Pin(id: 1, typeId: 2417, capacity: 1000).isExtractor())
        XCTAssertTrue(Pin(id: 1, typeId: 2418, capacity: 1000).isExtractor())
        
        // 测试非采集器
        XCTAssertFalse(Pin(id: 1, typeId: 2469, groupId: 1028, capacity: 1000).isExtractor()) // 处理设施
        XCTAssertFalse(Pin(id: 1, typeId: 2257, groupId: 1029, capacity: 1000).isExtractor()) // 储藏设施
    }
    
    func testProcessorTypeIdentification() {
        // 测试处理设施
        XCTAssertTrue(Pin(id: 1, typeId: 2469, groupId: 1028, capacity: 1000).isProcessor()) // 基础工业设施
        XCTAssertTrue(Pin(id: 1, typeId: 2470, groupId: 1028, capacity: 1000).isProcessor()) // 高级工业设施
        
        // 测试非处理设施
        XCTAssertFalse(Pin(id: 1, typeId: 2409, groupId: 1026, capacity: 1000).isProcessor()) // 采集器
        XCTAssertFalse(Pin(id: 1, typeId: 2257, groupId: 1029, capacity: 1000).isProcessor()) // 储藏设施
    }
    
    func testStorageTypeIdentification() {
        // 测试储藏设施
        XCTAssertTrue(Pin(id: 1, typeId: 2257, groupId: 1029, capacity: 1000).isStorage()) // 冰体行星
        XCTAssertTrue(Pin(id: 1, typeId: 2535, groupId: 1029, capacity: 1000).isStorage()) // 海洋行星
        XCTAssertTrue(Pin(id: 1, typeId: 2536, capacity: 1000).isStorage()) // 气体行星
        
        // 测试非储藏设施
        XCTAssertFalse(Pin(id: 1, typeId: 2409, groupId: 1026, capacity: 1000).isStorage()) // 采集器
        XCTAssertFalse(Pin(id: 1, typeId: 2469, groupId: 1028, capacity: 1000).isStorage()) // 处理设施
    }
    
    func testCommandCenterTypeIdentification() {
        // 测试指挥中心
        XCTAssertTrue(Pin(id: 1, typeId: 2254, groupId: 1027, capacity: 1000).isCommandCenter()) // 温和行星
        XCTAssertTrue(Pin(id: 1, typeId: 2524, groupId: 1027, capacity: 1000).isCommandCenter()) // 贫瘠行星
        
        // 测试高级指挥中心
        XCTAssertTrue(Pin(id: 1, typeId: 2132, capacity: 1000).isCommandCenter()) // 贫瘠行星高级
        XCTAssertTrue(Pin(id: 1, typeId: 2137, capacity: 1000).isCommandCenter()) // 气体行星高级
        
        // 测试非指挥中心
        XCTAssertFalse(Pin(id: 1, typeId: 2409, groupId: 1026, capacity: 1000).isCommandCenter()) // 采集器
        XCTAssertFalse(Pin(id: 1, typeId: 2469, groupId: 1028, capacity: 1000).isCommandCenter()) // 处理设施
        XCTAssertFalse(Pin(id: 1, typeId: 2257, groupId: 1029, capacity: 1000).isCommandCenter()) // 储藏设施
    }
    
    func testConsumerIdentification() {
        // 处理设施是消费者
        XCTAssertTrue(Pin(id: 1, typeId: 2469, groupId: 1028, capacity: 1000).isConsumer())
        XCTAssertTrue(Pin(id: 1, typeId: 2470, groupId: 1028, capacity: 1000).isConsumer())
        
        // 其他设施不是消费者
        XCTAssertFalse(Pin(id: 1, typeId: 2409, groupId: 1026, capacity: 1000).isConsumer()) // 采集器
        XCTAssertFalse(Pin(id: 1, typeId: 2257, groupId: 1029, capacity: 1000).isConsumer()) // 储藏设施
        XCTAssertFalse(Pin(id: 1, typeId: 2254, groupId: 1027, capacity: 1000).isConsumer()) // 指挥中心
    }
} 