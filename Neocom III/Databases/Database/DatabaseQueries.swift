import SQLite3

enum Database {
    // MARK: - Categories
    enum Categories {
        static func loadCategories(from db: OpaquePointer?) -> ([Category], [Category]) {
            var publishedCategories: [Category] = []
            var unpublishedCategories: [Category] = []
            
            guard let db = db else { return ([], []) }

            let query = """
            SELECT category_id, name, published, icon_filename FROM categories ORDER BY category_id
            """
            
            let categories: [Category] = executeQuery(
                db: db,
                query: query, bindParams: [], bind: nil,
                resultProcessor: { statement in
                    let id = Int(sqlite3_column_int(statement, 0))
                    let name = String(cString: sqlite3_column_text(statement, 1))
                    let published = sqlite3_column_int(statement, 2) != 0
                    let iconFileName = String(cString: sqlite3_column_text(statement, 3))
                    
                    let finalIconFileName = iconFileName.isEmpty ? DatabaseConfig.defaultIcon : iconFileName
                    
                    return Category(
                        id: id,
                        name: name,
                        published: published,
                        iconID: id,
                        iconFileNew: finalIconFileName
                    )
                }
            )
            
            publishedCategories = categories.filter { $0.published }
            unpublishedCategories = categories.filter { !$0.published }

            return (publishedCategories, unpublishedCategories)
        }
    }
    
    // MARK: - Groups
    enum Groups {
        static func loadGroups(for categoryID: Int, db: OpaquePointer?) -> ([Group], [Group]) {
            var publishedGroups: [Group] = []
            var unpublishedGroups: [Group] = []
            
            guard let db = db else { return ([], []) }

            let query = """
            SELECT group_id, name, categoryID, published, icon_filename 
            FROM groups 
            WHERE categoryID = ? 
            ORDER BY group_id
            """
            
            let groups: [Group] = executeQuery(
                db: db,
                query: query, bindParams: [categoryID],
                bind: { statement in
                    sqlite3_bind_int(statement, 1, Int32(categoryID))
                },
                resultProcessor: { statement in
                    let id = Int(sqlite3_column_int(statement, 0))
                    var name = String(cString: sqlite3_column_text(statement, 1))
                    if name.isEmpty {
                        name = "Unknown"
                    }
                    let categoryID = Int(sqlite3_column_int(statement, 2))
                    let published = sqlite3_column_int(statement, 3) != 0
                    var iconFileName = String(cString: sqlite3_column_text(statement, 4))
                    if iconFileName.isEmpty {
                        iconFileName = DatabaseConfig.defaultIcon
                    }
                    
                    return Group(
                        id: id,
                        name: name,
                        iconID: id,
                        categoryID: categoryID,
                        published: published,
                        icon_filename: iconFileName
                    )
                }
            )
            
            publishedGroups = groups.filter { $0.published }
            unpublishedGroups = groups.filter { !$0.published }

            return (publishedGroups, unpublishedGroups)
        }
    }
    
