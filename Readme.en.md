# EVE Nexus

[中文](Readme.md) | [English](Readme.en.md)

# Xcode

Compiled with Xcode Version 16.2

# Third-party Dependencies

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **Kingfisher**: https://github.com/onevcat/Kingfisher
- **Zip**: https://github.com/marmelroy/Zip

# Formatting

```bash
cd "EVE Nexus" && $(xcrun --find swift-format) -r . -i --configuration .swift-format.json
```

# Scan Unused Functions

```bash
periphery scan | grep -v "/Thirdparty/" > log.txt
```

# Get App

iOS / iPadOS / macOS: [Tritanium on the App Store](https://apps.apple.com/us/app/tritanium/id6739530875)

# Features

- View character public information: avatar, corporation, alliance, title, security status, birth date
- View character personal information: current location, current ship, jump fatigue
- Skills: current character skill queue and remaining time, all skill statuses, character attribute points, calculate required injectors for queue, calculate optimal attribute points
- Clones: view home station, last clone jump time, last station change, all clone statuses, current implants
- Mail: view, send and receive mail
- Personal asset valuation: implants, orders, assets, wallet balance, view some highest-value assets
- Loyalty points: view current loyalty points, view LP exchange tables for NPC corporations
- Search: search character names, view character employment history, view character standings, search corporation names, view corporation descriptions and standings, search alliance names
- Static database: view names, descriptions, and attributes of all in-game items
- Market: view item market prices, buy/sell orders, historical prices
- Market watch list: mark a series of items, set item quantities, and calculate their total value
- Comparison tool: compare attribute differences between series of items
- NPCs: view attributes of in-game NPC ships
- Agents: search for agent information from various factions and corporations, including: name, location, level, department, etc.
- Wormholes: view wormhole entrance information
- Incursions: view current Sansha incursion locations and progress
- Sovereignty campaigns: view current sovereignty activity locations and progress
- Language reference: search for items, star systems, NPC corporations, etc., and display text in other languages
- Capital ship jump navigation: calculate jump navigation paths from specified starting point to a series of waypoints
- Personal assets: view current character's asset list and locations
- Market orders: view current character's market order information
- Contract list: view current character's and corporation's contract list, estimate contract prices, filter specified contract types, provide courier mode, group courier contracts by origin/destination
- Transaction history: display character's purchase records by day
- Wallet journal: display character's wallet transaction records by day
- Industry jobs: display character's industrial production records
- Mining records: display character's mining records by month
- Planetary interaction: view current character's planetary development status, warehouse inventory status, extractor status, factory processing status, etc.
- Planetary interaction calculator: calculate the most suitable production locations based on specified star systems, products, and sovereignty. Also calculate available products based on specified regions.
- Corporation accounts: view corporation department wallet balances, transaction records, and transfer records
- Corporation members: view corporation member list and character locations
- Corporation moon mining: view corporation moon mining status, remaining tractor time, and remaining moon chunk time
- Corporation structures: view corporation structure reinforcement status and fuel status
- Combat records: view current character's zkillboard list, search any killboard
- ESI status: view health of various ESI interfaces

# Open Source License

This project's code is for viewing only. **Modification, commercial use, and redistribution are prohibited.**  
License: **CC BY-NC-ND 4.0**  
For details, view the [LICENSE](LICENSE) file or visit: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/). 