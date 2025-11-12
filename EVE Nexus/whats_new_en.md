# v1.0 February 20, 2025

Official release

# v1.1.3 March 3, 2025

1. Improved application performance
2. Enhanced PI page functionality
3. Added ESI status monitoring in settings
4. Fixed errors in skill injector quantity calculations

# v1.2 March 7, 2025

1. Fixed minor bugs
2. Added agent finder functionality
3. Updated SDE database
4. Added contract appraisal feature

# v1.2.1 March 11, 2025

1. Fixed issues caused by ESI Scopes changes
2. Improved agent finder functionality

# v1.2.3 March 13, 2025

1. Improved performance for multiple features: asset loading, historical market price charts, loading large location datasets, SQL query execution
2. Optimized agent finder UI
3. Enhanced cache clearing capabilities

# v1.2.5 March 17, 2025

1. Optimized performance through improved SQL statements and request concurrency
2. Enhanced UI styling for corp and personal wallets, improved transaction log responsiveness
3. Fixed bug of PI - now calculates correctly even when extractors expire (minor calculation differences remain)
4. Language comparator now supports TypeID searches
5. Various UI design optimizations

# v1.3 March 21, 2025

1. Added attribute comparator feature
2. Enhanced character search with filtering capabilities
3. Updated SDE database
4. Performance improvements

# v1.3.1 March 25, 2025

1. Added blueprint copy icons with detection in LP stores, blueprint invention, personal assets, and asset appraisal
2. Contract appraisal now alerts for blueprints (ESI doesn't indicate if blueprint is a copy)
3. Improved asset browser performance
4. Enhanced agent finder system/region name sorting
5. Fixed floating-point support in item attributes (e.g., module cycle time precision)
6. Prioritized ships and modules in item search results
7. Improved personal assets sorting - containers and ships with items now appear first
8. Added mutated module attribute display with source/output information
9. Enhanced language comparison with group and category searches
10. Added discount settings for contract appraisal

# v1.5 April 11, 2025

## New Features:
1. Added capital jump calculator
2. Special styling for characters with expired ESI tokens

## Localization:
1. Added station name localization
2. Added wallet journal localization
3. Added agent name localization
4. Added NPC browser UI localization

## Fixes & Optimizations:
1. Improved ESI token management and expiration detection
2. Removed unused code
3. Enhanced list sorting logic (database items now sorted by name)
4. Fixed incorrect links
5. Fixed errors from Xcode and iOS updates

# v1.5.3 April 22, 2025

## New Features:
1. Added PI calculator: a) Find optimal production systems by region and commodity, b) Find available commodities by system and range
2. Market watchlist auto-switches to selected region when viewing item orders
3. Capital jump calculator can now avoid invaded systems

## Localization:
1. Improved UI localization coverage
2. Continued wallet journal localization

## Fixes & Optimizations:
1. Fixed combat log bug - now properly categorizes kills and losses
2. Code cleanup
3. Fixed asset browser station name language switching
4. Fixed market order browser custom region UI errors and improved region selector
5. Capital jump calculator now supports high-sec starting points
6. Fixed missing dotlan link buttons in jump calculator

# v1.5.4 April 23, 2025

1. Fixed remaining bugs
2. Added sovereignty browser - view system counts by faction
3. Continued localization work
4. Separate language settings for app and database

# v1.5.5 April 24, 2025

1. Enhanced attribute comparator with rig support
2. Fixed missing attributes in comparator when items lack certain properties
3. Updated to April 22 SDE database

# v1.5.6 April 30, 2025

Improvements:

1. Added "Net Income" to wallet journal with 30/7/1 day calculation periods
2. Fixed missing CPU and powergrid attributes in database and market browsers
3. Added region names to jump calculator system selector
4. Added auxiliary functions for fitting feature
5. Fixed LP market display issues for certain factions and corporations

# v1.5.7 May 3, 2025

Fixes & Improvements:

1. Pod killmails now display slots correctly in combat records
2. Fixed agent finder bug - search results now display properly

# v1.5.8 May 7, 2025

Fixes & Improvements:

1. Updated to support local JWT validation
2. Updated SDE database with adjusted item attributes
3. Fixed asset search location issues
4. Added "Used in Blueprints" feature to item database
5. Added Faction Warfare feature to view empire war status

# v1.5.9 May 10, 2025

1. Fixed bugs in item database skill requirements and skill point formatting
2. Added "Used For" page for planetary commodities
3. Improved Faction Warfare page UI design

# v1.5.10 May 12, 2025

1. Chinese and English search support for personal assets, market orders, and transaction records
2. Wallet transaction type filtering
3. EVE Who and zKillboard links in character search with alliance information in employment history
4. Skill catalog category filtering and name search
5. Improved "Required Skills" UI in item database
6. Fixed personal wealth order display errors

# v1.5.11 May 27, 2025

1. Optimized industry and LP store loading - LP stores no longer show factions/corps without offers
2. Added contract filters
3. Skill achievement status display in item database
4. Fixed market watchlist item search issues
5. Added missing bonuses for T3C ships
6. Updated SDE

# v1.5.12 May 28, 2025

1. Fixed bug: localization errors in item group names
2. Alphabetical sorting for skill catalog and skill lists

# 1.6 June 18, 2025

1. !!!!!! Added "Fitting Simulator" feature !!!!!!
2. Updated SDE to June 5, 2025 version

# 1.6.1 June 26, 2025

1. Improved skill training progress UI with real-time display
2. Enhanced fitting UI with additional attributes: shield/armor/hull remote repair, mining yield, energy vampire/neutralizer amounts, capacitor boost
3. One-click return to market homepage in market browser
4. Fitting appraisal display
5. UI error corrections

