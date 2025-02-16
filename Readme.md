# 准备依赖

下载依赖，解压（也可以直接导入Thirdparty中的目录）：
- https://github.com/marmelroy/Zip

- 导入到项目中

![img.png](img/img.png)

![img.png](img/img_1.png)

![img_2.png](img/img_2.png)

# 准备数据库

通过 EveSDK 项目，将EVE SDE制作成数据库文件，以及整理好图标压缩包，将这资源放在以下位置

- 'EVE-Nexus/EVE Nexus/utils/icons_archive'
- 'EVE-Nexus/EVE Nexus/utils/SQLite'

# 编译运行

运行即可

# SDE 和 API 来源

- https://developers.eveonline.com/resource
- https://any-api.com/evetech_net/evetech_net/console
- https://images.evetech.net/alliances/xxxxxx/logo?size=128

示例:

- https://esi.evetech.net/latest/markets/10000002/orders/?type_id=17715
- https://esi.evetech.net/latest/markets/10000002/history/?type_id=17715
- https://whtype.info/
- https://esi.evetech.net/latest/incursions/?datasource=tranquility
- https://esi.evetech.net/latest/sovereignty/map/?datasource=tranquility
- https://esi.evetech.net/latest/status/?datasource=tranquility
- https://esi.evetech.net/latest/sovereignty/campaigns/?datasource=tranquility
- https://esi.evetech.net/latest/characters/xxxxxxxxx/skills/

# Todo

1. Zkillboard接入(Done)
2. 行星开发
3. 装配模拟
4. 技能属性计算与注射器计算(Done)
5. 技能Plan无法获取，esi没有提供有关信息(Done)
6. LP计算可以进行，但只能计算参考值，意义较低
7. 挖矿统计(Done)
8. 人物信息聚合
9. 对比工具
10. 军团月矿监视(Done)