# zero red

极简黑白 iPhone 浏览器项目。包含原生 iOS 工程、可操作的网页预览、测试及功能文档。不包含跨设备同步。

**当前状态：开发中的 0.2 版（构建 4）。界面已改为 iOS 27 原生样式 + Liquid Glass；云编译、54 项核心测试与模拟器 Release 通过，真机验收仍待完成。**

## 项目入口

| 内容 | 路径 |
| --- | --- |
| 原生 iPhone App | `apps/ios/ZeroRed.xcodeproj` |
| Swift 跨平台测试 | `apps/ios/Package.swift` |
| 网页预览源码 | `apps/web/dist/` |
| 功能覆盖及待验收项 | `docs/FEATURE_MATRIX.md` |
| 测试报告 | `docs/TEST_REPORT.md` |
| 项目需求 | `docs/PRODUCT.md` |
| 界面设计与 Liquid Glass 规范 | `docs/UI_DESIGN.md` |
| 后续开发清单 | `docs/ROADMAP.md` |
| 云编译与交付流程 | `docs/DEV_TO_DELIVERY.md` |
| GitHub Actions 说明 | `docs/GITHUB_ACTIONS_BUILD.md` |
| 云 Mac 连接与测试（历史） | `docs/CLOUD_MAC.md` |
| 云编译工作流 | `.github/workflows/ios-cloud-build.yml` |
| 网页测试工作流 | `.github/workflows/web-tests.yml` |
| 开发约定（给人或 AI 会话） | `AGENTS.md` |

在线预览：https://zero-red-preview.alpinefoam3.chatgpt.site

## 开发

原生 App：在 Mac 的 Xcode 中打开 `apps/ios/ZeroRed.xcodeproj`，选择 iPhone 模拟器。Xcode 会解析固定版本 ZIPFoundation 0.9.19。真机运行需要自己的签名 Team 和唯一 Bundle ID。

网页：进入 `apps/web`。部署输出为 `dist/`，是无需构建的静态页面；托管站点标识保留在 `.openai/hosting.json` 中。当前正式预览继续由原有 Sites 源仓库管理，本项目是统一的开发交付快照；在切换托管源前，不要把两处源码当作自动同步。

## 云编译与交付

Windows 本机不安装 Xcode：iOS 编译、Swift 核心测试和真机 IPA 打包都跑在 GitHub 托管的 macOS 运行器（`xcode-27`，Xcode 27 + iOS 27 模拟器）上，仓库为标准托管运行器免费额度。完整流程见 [DEV_TO_DELIVERY](docs/DEV_TO_DELIVERY.md)，工作流输入与产物见 [GITHUB_ACTIONS_BUILD](docs/GITHUB_ACTIONS_BUILD.md)。

- 双击 **`一键交付.cmd`**：本地预检 → 推送 → 按当前提交触发云构建 → 逐项读取步骤结论 → 下载并校验 IPA → 更新 `build/ios-device` → 写交付收据 `build/reviews/delivery-*.json`。
- 双击 **`更新真机安装包.cmd`**：手动从 Releases 下载 `ZeroRed-ipa.zip` 后，导入其中 `ipa` 文件夹。
- 双击 **`安装到iPhone.cmd`**：校验安装包后打开 Sideloadly 签名安装。

云构建产物发布在本仓库 Releases，标签 `build-<运行ID>-<尝试>`，含未签名 IPA 与构建日志。工作流只手动触发，构建的就是推送后的那个提交。

## 测试

当前版本的用户验收入口：[项目专用测试用例](docs/ZERO_RED_TEST_CASES.md)；环境、数据和执行批次见 [测试执行准备](docs/ZERO_RED_TEST_EXECUTION.md)。在项目根运行 `python apps/ios/scripts/prepare_qa.py --run-local` 可生成本轮源码清单、待执行登记表、导入样本和本机自检日志。准备检查不代表 iPhone 验收通过。

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

工程包含 GitHub Actions 配置：`ios-cloud-build.yml` 手动触发，在 macOS 运行器上跑核心测试、模拟器 Release 与真机 IPA 打包，并把产物发布到本仓库 Releases；`web-tests.yml` 在 `apps/web` 变更时自动跑网页单元测试。云 Mac 时代的验证记录与 GitHub Actions 的实际运行结果分开查看，不要互相替代。云构建成功只证明编译与核心测试通过，不等于真机安装、视觉验收或默认浏览器资格已完成。
