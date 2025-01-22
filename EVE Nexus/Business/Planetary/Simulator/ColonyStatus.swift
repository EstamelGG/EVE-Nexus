import Foundation

/// 殖民地设施状态
enum PinStatus: String {
    case idle = "IDLE"
    case active = "ACTIVE"
    case storageFull = "STORAGE_FULL"
    case inputMissing = "INPUT_MISSING"
    case outputFull = "OUTPUT_FULL"
}

/// 殖民地状态
struct ColonyStatus {
    struct PinStatusInfo {
        let pinId: Int64
        let status: PinStatus
    }
    
    let pins: [PinStatusInfo]
    var isWorking: Bool {
        pins.contains { $0.status == .active }
    }
} 