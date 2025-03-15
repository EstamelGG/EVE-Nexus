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