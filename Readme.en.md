# EVE Nexus

[中文](Readme.md) | [English](Readme.en.md)

# Xcode

Compiled with Xcode Version 16.2

# Third-party Dependencies

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **JWTDecode**: https://github.com/auth0/JWTDecode.swift
- **Zip**: https://github.com/marmelroy/Zip
- **Pulse**: https://github.com/kean/Pulse

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
