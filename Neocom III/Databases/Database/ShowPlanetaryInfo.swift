import SwiftUI

struct ShowPlanetaryInfo: View {
    let itemID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    // 基础信息
    @State private var itemDetails: ItemDetails?
    
    // 行星开发数据
    @State private var inputs: [(typeID: Int, name: String, iconFileName: String, quantity: Int)] = []
    @State private var output: (outputValue: Int, cycleTime: Int)?
    @State private var uses: [(typeID: Int, name: String, iconFileName: String)] = []
    
    // 添加设施状态
    @State private var facilities: [(typeID: Int, name: String, iconFileName: String)] = []
    
    var body: some View {
        List {
            // 基础信息部分
            if let itemDetails = itemDetails {
                Section {
                    HStack {
                        IconManager.shared.loadImage(for: itemDetails.iconFileName)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(itemDetails.name)
                                .font(.title2)
                            Text("\(itemDetails.categoryName) / \(itemDetails.groupName)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    let desc = itemDetails.description
                    if !desc.isEmpty {
                        processRichText(desc)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            // 输入材料部分
            if !inputs.isEmpty {
                Section(header: Text(NSLocalizedString("Planetary_Input_Materials", comment: "")).font(.headline)) {
                    ForEach(inputs, id: \.typeID) { input in
                        NavigationLink {
                            if let categoryID = databaseManager.getCategoryID(for: input.typeID) {
                                ItemInfoMap.getItemInfoView(
                                    itemID: input.typeID,
                                    categoryID: categoryID,
                                    databaseManager: databaseManager
                                )
                            }
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: input.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                Text(input.name)
                                    .font(.body)
                                
                                Spacer()
                                
                                Text("\(input.quantity) \(NSLocalizedString("Misc_number_item", comment: ""))")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            // 输出信息部分
            if let output = output {
                Section(header: Text(NSLocalizedString("Planetary_Output_Info", comment: "")).font(.headline)) {
                    HStack {
                        Text(NSLocalizedString("Planetary_Output_Quantity", comment: ""))
                        Spacer()
                        Text("\(output.outputValue) \(NSLocalizedString("Misc_number_item", comment: ""))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("Planetary_Cycle_Time", comment: ""))
                        Spacer()
                        Text(formatTime(output.cycleTime))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 用途部分
            if !uses.isEmpty {
                Section(header: Text(NSLocalizedString("Planetary_Uses", comment: "")).font(.headline)) {
                    ForEach(uses, id: \.typeID) { use in
                        NavigationLink {
                            if let categoryID = databaseManager.getCategoryID(for: use.typeID) {
                                ItemInfoMap.getItemInfoView(
                                    itemID: use.typeID,
                                    categoryID: categoryID,
                                    databaseManager: databaseManager
                                )
                            }
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: use.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                Text(use.name)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            
            // 设施部分
            if !facilities.isEmpty {
                Section(header: Text(NSLocalizedString("Planetary_Facilities", comment: "")).font(.headline)) {
                    ForEach(facilities, id: \.typeID) { facility in
                        NavigationLink {
                            if let categoryID = databaseManager.getCategoryID(for: facility.typeID) {
                                ItemInfoMap.getItemInfoView(
                                    itemID: facility.typeID,
                                    categoryID: categoryID,
                                    databaseManager: databaseManager
                                )
                            }
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: facility.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                Text(facility.name)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Info")
        .onAppear {
            loadItemDetails()
            loadPlanetaryData()
        }
    }
    
    // MARK: - Data Loading Methods
    private func loadItemDetails() {
        itemDetails = databaseManager.getItemDetails(for: itemID)
    }
    
    private func loadPlanetaryData() {
        loadInputs()
        loadOutput()
        loadUses()
        loadFacilities()
    }
    
    private func loadInputs() {
        let query = """
        SELECT input_typeid, input_value 
        FROM planetSchematics 
        WHERE output_typeid = ?
        """
        let result = databaseManager.executeQuery(query, parameters: [itemID])
        
        if case .success(let rows) = result, let row = rows.first {
            if let inputTypeIDs = row["input_typeid"] as? String,
               let inputValues = row["input_value"] as? String {
                let typeIDs = inputTypeIDs.split(separator: ",").compactMap { Int($0) }
                let values = inputValues.split(separator: ",").compactMap { Int($0) }
                
                inputs = zip(typeIDs, values).compactMap { typeID, quantity in
                    guard let details = databaseManager.getItemDetails(for: typeID) else { return nil }
                    return (typeID: typeID, name: details.name, iconFileName: details.iconFileName, quantity: quantity)
                }
            }
        }
    }
    
    private func loadOutput() {
        let query = """
        SELECT output_value, cycle_time 
        FROM planetSchematics 
        WHERE output_typeid = ?
        """
        let result = databaseManager.executeQuery(query, parameters: [itemID])
        
        if case .success(let rows) = result, let row = rows.first {
            if let outputValue = row["output_value"] as? Int,
               let cycleTime = row["cycle_time"] as? Int {
                output = (outputValue: outputValue, cycleTime: cycleTime)
            }
        }
    }
    
    private func loadUses() {
        let query = """
        SELECT output_typeid 
        FROM planetSchematics 
        WHERE instr(',' || input_typeid || ',', ',\(itemID),') > 0
        """
        let result = databaseManager.executeQuery(query)
        
        if case .success(let rows) = result {
            uses = rows.compactMap { row in
                guard let typeID = row["output_typeid"] as? Int,
                      let details = databaseManager.getItemDetails(for: typeID) else { return nil }
                return (typeID: typeID, name: details.name, iconFileName: details.iconFileName)
            }
        }
    }
    
    // 添加设施加载方法
    private func loadFacilities() {
        let query = """
        SELECT facilitys 
        FROM planetSchematics 
        WHERE output_typeid = ?
        """
        let result = databaseManager.executeQuery(query, parameters: [itemID])
        
        if case .success(let rows) = result, let row = rows.first {
            if let facilityIDs = row["facilitys"] as? String {
                facilities = facilityIDs.split(separator: ",")
                    .compactMap { Int($0) }
                    .compactMap { facilityID in
                        guard let details = databaseManager.getItemDetails(for: facilityID) else { 
                            return nil 
                        }
                        return (
                            typeID: facilityID,
                            name: details.name,
                            iconFileName: details.iconFileName
                        )
                    }
            }
        }
    }
}