# 1.6.2 July 7, 2025

1. Fitting page details button shows all calculated attributes for modules, ammunition, drones, fighters, and hulls
2. Fixed industry manufacturing page English localization
3. Fixed contract appraisal discount crash with large values
4. Removed unnecessary scopes
5. Significantly improved language comparison performance
6. Export fitting to game or clipboard support
7. Improved implant and booster selectors in fitting
8. Added single-planet calculator for PI 
9. Compatible with new PLEX market data format
10. Updated to latest SDE version

# 1.6.3 July 9, 2025

1. Fitting page now allows manual booster and implant selection without slot number requirements

# 1.6.4 July 15, 2025

1. Added "Update History" in settings to view all version changelogs. (reported by Cai ***)
2. Add a new site selection feature to PI function, allowing the production of one or more products in a single planet. It can identify the optimal star system under a specified sovereignty or region that meets the product requirements.
3. Added "Production Chain Analysis" feature to PI function, allowing analysis and display of processing chains for specified product
4. Fix a bug: On certain devices, the expected text copy functionality would unexpectedly fail after using the search feature. (reported by Kelly Hsueh), You can now long-press to copy content in certain sections (such as database details, solar-systems lists, email content, etc.).
5. Fix some localization issues.

# 1.6.5 July 23, 2025

1. Added a browser for NPC factions and legions, and displayed the reputation of the currently selected character.
2. The character sheet now displays the NPC faction the character belongs to, and show the rank.
3. The character searcher now displays the NPC faction the character belongs to.
4. Fix a bug that can not detect reaction jobs in Industry function.
5. Added the "Market Structure Settings" feature. You can search for and add structures in the "Settings" menu, and then use them in the Market Browser and Market Watchlist features.
6. Displaying the expiration time and completion time of contracts.
7. Show creator's and recipient's detail pages from the contract details.
8. Add refresh button for some functions. (assets, corp structures etc.)
9. Show available industry slots in Industry Jobs function.
10. Improved the KM page view and database image rendering on landscape mode and iPad.

# 1.7 Aug 4, 2025

1. Update localization string in Wallet Journal function.
2. Add calendar function to show events in the future.
3. Add corp industry function.
4. Allow add items from clipboard to Market watch list function.
5. Upgrade the "industrial jobs" function, adding support for filtering by job type, character, and solar system, as well as sorting by completion time, greatly improving usability.
6. Allow pin selected structures / stations in assets function
7. Allow hide functions user don't need in main page.
8. Update icon for reaction blueprints.
9. Add Blueprint calculator. 
10. Use local time instead of EVE time (beside server status)
11. Add star map.
12. Allow search LP Offer.

# v1.7.1 Aug 6, 2025

1. Fix Bug in Skill plan function.
2. Fix Bug in Industry Calculator when calculate EIV.

# v1.7.2 Aug 20, 2025

1. Fix a bug that can not get current skill level for blueprints.
2. Fix a bug when fetch Oauth scopes.
3. Fix a bug when navigate in market function.
4. Add refinery calculator.
5. Some tiny fixes.

# v1.7.3 Aug 25, 2025

1. Fix error in bp calculator when calculating job cost.
2. Fix error in fitting simulation function when calculating the bonus of implants.

# v1.7.4 Sep 4, 2025

1. Able to show fitting and killmail from in-game mail.

# v1.7.5 Sep 17, 2025

1. Fix time zone of contracts.
2. Able to convert fitting to image.
3. Note: Still waitting for update of official SDE.

# v1.8 Sep 28, 2025

1. Update to the latest SDE.
2. Adaptation for iOS 26
3. Fixed errors related to capacitor simulation and subsystem issues in the fitting simulation and fitting export functions.
4. Add DPS and DPH attributes for NPC.
5. Some UI improvements. 

# v1.8.1 Oct 17, 2025

1. Update to the latest SDE.
2. Support manual updates for SDE.
3. Optimize the LP store update logic to prevent incomplete data.
4. Fixed an issue where the latest market order data would not display immediately.
5. Some UI improvements.
6. Update the schema of insurgency api in faction war.
7. Enhance the “People & Locations” feature to enable navigate to the detail pages of a person’s corp or alliance. Also, refine the employment history feature so that a person’s faction is determined based on the end date of each employment record.

# v1.8.2 Nov 3, 2025

1. Fixed a bug in the asset feature that prevented the page from loading due to an incorrect container name.
2. Corrected the valuation error in the ore refining calculator.
3. Added support for custom skill queues in the "Skill Plans" feature.
4. Added an RSS-based EVE Online outage monitoring feature.
5. Optimized the “Market Watchlist” import function to support more formats.
6. Add insurance data for ships in database function. 
7. Fixed a bug in the "Skill Plans" feature that caused certain queues to be unremovable.

# v1.8.3 Nov 7, 2025

1. Switch LP Store data to local storage; online loading is no longer required.
2. Highlight the "Militia corp" in the LP Store list.
3. Design a more native "image downloader" to reduce third-party dependencies.
4. Fix a bug when update sde.

# v1.8.4 Nov 11, 2025

1. Support the latest ESI health data interface.
2. Optimize planetary industry calculation logic and parts of the UI design.
3. Provide future-time data simulation for planetary industry, and enable viewing of storage facility inventory change charts.
4. Allow renaming of the skill list, market watchlist, and attribute comparison list (how did I only think of this now?).

# v1.8.5 Nov 13, 2025

1. Resolved a performance issue in Pulse caused by excessive logging from the planetary development feature."