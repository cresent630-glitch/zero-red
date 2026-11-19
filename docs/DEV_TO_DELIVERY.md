# zero red：从开发到交付的完整链路

本文是 Windows 开发机到 iPhone 的端到端流程。iOS 编译只在 GitHub 托管的 macOS 运行器上发生；Windows 本机不需要 Xcode、Mac 或 Tailscale。

## 链路总览

```
Windows 工作副本（C:\myfile\my_project\dsh\zerored，Git）
  │  ① 修改源码/测试/文档
  │  ② scripts/preflight.ps1 本地预检（静态检查，不编译）
  │  ③ 一键交付.cmd：预检 → 审查提交 → 推送
  ▼
公开仓库 cresent630-glitch/zero-red
  │  ④ 按当前 HEAD 的完整 SHA 触发 ios-cloud-build
  ▼
GitHub 托管 macOS 运行器（xcode-27）
  │  ⑤ 核心测试 →（可选界面测试）→ 模拟器 Release/静态分析 → 未签名真机 IPA
  │  ⑥ 结果写入 Releases：build-<运行ID>-<尝试>（IPA + 构建日志）
  ▼
Windows 交付脚本
  │  ⑦ 下载 ZeroRed-ipa.zip → 校验 Release 摘要 → 校验提交一致性/SHA256/iPhoneOS/arm64/iOS 17
  │  ⑧ 导入 build/ios-device，写交付收据 build/reviews/delivery-*.json
  ▼
安装入口：安装到iPhone.cmd → Sideloadly 本机签名 → iPhone
```

仓库是**公开**的：工作流配置、源码、编译日志和 IPA 都可见。因此不要提交密钥、照片、真实浏览记录或 Apple 账户信息。

## 一次性配置

1. 仓库公开：`https://github.com/cresent630-glitch/zero-red`（Settings → General → 底部 Danger Zone → Change visibility）。公开仓库的标准托管运行器免计算分钟费。
2. Actions 已启用，工作流 `iOS cloud build` 出现在 Actions 列表（只手动触发，无需 Secrets）。
3. 本机工具：Git（已登录 github.com，交付脚本从 Git 凭据管理器取令牌，不落盘）、Python 3.11+（预检用 `yaml` 解析工作流）、Sideloadly（真机签名安装时才需要）。

## 日常开发循环

1. 在 `C:\myfile\my_project\dsh\zerored` 修改源码/测试/文档。工程配置以 `apps/ios/ZeroRed.xcodeproj/project.pbxproj` 为准（bundle 编号、最低系统、版本号都从这里读）。
2. 本地预检：
   ```powershell
   powershell -NoProfile -ExecutionPolicy RemoteSigned -File scripts\preflight.ps1
   ```
   覆盖：Git 状态与空白、PowerShell/Bash/Python 语法、工作流 YAML 与关键指向、Xcode 工程结构、密钥扫描、忽略规则、应用身份与版本。**不包含** iOS 编译、Swift 单元测试和界面测试。
3. 审查差异并提交（不提交 `build/`、安装包、凭据、真实数据）。
4. 双击 **`一键交付.cmd`**（可选参数 `-RunUiTests`、`-SkipSimulatorRelease`）：
   预检 → 要求工作区干净 → 推送 → 触发云构建 → 跟踪 → 逐项读取步骤结论 → 下载 Release（校验摘要）→ 导入并校验 IPA → 安装入口验证 → 写交付收据。
5. 连接 iPhone，双击 **`安装到iPhone.cmd`**，在 Sideloadly 用同一 Apple 账户与 App 编号签名覆盖安装。免费签名 7 天有效，续签前先导出 App 内备份。

### 手动备用路径

- 网页触发：<https://github.com/cresent630-glitch/zero-red/actions/workflows/ios-cloud-build.yml> → Run workflow → 勾选需要的步骤。无需填 SHA：工作流构建的就是所选分支的当前提交。
- 网页下载：Releases 里 `build-<运行ID>-<尝试>` 的 `ZeroRed-ipa.zip`，解压后双击 `更新真机安装包.cmd`，输入其中 `ipa` 文件夹路径。
- 续跑跟踪：`一键交付.cmd -RunId <运行ID>`，只跟踪已有运行，不重复推送或触发。

## 验证边界（如实区分）

| 环节 | 验证位置 | 说明 |
| --- | --- | --- |
| 语法、工作流 YAML、工程结构、密钥与忽略规则 | Windows 预检 | 离线静态检查，不编译 |
| Swift 核心测试（54 项，离线 fixture） | GitHub Actions macOS 运行器 | 交付硬门槛；未运行或跳过不算通过 |
| 界面测试（可选） | GitHub Actions macOS 运行器 | 托管环境下视频/媒体用例不稳定，默认关闭 |
| 模拟器 Release 编译与静态分析 | GitHub Actions macOS 运行器 | 结论按步骤读取 |
| 真机 IPA 编译与打包校验 | GitHub Actions macOS 运行器 | 产物内校验平台/架构/最低系统/未签名状态 |
| IPA 提交一致性、SHA256、iPhoneOS/arm64/iOS 17 | Windows 导入校验 | `build-source.txt` 的提交号必须等于本地 HEAD |
| 签名、安装、信任、开发者模式 | 用户 iPhone + Sideloadly | 脚本不代替 Apple 验证 |
| 网页媒体播放、相机、视觉与默认浏览器资格 | 实机人工验收 | 云端模拟器不能替代 |

失败或权限不足时如实记录未验证项，不用旧包代替新构建。交付收据包含提交 SHA、运行链接、Release 链接、IPA 哈希与未验项清单。

## 常用命令

```powershell
# 只跑预检
powershell -NoProfile -ExecutionPolicy RemoteSigned -File scripts\preflight.ps1

# 完整交付（含界面测试）
pwsh -NoProfile -File scripts\deliver.ps1 -RunUiTests

# 跳过界面测试与模拟器 Release，只出真机包
pwsh -NoProfile -File scripts\deliver.ps1 -SkipSimulatorRelease

# 跟踪已有运行
pwsh -NoProfile -File scripts\deliver.ps1 -RunId 12345678901
```

## 常见问题

- **触发后找不到运行**：确认工作流在默认分支上、Actions 已启用；`workflow_dispatch` 只在实际存在该文件的分支上可用。
- **运行一直排队**：`xcode-27` 是 GitHub 托管运行器标签；若账号无权使用该镜像会一直等待，改用 `macos-26`/`macos-latest` 需要同步修改工程最低系统与 `scripts/package-ipa.sh` 的期望值。
- **核心测试失败**：`test-core.sh` 用 `-warnings-as-errors`，新工具链的警告也会让测试失败；看 `ZeroRed-build-logs.zip` 里的核心测试输出。
- **导入报提交不一致**：本地 HEAD 与构建 SHA 不同；重新推送并构建当前提交，或检出对应提交后再导入。
- **网页测试失败**：`web-tests` 工作流与 iOS 交付独立，不影响 IPA；需要单独修。