# EVE Nexus

[中文](Readme.md) | [English](Readme.en.md)

# 开发进度

[查看资料..](inDev.md)

# Xcode

使用 Xcode Version 16.2 编译

# 第三方依赖

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **Kingfisher**: https://github.com/onevcat/Kingfisher
- **Zip**: https://github.com/marmelroy/Zip

# 格式化

```bash
cd "EVE Nexus" && $(xcrun --find swift-format) -r . -i --configuration .swift-format.json
```

# 扫描未被使用的函数

```bash
periphery scan | grep -v "/Thirdparty/" > log.txt
```

```regexp
(Enum|Property|Function|Initializer).*is unused
```

# 获取应用 / Get App

iOS / iPadOS / macOS: [Tritanium on the App Store](https://apps.apple.com/us/app/tritanium/id6739530875)

# 功能

## 角色（Character）

- **角色公共信息**：查看头像、所属公司、联盟、头衔、安全状态和出生日期  
- **角色个人信息**：查看当前位置、当前舰船和跳跃疲劳状态

## 技能（Skills）

- 查看当前技能队列和剩余时间  
- 查看所有技能状态和角色属性点  
- 计算技能队列所需的注入器数量  
- 优化角色属性点分配

## 克隆（Clones）

- 查看主克隆所在站点  
- 查看上次克隆跳跃时间与上次站点变更  
- 查看所有克隆状态和当前植入体信息

## 邮件（Mail）

- 查看、发送和接收邮件

## 个人资产估值（Personal Asset Valuation）

- 查看植入体、市场订单、资产和钱包余额  
- 查看最高价值资产

## 忠诚点（Loyalty Points）

- 查看当前忠诚点  
- 查看 NPC 公司忠诚点兑换表

## 搜索（Search）

- 查看角色名称、就业历史和声望  
- 查看公司名称、描述和声望  
- 查看联盟名称

## 静态数据库（Static Database）

- 查看所有游戏内物品的名称、描述和属性

## 市场（Market）

- 查看物品价格、买卖订单和历史市场数据

## 市场关注列表（Market Watchlist）

- 标记关注物品  
- 设置物品数量并计算总价值

## 比较工具（Comparison Tool）

- 查看并比较选定物品之间的属性差异

## NPC 舰船（NPCs）

- 查看游戏内 NPC 舰船的属性信息

## 代理人（Agents）

- 查看代理人信息：名称、位置、等级、部门、所属公司或阵营

## 虫洞（Wormholes）

- 查看虫洞入口信息

## 入侵（Incursions）

- 查看当前 Sansha 入侵位置和进展情况

## 主权战役（Sovereignty Campaigns）

- 查看当前主权战争位置和进展

## 语言参考（Language Reference）

- 查看物品、星系、NPC 公司的多语言名称

## 旗舰跳跃导航（Capital Ship Jump Navigation）

- 计算从起始点到多个航点的旗舰跳跃路径

## 个人资产（Personal Assets）

- 查看当前角色的资产清单及其位置

## 市场订单（Market Orders）

- 查看当前角色的市场订单信息

## 合同（Contracts）

- 查看个人与公司合同  
- 估算价格，按合同类型筛选  
- 启用快递模式，并按起点/终点对快递合同进行分组

## 交易记录（Transaction History）

- 查看角色每日购买记录

## 钱包流水（Wallet Journal）

- 查看角色每日钱包交易记录

## 工业生产（Industry Jobs）

- 查看角色的工业生产任务记录

## 采矿记录（Mining Records）

- 查看角色的月度采矿活动数据

## 行星开发（Planetary Interaction）

- 查看行星开发状态，包括仓库库存、开采器和工厂加工情况

## 行星开发计算器（Planetary Interaction Calculator）

- 根据星系、产品和主权状态计算最优生产位置  
- 根据区域估算可用产品

## 公司账户（Corporation Accounts）

- 查看公司各部门的钱包余额、交易记录和转账记录

## 公司成员（Corporation Members）

- 查看公司成员列表和角色所在位置

## 公司月矿开采（Corporation Moon Mining）

- 查看公司月矿开采状态、牵引光束剩余时间和月岩剩余时间

## 公司建筑物（Corporation Structures）

- 查看建筑物加固状态和燃料状况

## 战斗记录（Combat Records）

- 查看角色的 zKillboard 战绩并搜索击毁记录

## ESI 接口状态（ESI Status）

- 查看各类 ESI 接口运行状态

## 派系战争（Factional Warfare）

- 查看派系战争相关信息

# 画廊

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

# 开源协议 / Open Source License

本项目代码仅供查看，**禁止修改、商用、二次分发**。  
适用许可证：**CC BY-NC-ND 4.0**  
详情查看 [LICENSE](LICENSE) 文件或访问：[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)

This project's code is for viewing only. **Modification, commercial use, and redistribution are prohibited.**  
License: **CC BY-NC-ND 4.0**  
For details, view the [LICENSE](LICENSE) file or visit: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/).
