import SwiftUI

/// 通用的位置信息显示组件
struct LocationInfoView: View {
    let stationName: String?
    let solarSystemName: String?
    let security: Double?
    let locationId: Int64?
    let font: Font
    let textColor: Color
    
    init(
        stationName: String?,
        solarSystemName: String?,
        security: Double?,
        locationId: Int64? = nil,
        font: Font = .caption,
        textColor: Color = .secondary
    ) {
        self.stationName = stationName
        self.solarSystemName = solarSystemName
        self.security = security
        self.locationId = locationId
        self.font = font
        self.textColor = textColor
    }
    
    private func formatSecurity(_ security: Double) -> String {
        String(format: "%.1f", security)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let security = security {
                Text(formatSecurity(security))
                    .foregroundColor(getSecurityColor(security))
            } else {
                Text("0.0")
                    .foregroundColor(.red)
            }
            
            if let stationName = stationName,
               let solarSystemName = solarSystemName {
                // 检查空间站名称是否以星系名开头
                if stationName.hasPrefix(solarSystemName) {
                    // 如果是，将星系名部分加粗
                    Text(solarSystemName)
                        .fontWeight(.bold) +
                    Text(stationName.dropFirst(solarSystemName.count))
                } else {
                    Text(stationName)
                }
            } else if let locationId = locationId {
                Text("\(NSLocalizedString("Assets_Unknown_Location", comment: "")) (\(locationId))")
            } else {
                Text(NSLocalizedString("Assets_Unknown_Location", comment: ""))
            }
        }
        .font(font)
        .foregroundColor(textColor)
    }
}