    // MARK: - Items
    enum Items {
        static func loadItems(for groupID: Int, db: OpaquePointer?) -> ([DatabaseItem], [DatabaseItem], [Int: String]) {
            var publishedItems: [DatabaseItem] = []
            var unpublishedItems: [DatabaseItem] = []
            var metaGroupNames: [Int: String] = [:]
            
            guard let db = db else { return ([], [], [:]) }

            let query = """
            SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published,
                   categoryID, rig_cost,
                   em_damage, them_damage, kin_damage, exp_damage,
                   high_slot, mid_slot, low_slot, rig_slot, gun_slot, miss_slot
            FROM types
            WHERE groupID = ?
            ORDER BY metaGroupID
            """
            
            let results: [DatabaseItem] = executeQuery(
                db: db,
                query: query, bindParams: [groupID],
                bind: { statement in
                    sqlite3_bind_int(statement, 1, Int32(groupID))
                },
                resultProcessor: { statement in
                    let emDamage = sqlite3_column_type(statement, 9) != SQLITE_NULL ? 
                        Double(sqlite3_column_double(statement, 9)) : nil
                    let themDamage = sqlite3_column_type(statement, 10) != SQLITE_NULL ? 
                        Double(sqlite3_column_double(statement, 10)) : nil
                    let kinDamage = sqlite3_column_type(statement, 11) != SQLITE_NULL ? 
                        Double(sqlite3_column_double(statement, 11)) : nil
                    let expDamage = sqlite3_column_type(statement, 12) != SQLITE_NULL ? 
                        Double(sqlite3_column_double(statement, 12)) : nil
                    
                    return DatabaseItem(
                        id: Int(sqlite3_column_int(statement, 0)),
                        typeID: Int(sqlite3_column_int(statement, 0)),
                        name: String(cString: sqlite3_column_text(statement, 1)),
                        iconFileName: String(cString: sqlite3_column_text(statement, 2)).isEmpty ? 
                            DatabaseConfig.defaultItemIcon : String(cString: sqlite3_column_text(statement, 2)),
                        categoryID: Int(sqlite3_column_int(statement, 7)),
                        pgNeed: Int(sqlite3_column_int(statement, 3)),
                        cpuNeed: Int(sqlite3_column_int(statement, 4)),
                        rigCost: Int(sqlite3_column_int(statement, 8)),
                        emDamage: emDamage,
                        themDamage: themDamage,
                        kinDamage: kinDamage,
                        expDamage: expDamage,
                        highSlot: Int(sqlite3_column_int(statement, 13)),
                        midSlot: Int(sqlite3_column_int(statement, 14)),
                        lowSlot: Int(sqlite3_column_int(statement, 15)),
                        rigSlot: Int(sqlite3_column_int(statement, 16)),
                        gunSlot: Int(sqlite3_column_int(statement, 17)),
                        missSlot: Int(sqlite3_column_int(statement, 18)),
                        metaGroupID: Int(sqlite3_column_int(statement, 5)),
                        published: sqlite3_column_int(statement, 6) != 0
                    )
                }
            )

            for item in results {
                if item.published {
                    publishedItems.append(item)
                } else {
                    unpublishedItems.append(item)
                }
                loadMetaGroupName(for: item.metaGroupID, db: db, metaGroupNames: &metaGroupNames)
            }
            
            return (publishedItems, unpublishedItems, metaGroupNames)
        }
        
        static func loadItemDetails(for itemID: Int, db: OpaquePointer?) -> ItemDetails? {
            guard let db = db else { return nil }

            let query = """
            SELECT name, description, icon_filename, group_name, category_name 
            FROM types 
            WHERE type_id = ? 
            ORDER BY metaGroupID
            """

            let results: [ItemDetails] = executeQuery(
                db: db,
                query: query, bindParams: [itemID],
                bind: { statement in
                    sqlite3_bind_int(statement, 1, Int32(itemID))
                },
                resultProcessor: { statement in
                    let name = String(cString: sqlite3_column_text(statement, 0))
                    let description = String(cString: sqlite3_column_text(statement, 1))
                    let iconFileName = String(cString: sqlite3_column_text(statement, 2))
                    let groupName = String(cString: sqlite3_column_text(statement, 3))
                    let categoryName = String(cString: sqlite3_column_text(statement, 4))
                    
                    let finalIconFileName = iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    
                    return ItemDetails(
                        name: name,
                        description: description,
                        iconFileName: finalIconFileName,
                        groupName: groupName,
                        categoryName: categoryName
                    )
                }
            )

            return results.first
        }
        
        private static func loadMetaGroupName(for metaGroupID: Int, db: OpaquePointer, metaGroupNames: inout [Int: String]) {
            let query = "SELECT name FROM metaGroups WHERE metaGroup_id = ?"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(metaGroupID))
                if sqlite3_step(statement) == SQLITE_ROW, let name = sqlite3_column_text(statement, 0) {
                    metaGroupNames[metaGroupID] = String(cString: name)
                }
                sqlite3_finalize(statement)
            }
        }
    }
    
    // MARK: - Shared Query Functions
    private static func executeQuery<T>(
        db: OpaquePointer,
        query: String,
        bindParams: [Any],
        bind: ((OpaquePointer) -> Void)?,
        resultProcessor: (OpaquePointer) -> T
    ) -> [T] {
        var results: [T] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            bind?(statement!)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(resultProcessor(statement!))
            }
            
            sqlite3_finalize(statement)
        }
        
        return results
    }
} 
