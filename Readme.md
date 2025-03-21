# Xcode

Open Project with Xcode Version 16.2.

# 3rd

Third party plugin from:

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **Kingfisher**: https://github.com/onevcat/Kingfisher
- **Zip**: https://github.com/marmelroy/Zip

# format

```bash
cd "EVE Nexus" && $(xcrun --find swift-format) -r . -i --configuration .swift-format.json
```

# hint

1. 通过 `withAnimation` 来添加一些动画
2. 通过在view的init阶段加载数据来避免重复加载
3. 批量插入sql，参考 `MarketPricesAPI.swift` 的 `saveToDatabase`

# 获取应用 / Get App

iOS/iPadOS: [Tritanium on the App Store](https://apps.apple.com/us/app/tritanium/id6739530875)

# 开源协议 / Open Source License

本项目代码仅供查看，**禁止修改、商用、二次分发**。  
适用许可证：**CC BY-NC-ND 4.0**  
详情查看 [LICENSE](LICENSE) 文件或访问：[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)

This project's code is for viewing only. **Modification, commercial use, and redistribution are prohibited.**  
License: **CC BY-NC-ND 4.0**  
For details, view the [LICENSE](LICENSE) file or visit: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/).
