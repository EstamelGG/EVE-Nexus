import Foundation
import SQLite3

/// 在只读 SDE 上创建 TEMP VIEW，将多语言列别名为 name / group_name 等
enum SDELocalization {
    static func apply(to db: OpaquePointer, languageCode: String? = nil) -> Bool {
        let lang = SDELanguage.columnPrefix(from: languageCode)
        let statements = buildStatements(lang: lang)
        for sql in statements {
            if !exec(db, sql) {
                Logger.error("SDE 本地化视图创建失败: \(sql.prefix(120))...")
                return false
            }
        }
        Logger.info("SDE 本地化 TEMP VIEW 已应用，语言前缀: \(lang)")
        return true
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            Logger.error("sqlite3_exec 失败 (\(rc)): \(msg)")
            return false
        }
        return true
    }

    private static func buildStatements(lang: String) -> [String] {
        return [
            drop("types"),
            """
            CREATE TEMP VIEW types AS
            SELECT t.*,
                   t.\(lang)_name AS name,
                   t.\(lang)_desc_id AS desc_id,
                   '' AS description,
                   t.group_\(lang)_name AS group_name,
                   t.category_\(lang)_name AS category_name,
                   char(31) || COALESCE(t.de_name, '') || char(31) ||
                   COALESCE(t.en_name, '') || char(31) ||
                   COALESCE(t.es_name, '') || char(31) ||
                   COALESCE(t.fr_name, '') || char(31) ||
                   COALESCE(t.ja_name, '') || char(31) ||
                   COALESCE(t.ko_name, '') || char(31) ||
                   COALESCE(t.ru_name, '') || char(31) ||
                   COALESCE(t.zh_name, '') || char(31) AS name_search
            FROM main.types t
            """,

            drop("categories"),
            """
            CREATE TEMP VIEW categories AS
            SELECT c.*, c.\(lang)_name AS name
            FROM main.categories c
            """,

            drop("groups"),
            """
            CREATE TEMP VIEW groups AS
            SELECT g.*, g.\(lang)_name AS name
            FROM main.groups g
            """,

            drop("marketGroups"),
            """
            CREATE TEMP VIEW marketGroups AS
            SELECT m.*, m.\(lang)_name AS name
            FROM main.marketGroups m
            """,

            drop("metaGroups"),
            """
            CREATE TEMP VIEW metaGroups AS
            SELECT m.*, m.\(lang)_name AS name
            FROM main.metaGroups m
            """,

            drop("factions"),
            """
            CREATE TEMP VIEW factions AS
            SELECT f.*,
                   f.\(lang)_name AS name,
                   f.\(lang)_description AS description,
                   f.\(lang)_short_description AS shortDescription
            FROM main.factions f
            """,

            drop("npcCorporations"),
            """
            CREATE TEMP VIEW npcCorporations AS
            SELECT n.*,
                   n.\(lang)_name AS name,
                   n.\(lang)_description AS description
            FROM main.npcCorporations n
            """,

            drop("wormholes"),
            """
            CREATE TEMP VIEW wormholes AS
            SELECT w.*,
                   w.\(lang)_name AS name,
                   w.\(lang)_description AS description
            FROM main.wormholes w
            """,

            drop("traits"),
            """
            CREATE TEMP VIEW traits AS
            SELECT typeid, skill, importance, bonus_type,
                   \(lang)_content AS content,
                   de_content, en_content, es_content, fr_content,
                   ja_content, ko_content, ru_content, zh_content
            FROM main.traits
            """,

            drop("dogmaAttributeCategories"),
            """
            CREATE TEMP VIEW dogmaAttributeCategories AS
            SELECT d.*,
                   d.\(lang)_name AS name,
                   d.\(lang)_description AS description
            FROM main.dogmaAttributeCategories d
            """,

            drop("dogmaAttributes"),
            """
            CREATE TEMP VIEW dogmaAttributes AS
            SELECT d.*,
                   d.attribute_key AS name,
                   d.\(lang)_name AS display_name,
                   d.\(lang)_tooltip_description AS tooltipDescription,
                   d.unit_\(lang)_name AS unitName
            FROM main.dogmaAttributes d
            """,

            drop("dogmaEffects"),
            """
            CREATE TEMP VIEW dogmaEffects AS
            SELECT e.*,
                   e.\(lang)_name AS display_name,
                   e.\(lang)_name AS name,
                   e.\(lang)_description AS description
            FROM main.dogmaEffects e
            """,

            drop("agents"),
            """
            CREATE TEMP VIEW agents AS
            SELECT a.*,
                   a.\(lang)_name AS name,
                   a.\(lang)_name AS agent_name
            FROM main.agents a
            """,

            drop("divisions"),
            """
            CREATE TEMP VIEW divisions AS
            SELECT d.*, d.\(lang)_name AS name
            FROM main.divisions d
            """,

            drop("planetSchematics"),
            """
            CREATE TEMP VIEW planetSchematics AS
            SELECT p.*, p.\(lang)_name AS name
            FROM main.planetSchematics p
            """,

            drop("typeMaterials"),
            """
            CREATE TEMP VIEW typeMaterials AS
            SELECT t.*, t.output_material_\(lang)_name AS output_material_name
            FROM main.typeMaterials t
            """,

            drop("typeSkillRequirement"),
            """
            CREATE TEMP VIEW typeSkillRequirement AS
            SELECT r.*,
                   r.type_\(lang)_name AS typename,
                   r.category_\(lang)_name AS category_name
            FROM main.typeSkillRequirement r
            """,

            drop("regions"),
            """
            CREATE TEMP VIEW regions AS
            SELECT r.*,
                   r.\(lang)_name AS regionName,
                   r.de_name AS regionName_de,
                   r.en_name AS regionName_en,
                   r.es_name AS regionName_es,
                   r.fr_name AS regionName_fr,
                   r.ja_name AS regionName_ja,
                   r.ko_name AS regionName_ko,
                   r.ru_name AS regionName_ru,
                   r.zh_name AS regionName_zh
            FROM main.regions r
            """,

            drop("solarsystems"),
            """
            CREATE TEMP VIEW solarsystems AS
            SELECT s.*,
                   s.\(lang)_name AS solarSystemName,
                   s.de_name AS solarSystemName_de,
                   s.en_name AS solarSystemName_en,
                   s.es_name AS solarSystemName_es,
                   s.fr_name AS solarSystemName_fr,
                   s.ja_name AS solarSystemName_ja,
                   s.ko_name AS solarSystemName_ko,
                   s.ru_name AS solarSystemName_ru,
                   s.zh_name AS solarSystemName_zh,
                   s.security_status AS system_security
            FROM main.solarsystems s
            """,

            drop("constellations"),
            """
            CREATE TEMP VIEW constellations AS
            SELECT c.*,
                   c.\(lang)_name AS constellationName,
                   c.de_name AS constellationName_de,
                   c.en_name AS constellationName_en,
                   c.es_name AS constellationName_es,
                   c.fr_name AS constellationName_fr,
                   c.ja_name AS constellationName_ja,
                   c.ko_name AS constellationName_ko,
                   c.ru_name AS constellationName_ru,
                   c.zh_name AS constellationName_zh
            FROM main.constellations c
            """,

            drop("stations"),
            """
            CREATE TEMP VIEW stations AS
            SELECT s.*, s.\(lang)_name AS stationName
            FROM main.stations s
            """,

            drop("fighterAbilities"),
            """
            CREATE TEMP VIEW fighterAbilities AS
            SELECT f.*,
                   f.\(lang)_name AS name,
                   f.\(lang)_tooltip_description AS description
            FROM main.fighterAbilities f
            """,
        ]
            + blueprintViews(lang: lang)
    }

    private static func drop(_ name: String) -> String {
        // 必须用 temp. 前缀，否则会误伤 main 上的同名表
        "DROP VIEW IF EXISTS temp.\(name)"
    }

    private static func blueprintViews(lang: String) -> [String] {
        let materialTables = [
            "blueprint_manufacturing_materials",
            "blueprint_research_material_materials",
            "blueprint_research_time_materials",
            "blueprint_copying_materials",
            "blueprint_invention_materials",
        ]
        let skillTables = [
            "blueprint_manufacturing_skills",
            "blueprint_research_material_skills",
            "blueprint_research_time_skills",
            "blueprint_copying_skills",
            "blueprint_invention_skills",
        ]
        let productTables = [
            "blueprint_manufacturing_output",
            "blueprint_invention_products",
        ]

        var stmts: [String] = []

        for table in materialTables {
            stmts.append(drop(table))
            stmts.append(
                """
                CREATE TEMP VIEW \(table) AS
                SELECT b.blueprintTypeID,
                       bt.\(lang)_name AS blueprintTypeName,
                       bt.icon_filename AS blueprintTypeIcon,
                       b.typeID,
                       t.\(lang)_name AS typeName,
                       t.icon_filename AS typeIcon,
                       b.quantity
                FROM main.\(table) b
                LEFT JOIN main.types bt ON bt.type_id = b.blueprintTypeID
                LEFT JOIN main.types t ON t.type_id = b.typeID
                """
            )
        }

        for table in skillTables {
            stmts.append(drop(table))
            stmts.append(
                """
                CREATE TEMP VIEW \(table) AS
                SELECT b.blueprintTypeID,
                       bt.\(lang)_name AS blueprintTypeName,
                       bt.icon_filename AS blueprintTypeIcon,
                       b.typeID,
                       t.\(lang)_name AS typeName,
                       t.icon_filename AS typeIcon,
                       b.level
                FROM main.\(table) b
                LEFT JOIN main.types bt ON bt.type_id = b.blueprintTypeID
                LEFT JOIN main.types t ON t.type_id = b.typeID
                """
            )
        }

        for table in productTables {
            let extra = table == "blueprint_invention_products" ? ", b.probability" : ""
            stmts.append(drop(table))
            stmts.append(
                """
                CREATE TEMP VIEW \(table) AS
                SELECT b.blueprintTypeID,
                       bt.\(lang)_name AS blueprintTypeName,
                       bt.icon_filename AS blueprintTypeIcon,
                       b.typeID,
                       t.\(lang)_name AS typeName,
                       t.icon_filename AS typeIcon,
                       b.quantity\(extra)
                FROM main.\(table) b
                LEFT JOIN main.types bt ON bt.type_id = b.blueprintTypeID
                LEFT JOIN main.types t ON t.type_id = b.typeID
                """
            )
        }

        stmts.append(drop("blueprint_process_time"))
        stmts.append(
            """
            CREATE TEMP VIEW blueprint_process_time AS
            SELECT b.*,
                   t.\(lang)_name AS blueprintTypeName,
                   t.icon_filename AS blueprintTypeIcon
            FROM main.blueprint_process_time b
            LEFT JOIN main.types t ON t.type_id = b.blueprintTypeID
            """
        )

        return stmts
    }
}
