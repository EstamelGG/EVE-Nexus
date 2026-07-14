import SwiftUI

struct CalculatorView: View {
    @StateObject private var databaseManager = DatabaseManager.shared

    var body: some View {
        List {
            // 工业计算器
            Section(header: Text(NSLocalizedString("Calculator_Industry_Section", comment: "工业"))) {
                NavigationLink(destination: BlueprintCalculatorView()) {
                    HStack {
                        Image("industry")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("Calculator_Blueprint", comment: ""))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                NavigationLink(destination: OreRefineryCalculatorView(databaseManager: databaseManager)) {
                    HStack {
                        Image("reprocess")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("Calculator_Ore_Refinery", comment: ""))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                NavigationLink(destination: MutationCalculatorView(databaseManager: databaseManager)) {
                    HStack {
                        Image("attributes")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("Calculator_Mutation", comment: ""))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 行星开发计算器
            Section(header: Text(NSLocalizedString("Calculator_PI_Section", comment: "行星开发（Planetary Industry）"))) {
                NavigationLink(destination: PIOutputCalculatorView(characterId: nil)) {
                    HStack {
                        Image("planets")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("Main_Planetary_Output", comment: ""))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                NavigationLink(destination: PlanetarySiteFinder(characterId: nil)) {
                    HStack {
                        Image("planets")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("Main_Planetary_location_calc", comment: ""))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                NavigationLink(destination: PIAllInOneMainView(characterId: nil)) {
                    HStack {
                        Image("planets")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("Planet_All-in-One_Calc", comment: ""))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                NavigationLink(destination: PIAllInOneSystemFinderMainView(characterId: nil)) {
                    HStack {
                        Image("planets")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("AllInOne_SystemFinder_Title", comment: "查找 All-in-One 星系"))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                NavigationLink(destination: PIProductionChainView(characterId: nil)) {
                    HStack {
                        Image("planets")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        Text(NSLocalizedString("PI_Chain_Title", comment: "生产链分析"))
                            .font(.body)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Calculator_Title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }
}
