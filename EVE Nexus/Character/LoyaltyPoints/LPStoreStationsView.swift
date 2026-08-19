import SwiftUI

/// LP 商店空间站行数据
struct LPStoreStation: Identifiable {
    let stationID: Int
    let stationName: String
    let solarSystemID: Int
    let solarSystemName: String
    let security: Double?
    let regionID: Int
    let iconFileName: String

    var id: Int {
        stationID
    }
}

/// 某军团 LP 商店所在空间站列表（SDE stations 表 LPStore 列），按星域分 section
struct LPStoreStationsView: View {
    let corporationId: Int
    let corporationName: String

    @State private var stationsByRegion: [(regionID: Int, regionName: String, stations: [LPStoreStation])] = []
    @State private var isLoading = true
    @State private var mapNavigation: RegionNavigation?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if stationsByRegion.isEmpty {
                NoDataSection()
            } else {
                ForEach(stationsByRegion, id: \.regionID) { region in
                    Section {
                        ForEach(region.stations) { station in
                            HStack(spacing: 12) {
                                IconManager.shared.loadImage(for: station.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(6)
                                    .frame(width: 36, height: 36)

                                LocationInfoView(
                                    stationName: station.stationName,
                                    solarSystemName: station.solarSystemName,
                                    security: station.security,
                                    locationId: Int64(station.stationID),
                                    font: .body,
                                    textColor: .primary
                                )

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack {
                            Text("\(region.regionName) (\(region.stations.count))")
                            Spacer()
                            // 仅当地图数据包含该星域时显示（虫洞等星域不在地图中，SDE 初始化预载的内存集合）
                            if StarMapRegionAvailability.isAvailable(region.regionID) {
                                Button {
                                    // 高亮该星域内所有 LP 空间站所在星系
                                    mapNavigation = .regionMap(
                                        region.regionID,
                                        region.regionName,
                                        Array(Set(region.stations.map(\.solarSystemID)))
                                    )
                                } label: {
                                    Text(NSLocalizedString("LP_Show_Map", comment: ""))
                                        .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(corporationName)
        .navigationDestination(item: $mapNavigation) { navigation in
            switch navigation {
            case let .regionMap(regionId, regionName, systemIds):
                RegionSystemMapView(
                    databaseManager: DatabaseManager.shared,
                    regionId: regionId,
                    regionName: regionName,
                    highlightSystemIds: systemIds
                )
            }
        }
        .task {
            await loadStations()
        }
    }

    /// 从 SDEMemoryStore 内存查询 LP 商店属于该军团的空间站
    private func loadStations() async {
        let stationInfos = SDEMemoryStore.stationsWithLPStore(corporationId: corporationId)

        var regionDict: [Int: [LPStoreStation]] = [:]
        for info in stationInfos {
            let regionID = info.regionID ?? 0
            let solarSystemID = info.solarSystemID ?? 0
            let iconFileName = info.stationTypeID.flatMap { typeId in
                SDEMemoryStore.type(for: typeId)?.iconFilename
            } ?? "not_found"

            let station = LPStoreStation(
                stationID: info.id,
                stationName: info.name,
                solarSystemID: solarSystemID,
                solarSystemName: SDEMemoryStore.solarSystemName(for: solarSystemID) ?? "",
                security: info.security,
                regionID: regionID,
                iconFileName: iconFileName
            )
            regionDict[regionID, default: []].append(station)
        }

        stationsByRegion = regionDict.map { regionID, stations in
            (
                regionID: regionID,
                regionName: SDEMemoryStore.regionName(for: regionID) ?? "Region \(regionID)",
                // 按星系 ID 排序，同星系内按空间站 ID 排序
                stations: stations.sorted {
                    $0.solarSystemID == $1.solarSystemID
                        ? $0.stationID < $1.stationID
                        : $0.solarSystemID < $1.solarSystemID
                }
            )
        }
        .sorted {
            $0.regionName.localizedStandardCompare($1.regionName) == .orderedAscending
        }

        isLoading = false
    }
}
