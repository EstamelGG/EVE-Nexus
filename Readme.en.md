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

## Character

- **Character Public Information**: View avatar, corporation, alliance, title, security status, and birth date.  
- **Character Personal Information**: View current location, current ship, and jump fatigue.

## Skills

- View current skill queue and remaining time.  
- View all skill statuses and character attributes.  
- Calculate required injectors for the queue.  
- Optimize attribute points.

## Clones

- View home station.  
- View last clone jump time and last station change.  
- View all clone statuses and current implants.

## Mail

- View, send, and receive mail.

## Personal Asset Valuation

- View implants, market orders, assets, and wallet balance.  
- View highest-value assets.

## Loyalty Points

- View current loyalty points.  
- View LP exchange tables for NPC corporations.

## Search

- View character names, employment history, and standings.  
- View corporation names, descriptions, and standings.  
- View alliance names.

## Static Database

- View names, descriptions, and attributes of all in-game items.

## Market

- View item prices, buy/sell orders, and historical market data.

## Market Watchlist

- View marked items.  
- Set item quantities and calculate total value.

## Comparison Tool

- View and compare attribute differences between selected items.

## NPCs

- View attributes of in-game NPC ships.

## Agents

- View agent information: name, location, level, department, affiliated corporation or faction.

## Wormholes

- View wormhole entrance information.

## Incursions

- View current Sansha incursion locations and progress.

## Sovereignty Campaigns

- View active sovereignty conflict locations and progress.

## Language Reference

- View localized names of items, star systems, NPC corporations, etc.

## Capital Ship Jump Navigation

- View and calculate jump routes from a starting point to multiple waypoints.

## Personal Assets

- View the current character’s assets and their locations.

## Market Orders

- View current market orders of the character.

## Contracts

- View personal and corporate contracts.  
- Estimate prices and filter by contract type.  
- Enable courier mode and group courier contracts by origin/destination.

## Transaction History

- View character purchase records by day.

## Wallet Journal

- View wallet transaction records by day.

## Industry Jobs

- View character’s industrial job records.

## Mining Records

- View monthly mining statistics.

## Planetary Interaction

- View development status including warehouse inventory, extractors, and factory operations.

## Planetary Interaction Calculator

- View optimal production locations based on star systems, products, and sovereignty.  
- View available products by region.

## Corporation Accounts

- View corporate division wallet balances, transaction records, and transfers.

## Corporation Members

- View member list and character locations.

## Corporation Moon Mining

- View moon mining status, tractor beam remaining time, and moon chunk timer.

## Corporation Structures

- View structure reinforcement status and fuel levels.

## Combat Records

- View character’s zKillboard records and search killboards.

## ESI Status

- View the operational health of ESI interfaces.

## Factional Warfare

- View factional warfare information.

# Screenshots

![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.28.26.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.28.26.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.28.38.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.28.38.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.38.39.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.38.39.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.39.21.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.39.21.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.40.36.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.40.36.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.41.43.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.41.43.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.42.02.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.42.02.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.42.07.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.42.07.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.43.57.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.43.57.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.44.05.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.44.05.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-10 at 23.44.25.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.44.25.png)
![Simulator Screenshot - iPhone 16 Pro Max - 2025-05-11 at 00.27.48.png](gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-11%20at%2000.27.48.png)


# Open Source License

This project's code is for viewing only. **Modification, commercial use, and redistribution are prohibited.**  
License: **CC BY-NC-ND 4.0**  
For details, view the [LICENSE](LICENSE) file or visit: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/). 