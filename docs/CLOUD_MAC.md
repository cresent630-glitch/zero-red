# 云 Mac 调试（历史记录）

> 当前默认路径是 GitHub Actions 云编译与交付，见 [DEV_TO_DELIVERY](DEV_TO_DELIVERY.md) 与 [GITHUB_ACTIONS_BUILD](GITHUB_ACTIONS_BUILD.md)。本文保留 2026-11-07 的云 Mac 连接方式，仅作历史记录；不再作为前置条件或默认回退。

项目目录：`/Users/chuzu/zero-red-20261107`。

环境：Xcode 27.0（27A266a），iOS 27.0，iPhone 18 Pro 模拟器。

Windows PowerShell 连接命令（需先连接已授权的 Tailscale 网络）：

```powershell
ssh -i "$env:USERPROFILE\.ssh\zero_red_cloud_mac" chuzu@100.70.223.101
```

私钥保存在 Windows 用户的 `.ssh` 目录中，不属于项目文件，不上传到 Mac 或代码仓库。

连接后运行：

```bash
cd ~/zero-red-20261107/apps/ios
bash scripts/test-core.sh
IOS_SIMULATOR_ID=F75E896E-D837-4A23-98E2-8C52E6124E90 bash scripts/test-ios.sh
```

Xcode 工程：`/Users/chuzu/zero-red-20261107/apps/ios/ZeroRed.xcodeproj`。

Windows 和云 Mac 是两份独立源码，修改后需要显式同步。上传时排除私钥、`.git`、`node_modules`、`.build`、`DerivedData` 和测试生成的构建目录。不要用旧压缩包覆盖后续修复。

模拟器测试不需要开发者签名。真机安装和发布仍需要 Apple 开发者账号、签名与对应设备。
