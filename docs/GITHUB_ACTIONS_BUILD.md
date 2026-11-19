# GitHub 云编译（zero red）

本项目只有**一个公开仓库** `cresent630-glitch/zero-red`。iOS 编译、Swift 核心测试和真机 IPA 打包都在 GitHub 托管的 macOS 运行器上执行，Windows 本机不安装 Xcode，也不需要 Mac 或 Tailscale。

公开仓库使用标准 GitHub-hosted 运行器，不收计算分钟费（私有仓库、存储和超额用量另有规则）。公开的代价是**源码、编译日志和产物对所有人可见**；因此不得提交密钥、个人照片、真实浏览记录或 Apple 账户信息。

## 工作流

| 文件 | 作用 | 运行器 | 触发 |
| --- | --- | --- | --- |
| `.github/workflows/ios-cloud-build.yml` | 核心测试 → 可选界面测试 → 模拟器 Release/静态分析 → 未签名真机 IPA → 发布 Release | `xcode-27`（GitHub 托管，Xcode 27 + iOS 27 模拟器） | 仅手动 `workflow_dispatch` |
| `.github/workflows/web-tests.yml` | 网页预览单元测试（`npm test`） | `ubuntu-latest` | 手动 + `apps/web` 变更推送 |

iOS 工作流只手动触发：交付脚本按当前提交的完整 SHA 触发，保证「构建的源码」与「要交付的源码」是同一个提交。网页测试与 iOS 交付互相独立，网页回归失败不会让真机包停摆。

## 输入

在 Actions 页面 `Run workflow` 时可选项：

| 输入 | 默认 | 说明 |
| --- | --- | --- |
| `run_unit_tests` | 开 | `apps/ios/scripts/test-core.sh`：离线 fixture 服务 + `swift test`，54 项核心测试，`-warnings-as-errors`。这是交付的硬门槛。 |
| `run_ui_tests` | 关 | `apps/ios/scripts/test-ios.sh`：iOS 27 模拟器界面测试。托管运行器上视频/媒体相关用例历史上不稳定（2026-11-07 的运行中 3 个视频用例失败），默认不跑；开了就要如实记录结论。 |
| `build_simulator_release` | 开 | `scripts/cloud-release.sh`：模拟器 Release 编译并 `analyze` 静态分析。 |

## 产物

运行成功后，同一仓库的 **Releases** 会出现标签 `build-<运行ID>-<尝试>` 的发布：

- `ZeroRed-ipa.zip`：解压后是 `ipa/` 目录，含 `ZeroRed-<版本>-<构建号>-<UTC时间>-unsigned.ipa`、`latest.json`、`.sha256` 和 `build-source.txt`。
- `ZeroRed-build-logs.zip`：编译日志、模拟器 Release 日志、界面测试日志与 `.xcresult`（失败时也发布，用于诊断）。

同时 Actions 运行页保留 `ZeroRed-build-<运行ID>-<尝试>` 构建产物（30 天）。

`build-source.txt` 记录构建提交号、运行编号和 Xcode 版本。Windows 导入脚本要求它的 `commit=` 等于当前 HEAD，否则拒绝更新安装包。

## 读取结果

- 运行页只显示步骤状态；具体日志看 `ZeroRed-build-logs.zip` 或运行页展开的步骤输出。
- 「整体成功」不等于测试真的跑过：界面测试默认被跳过，跳过不能记为通过。交付脚本按步骤名逐项读取实际结论（`Run core tests`、`Build unsigned device IPA`、`Publish build release`）。
- IPA 是**未签名**包，不代表已安装、已信任或真机验收通过。

## 成本与边界

- 公开仓库的标准托管运行器免计算分钟费；私有大仓/私有仓库另有额度规则，以 GitHub 官方计费说明为准。
- 托管运行器不能交互操作模拟器：真机相机、网页媒体播放、整体视觉与默认浏览器资格仍需实机人工验收。
- 不处理外部 PR，不接受外部代码触发构建；修改工作流前先审查。