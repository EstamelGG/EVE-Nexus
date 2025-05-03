import XCTest
@testable import EVE_Nexus

final class FormatUtilTests: XCTestCase {
    // MARK: - format 测试
    func testFormat() {
        // 基本格式化测试
        XCTAssertEqual(FormatUtil.format(1234.567), "1,234.567")
        XCTAssertEqual(FormatUtil.format(1234.0), "1,234")
        XCTAssertEqual(FormatUtil.format(1234.567, false), "1,235")
        
        // 不同小数位数测试
        XCTAssertEqual(FormatUtil.format(1234.567), "1,234.567")
        XCTAssertEqual(FormatUtil.format(1234.500), "1,234.5")
        XCTAssertEqual(FormatUtil.format(1234.000), "1,234")
        
        // 边界值测试
        XCTAssertEqual(FormatUtil.format(0), "0")
        XCTAssertEqual(FormatUtil.format(0.001), "0.001")
        XCTAssertEqual(FormatUtil.format(999999.999), "999,999.999")
    }
    
    // MARK: - formatWithMillisecondPrecision 测试
    func testFormatWithMillisecondPrecision() {
        // 毫秒精度测试
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(1.234), "1.234")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(1.230), "1.23")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(1.200), "1.2")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(1.000), "1")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(0.001), "0.001")
        
        // 边界值测试
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(0), "0")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(0.0001), "0.0001")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(999.999), "999.999")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(999.900), "999.9")
        XCTAssertEqual(FormatUtil.formatWithMillisecondPrecision(999.000), "999")
    }
    
    // MARK: - formatFileSize 测试
    func testFormatFileSize() {
        // 基本单位测试
        XCTAssertEqual(FormatUtil.formatFileSize(1024), "1.00 KB")
        XCTAssertEqual(FormatUtil.formatFileSize(1024 * 1024), "1.00 MB")
        XCTAssertEqual(FormatUtil.formatFileSize(1024 * 1024 * 1024), "1.00 GB")
        
        // 小数位数测试
        XCTAssertEqual(FormatUtil.formatFileSize(1500), "1.46 KB")
        XCTAssertEqual(FormatUtil.formatFileSize(1500000), "1.43 MB")
        XCTAssertEqual(FormatUtil.formatFileSize(15000000), "14.3 MB")
        XCTAssertEqual(FormatUtil.formatFileSize(1604608), "1.53 MB")
        XCTAssertEqual(FormatUtil.formatFileSize(150000000), "143 MB")
        
        // 边界值测试
        XCTAssertEqual(FormatUtil.formatFileSize(0), "0 bytes")
        XCTAssertEqual(FormatUtil.formatFileSize(999), "999 bytes")
        XCTAssertEqual(FormatUtil.formatFileSize(1023), "1023 bytes")
    }
    
    // MARK: - formatISK 测试
    func testFormatISK() {
        // 不同单位测试
        XCTAssertEqual(FormatUtil.formatISK(1200), "1.20K ISK")
        XCTAssertEqual(FormatUtil.formatISK(1200000), "1.20M ISK")
        XCTAssertEqual(FormatUtil.formatISK(1200000000), "1.20B ISK")
        XCTAssertEqual(FormatUtil.formatISK(1200000000000), "1.20T ISK")
        
        // 小数位数测试
        XCTAssertEqual(FormatUtil.formatISK(1234), "1.23K ISK")
        XCTAssertEqual(FormatUtil.formatISK(12345), "12.35K ISK")
        XCTAssertEqual(FormatUtil.formatISK(123456), "123.46K ISK")
        XCTAssertEqual(FormatUtil.formatISK(1234567), "1.23M ISK")
        
        // 边界值测试
        XCTAssertEqual(FormatUtil.formatISK(0), "0 ISK")
        XCTAssertEqual(FormatUtil.formatISK(999), "999 ISK")
        XCTAssertEqual(FormatUtil.formatISK(999999999999999), "1000.00T ISK")
    }
    
    // MARK: - formatTimeWithMillisecondPrecision 测试
    func testFormatTimeWithMillisecondPrecision() {
        // 基本时间单位测试
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(1000), "1s")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(1500), "1.5s")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(61000), "1m 1s")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(3661000), "1h 1m 1s")
        
        // 毫秒测试
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(0.5), "0.5ms")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(0.001), "0.001ms")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(0.999), "0.999ms")
        
        // 边界值测试
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(0), "0ms")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(86400000), "1d")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(86461000), "1d 0h 1m 1s")
        XCTAssertEqual(FormatUtil.formatTimeWithMillisecondPrecision(86461000.5), "1d 0h 1m 1.0005s")
    }
    
    // MARK: - formatTimeWithPrecision 测试
    func testFormatTimeWithPrecision() {
        // 基本时间单位测试
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(1.5), "1.5s")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(61.5), "1m 1.5s")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(3661.5), "1h 1m 1.5s")
        
        // 小数测试
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(0.5), "0.5s")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(0.001), "0.001s")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(0.0001), "0s")
        
        // 边界值测试
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(0), "0s")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(86400), "1d")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(86461.5), "1d 0h 1m 1.5s")
        XCTAssertEqual(FormatUtil.formatTimeWithPrecision(86461.001), "1d 0h 1m 1.001s")
    }
} 
