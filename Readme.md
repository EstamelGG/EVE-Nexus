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

- 查看人物公共信息：头像、军团、联盟、title、安全等级 、出生日期
- 查看人物个人信息：当前位置、当前飞船、跳跃疲劳
- 技能：当前人物技能队列与剩余时间、人物所有技能状态、人物属性点、计算队列所需注射器个数、计算最佳属性点
- 克隆体：查看基地空间站、最后一次克隆跳跃时间、最后一次空间站变更、所有克隆体状态、当前植入体
- 邮件：查看、收发邮件
- 个人财产估价：植入体、订单、资产、钱包余额，查看最高价的一些资产
- 忠诚点：查看当前已有忠诚点，查看各NPC军团的LP点兑换表
- 搜索：搜索人物名称、查看人物雇佣记录、查看人物声望、搜索军团名称、查看军团描述与声望、搜索联盟名称
- 静态数据库：查看游戏内所有物品的名称、描述、属性
- 市场：查看物品的市场价格、买卖订单、历史价格
- 市场关注列表：标记一系列物品，允许设置物品数量，并计算其总价值。
- 对比工具：对比一系列物品的属性差异
- NPC：查看游戏内NPC飞船的属性
- 代理人：搜索各势力、军团的代理人信息，包括：名称、位置、等级、部门等
- 虫洞：查看虫洞洞口的信息
- 入侵：查看当前正进行中的萨沙入侵位置与进度
- 主权争夺：查看当前正进行中的主权活动位置与进度
- 语言对照：搜索物品、星系、NPC军团等名称，展示其他语言的文本
- 旗舰跳跃导航：计算从指定起点到一系列路径点的跳跃导航路径
- 个人资产：查看当前人物的资产清单、位置
- 市场订单：查看当前人物的市场订单信息
- 合同列表：查看当前人物与所属军团的合同列表，并能够估计合同价格，过滤指定类型的合同，提供快递模式，针对快递类合同按起止地进行合并分组
- 交易记录：按天展示人物购物的记录
- 钱包日志：按天展示人物的钱包变动记录
- 工业任务：展示人物的工业生产记录
- 采矿记录：按月展示人物的采矿记录
- 行星开发：查看当前人物的行星开发状态、仓库库存状态、采集器状态、工厂加工状态等
- 行星开发计算器：根据指定星系、产品、主权，计算最合适的产地。以及根据指定地区，计算可用的产品。
- 军团账户：查看军团各部门的钱包余额与交易记录、转账记录
- 军团成员：查看军团成员列表与人物位置
- 军团月矿作业：查看军团月矿的状态，牵引剩余时间与月矿破碎的剩余时间
- 军团建筑：查看军团建筑的增强状态、燃料状态
- 战斗记录：查看当前人物的zkb列表、搜索任意kb
- ESI状态：查看esi各接口的健康度

# 开源协议 / Open Source License

本项目代码仅供查看，**禁止修改、商用、二次分发**。  
适用许可证：**CC BY-NC-ND 4.0**  
详情查看 [LICENSE](LICENSE) 文件或访问：[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)

This project's code is for viewing only. **Modification, commercial use, and redistribution are prohibited.**  
License: **CC BY-NC-ND 4.0**  
For details, view the [LICENSE](LICENSE) file or visit: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/).
