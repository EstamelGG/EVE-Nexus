import SwiftUI

/// 通用的位置信息显示组件
struct LocationInfoView: View {
    let stationName: String?
    let solarSystemName: String?
    let security: Double?
    let locationId: Int64?
    let font: Font
    let textColor: Color
    let inSpaceNote: String?
    
    init(
        stationName: String?,
        solarSystemName: String?,
        security: Double?,
        locationId: Int64? = nil,
        font: Font = .caption,
        textColor: Color = .secondary,
        inSpaceNote: String? = nil
    ) {
        self.stationName = stationName
        self.solarSystemName = solarSystemName
        self.security = security
        self.locationId = locationId
        self.font = font
        self.textColor = textColor
        self.inSpaceNote = inSpaceNote
    }
    
    var body: some View {
        if let stationName = stationName,
           let solarSystemName = solarSystemName {
            // 空间站或建筑物场景
            if stationName.hasPrefix(solarSystemName) {
                // 如果空间站名称以星系名开头
                (Text(security != nil ? "\(formatSystemSecurity(security!)) " : "0.0 ")
                    .foregroundColor(security != nil ? getSecurityColor(security!) : .red) +
                Text(solarSystemName)
                    .fontWeight(.bold) +
                Text(stationName.dropFirst(solarSystemName.count)))
                    .font(font)
                    .foregroundColor(textColor)
            } else {
                // 如果空间站名称不以星系名开头
                (Text(security != nil ? "\(formatSystemSecurity(security!)) " : "0.0 ")
                    .foregroundColor(security != nil ? getSecurityColor(security!) : .red) +
                Text("\(solarSystemName) - \(stationName)"))
                    .font(font)
                    .foregroundColor(textColor)
            }
        } else if let solarSystemName = solarSystemName {
            // 在太空中的场景
            (Text(security != nil ? "\(formatSystemSecurity(security!)) " : "0.0 ")
                .foregroundColor(security != nil ? getSecurityColor(security!) : .red) +
            Text("\(solarSystemName)") +
            (inSpaceNote != nil ? Text(" (\(inSpaceNote!))") : Text("")))
                .font(font)
                .foregroundColor(textColor)
        } else if let locationId = locationId {
            // 未知位置但有ID
            (Text(security != nil ? "\(formatSystemSecurity(security!)) " : "0.0 ")
                .foregroundColor(security != nil ? getSecurityColor(security!) : .red) +
            Text("\(NSLocalizedString("Assets_Unknown_Location", comment: "")) (\(locationId))"))
                .font(font)
                .foregroundColor(textColor)
        } else {
            // 完全未知的位置
            (Text(security != nil ? "\(formatSystemSecurity(security!)) " : "0.0 ")
                .foregroundColor(security != nil ? getSecurityColor(security!) : .red) +
            Text(NSLocalizedString("Assets_Unknown_Location", comment: "")))
                .font(font)
                .foregroundColor(textColor)
        }
    }
}
