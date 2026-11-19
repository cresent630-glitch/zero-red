# zero red 开发约定

- 本项目是从 `C:\myfile\my_project\zero_red` 导入的工作副本。原目录保持不变；Git 远端 `origin` 是唯一仓库 `cresent630-glitch/zero-red`（公开），`upstream` 指回原目录做对照。不要强推、不要删除远端仓库。
- 开始任务前阅读 `README.md`、`docs/DEV_TO_DELIVERY.md`、`docs/GITHUB_ACTIONS_BUILD.md`；产品范围与功能矩阵看 `docs/PRODUCT.md`、`docs/FEATURE_MATRIX.md`，测试用例看 `docs/ZERO_RED_TEST_CASES.md`。
- iOS 编译、Swift 核心测试、界面测试和真机 IPA 打包**只在 GitHub Actions 的 macOS 运行器**执行（标签 `xcode-27`）。Windows 不安装 Xcode、不调用 `xcodebuild`，也不用云 Mac/Tailscale（`docs/CLOUD_MAC.md` 仅作历史记录）。
- 交付入口是根目录 `一键交付.cmd`（`scripts/deliver.ps1`）：本地预检 → 推送 → 按 SHA 触发云构建 → 跟踪 → 逐项读取步骤结论 → 下载并校验 IPA → 更新安装入口 → 写 `build/reviews/delivery-*.json` 收据。手动路径见 `docs/DEV_TO_DELIVERY.md`。
- 工程配置唯一来源是 `apps/ios/ZeroRed.xcodeproj/project.pbxproj`：bundle 编号 `com.zerored.browser`、最低 iOS 17.0、`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。`scripts/package-ipa.sh` 与 `scripts/Test-DeviceIpa.ps1` 会从 pbxproj 读取期望值并与真实产物比对；改身份或最低系统必须同时更新 `docs/` 与 `project.json`。
- 仓库是**公开**的：工作流、源码、编译日志和 IPA 都可见。不提交密钥、API Key、照片、真实浏览记录、Apple 账户信息、描述文件或签名材料；本机凭据只存在于 Git 凭据管理器。
- 交付必须对应已推送提交。云构建只含已推送内容；导入时 `build-source.txt` 的 `commit=` 必须等于本地 `HEAD`，不一致就停下重新构建。失败或未运行的步骤如实记录，不用旧包代替新构建。
- 界面测试在托管运行器上不稳定（视频/媒体用例历史上会失败），默认关闭（`run_ui_tests=false`）。UI 变更仍需实机人工视觉验收，不能以模拟器通过代替。
- 每个可交付增量：预检 → 审查提交 → 一键交付 → 记录提交 SHA、运行链接、Release 链接、IPA 哈希与未验证项。
- 不要用 `README.md` 里的在线预览地址当作本仓库的部署结果：网页预览仍由外部 Sites 源管理，`apps/web/dist/` 是开发快照。
- 提交不包含 `build/`、`*.ipa`、`apps/ios/TestResults/`、`node_modules/`；这些已在 `.gitignore` 中忽略，预检会核对。