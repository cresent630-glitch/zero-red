# zero red

极简黑白 iPhone 浏览器项目。包含原生 iOS 工程、可操作的网页预览、测试及功能文档。不包含跨设备同步。

**当前状态：开发中的 0.2 版。已在 Xcode 27 / iOS 27 模拟器完成 Debug 编译和 15 项界面测试；真机验收仍待完成。**

## 项目入口

| 内容 | 路径 |
| --- | --- |
| 原生 iPhone App | `apps/ios/ZeroRed.xcodeproj` |
| Swift 跨平台测试 | `apps/ios/Package.swift` |
| 网页预览源码 | `apps/web/dist/` |
| 功能覆盖及待验收项 | `docs/FEATURE_MATRIX.md` |
| 测试报告 | `docs/TEST_REPORT.md` |
| 项目需求 | `docs/PRODUCT.md` |
| 后续开发清单 | `docs/ROADMAP.md` |
| 云 Mac 连接与测试 | `docs/CLOUD_MAC.md` |
| macOS CI | `.github/workflows/ios.yml` |

在线预览：https://zero-red-preview.alpinefoam3.chatgpt.site

## 开发

原生 App：在 Mac 的 Xcode 中打开 `apps/ios/ZeroRed.xcodeproj`，选择 iPhone 模拟器。Xcode 会解析固定版本 ZIPFoundation 0.9.19。真机运行需要自己的签名 Team 和唯一 Bundle ID。

网页：进入 `apps/web`。部署输出为 `dist/`，是无需构建的静态页面；托管站点标识保留在 `.openai/hosting.json` 中。当前正式预览继续由原有 Sites 源仓库管理，本项目是统一的开发交付快照；在切换托管源前，不要把两处源码当作自动同步。

## 测试

```sh
# 需要 Swift 6+ 和 Python 3
cd apps/ios
bash scripts/test-core.sh

# 仅 Mac / Xcode；先查询已安装的 iPhone Simulator UDID
IOS_SIMULATOR_ID='<UDID>' bash scripts/test-ios.sh

# 网页单元测试：回到项目根目录后
cd apps/web
npm install
npm test
```

已记录的验证结果为 54 项 Swift 核心测试、73 项网页单元测试通过；2026-11-07 在云 Mac 上重新通过 54 项核心测试及 15 项 iOS 27 模拟器界面测试。完整记录见 `docs/TEST_REPORT.md`。这些结果不等于真机、全部网站兼容性或全部 Apple 系统功能验收通过。默认浏览器资格仍需 Apple 授权。

工程包含 GitHub Actions 配置。推送到 GitHub 的 `main` 分支后会自动运行 iOS 验证，也可在 Actions 中手动触发。云 Mac 验证记录与 GitHub Actions 的实际运行结果分别查看。
