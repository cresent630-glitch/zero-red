# zero red 测试执行准备与操作手册

入口：[项目专用用例](ZERO_RED_TEST_CASES.md)。通用旧用例仅供补充参考。准备脚本不安装 APP、不清理 APP 数据、不覆盖云 Mac、不触碰签名或申请授权。

## 1. 先建立本轮基线

在仓库根运行（Python 3 标准库，无额外依赖）：

```powershell
python apps/ios/scripts/prepare_qa.py
# 同时执行当前机器可运行的项目检查和 Node 测试（不会自动安装依赖）
python apps/ios/scripts/prepare_qa.py --run-local
# 需要导入边界文件时，才额外生成约 63 MiB 大样本
python apps/ios/scripts/prepare_qa.py --large-fixtures
```

每次输出到 `apps/ios/TestResults/qa-prep-<UTC时间>-<随机后缀>/`，包括：

- `readiness.json`：工具/依赖、fixture HTTP 自检、当前 UI test 名单、部署版本、状态与限制。
- `source-manifest.json`：原生、fixture、脚本及测试源码哈希；Git HEAD/dirty（可读取时）。云 Mac 必须对照此清单确认同一源码，不拿旧 tar 包覆盖当前改动。
- `execution.json`：每条专用用例一条待执行记录，含设备、系统、版本、网络、前置、步骤、预期、实际、证据、缺陷等字段；按设备和参数复制记录，不能一条覆盖全部组合。
- `run-local-*.log`（显式指定 `--run-local` 时）：本机实际执行日志，失败/阻塞保留；不把准备状态写成 APP 通过。
- `fixtures/`：可从文件 APP 导入的合成文本、字幕、损坏样本、PDF/DOCX 样本副本和可选大文件；`fixture-manifest.json` 含大小与哈希。

准备过程会用随机 loopback 端口启动既有 fixture Handler 做自检，结束即关闭；不修改固定端口 8765 的现有服务。此自检只证明测试资源可用，不能证明 APP 功能通过。

## 2. 数据和 fixture 使用

| 编号 | 现有资源/准备输出 | 使用限制 |
| --- | --- | --- |
| F1 浏览 | `apps/ios/Fixtures/index.html`、second.html、interaction.html；`/redirect`、`/error.mp4`、`/fake.mp4` | 静态页/弹窗/上传/下载；没有完整慢网、Range、HTTPS、HTTP Auth 等服务，不能宣称这些已准备完成 |
| F2 阅读 | reader-complete.html、reader-frame.html；生成 `reading-zh.md`、`reading-utf16.txt`、`reading.html` | 等待动态文字加载；完整提取仅同源/开放 Shadow DOM 基线 |
| F3 导入 | 复制网页 tests/fixtures 的 reading.pdf、reading.docx；生成 empty.txt、broken.docx、broken-backup.json、unsupported.doc | 现有样本需在 iOS PDFKit/ZIPFoundation 重新验证；加密/扫描/500页 PDF 和特殊备份需另备 |
| F4 视频 | sample.mp4、video-controls.html、video-frame.html；生成 captions.srt/captions.vtt；`/offline-sample.mp4` | 仅短 MP4 和同源 iframe；需另外准备合法长 MOV/MP4、HLS、多音轨/内嵌字幕、跨域/受保护流 |
| F5 隔离/权限/拦截 | 新增 `qa/session.html`：Cookie/localStorage/IndexedDB 哨兵与来源、HTTPS 权限按钮；`qa/external.html` | loopback 可测存储；真机摄像头/定位、跨域及拦截须部署可信 HTTPS 测试域名；localhost 与 127.0.0.1 可用于模拟器不同主机存储对照 |
| F6 表单 | 新增 `qa/form.html` GET 编码回显页 | 表单提交计数、POST 幂等性、支付沙盒仍需受控后端，当前 GET 回显不能替代 |
| F7 安全 | 待配独立自有有效/过期/错域/不可信 HTTPS 域名 | 不安装全局信任证书绕过生产判断；不访问不明恶意站 |
| F8 资产/边界 | 自动生成 20MiB±1B 文件和 metadata（按需）；通过 APP 手工建立书签、阅读与视频基准清单 | 大文件针对大小边界，不等同合法 PDF 页数或有效超长 DOCX；备份合法数据应由 APP 自身导出 |
| F9 实站兼容 | 见下表 | 需按版本、地域与时间留证；只用获授权测试账号，不做真实扣费 |

目标网站首轮清单：

| 网站/类别 | 固定流程 | 外部准备 |
| --- | --- | --- |
| B 站 | 首页→当前可访问视频→直接点击画面→播放/缓存→重启离线播放 | 留实际 BV、URL、时间、登录与清晰度；历史 BV1VS4i6fEw2 仅作参考，不假设一直有效 |
| Bing/Google/DuckDuckGo/百度 | 同一组中英关键词→结果→返回 | 记录网络地区，服务不可达不等于搜索逻辑失败 |
| 团队确认的登录/验证码站 | 登录→新标签共享→退出→授权返回 | 测试账号/验证码渠道；尚未指定站点时标待准备 |
| 团队支付沙盒 | 成功/失败/取消/回跳及幂等核对 | 沙盒商户及只读订单核查入口；没有环境时阻塞 |
| 团队上传/直播/HLS 站 | 图片/文件/相机上传，直播与离线 HLS | 获授权资源、HTTPS 域名、Range/鉴权/跨域后端 |

## 3. Mac / 模拟器准备

1. 使用 `CLOUD_MAC.md` 中已有授权连接。先只读检查 Xcode、可用 iPhone 模拟器、磁盘和当前源码；不要上传整个旧归档覆盖远端。
2. Windows 当前有未提交开发改动：对照 source-manifest 的 SHA-256，明确同步文件集合后显式同步；保留云端独有改动并核对冲突。测试日志标记实际 build 对应的源码，不能只记 0.2.0。
3. 当前现有 UI suite 为 15 个方法，历史文档数字不一致；本次以实际新日志为准。确认 `-ui-testing` 和 `-reset-library` 仅用于隔离测试沙盒；不要在普通运行中执行重置。
4. 现有脚本固定绑定 `127.0.0.1:8765`，UI 测试固定访问 localhost。先确认端口未占用；不要结束未知服务。核心测试和 UI 测试串行运行，避免抢端口和修改离线源开关。

```bash
cd /Users/chuzu/zero-red-20261107
python3 apps/ios/scripts/prepare_qa.py --run-local
xcodebuild -version
xcrun simctl list devices available
cd apps/ios
bash scripts/test-core.sh
# 选择本次实际存在的 UDID，不能盲目复用旧记录
IOS_SIMULATOR_ID='<本次UDID>' bash scripts/test-ios.sh
```

现有脚本产生 Debug test xcresult、Release build/analyze 和日志。先查源码/fixture 一致性再跑；执行脚本会启动服务并在结束时释放服务。`test-core.sh` 依赖 Swift 6+ 和 bash；Windows 上缺 Swift/Xcode 时不能据网页单测宣称原生已通过。

手工模拟器：先运行 `python3 apps/ios/scripts/fixture_server.py`（前台）；访问 `http://localhost:8765/qa/session.html`、`/reader-complete.html` 等。该服务仅监听 loopback，**真机 localhost 是手机本身**。真机需将合成 fixture 部署到团队可访问的受控 HTTPS 主机，不要直接把本地测试服务开放到公网。

## 4. 真机与系统专项准备

需要：Apple 签名 Team、专用 Bundle ID 和测试设备；最低支持/低内存 iPhone、主流大屏 iPhone；目标 iOS 27 真机。工程最低版本从 readiness 报告读取，待产品确认支持范围后补齐其余正式版本。AirPlay 接收端、蓝牙耳机、PiP 支持资源、HLS 离线资源、翻译语言包、可控弱网、有限存储专用设备、旧版本安装包需分别准备。

默认浏览器资格目前作为明确外部阻塞项：账号持有人获 Apple 批准后配置 entitlement 和匹配签名，再验证系统入口。不得用未启用模板或设置按钮当作资格通过证据。

本次只读预检确认云 Mac Xcode 27.0（27A266a），目标 iPhone 18 Pro 模拟器已启动，可用磁盘约 37 GiB；工程部署目标为 iOS 17.0。检查时 8765 被 PID 92325 的 Python 服务占用，未结束该服务。当前云端 NativePlayer.swift 与 UI 测试文件哈希和本地不同（其余抽查 8 文件相同），因此当前云端不可直接作为本地候选包的同源验收环境。执行前必须复核进程归属并协调端口、对齐源码或使用隔离运行目录；这些都是本次已知事实，不应被“有 Mac”掩盖。

破坏性测试只用专用沙盒；清理/卸载前先导出 F8 并核验文件，低空间测试不填满用户主力设备。支付只用沙盒。

## 5. 执行批次与门槛

| 批次 | 内容 | 开始条件 |
| --- | --- | --- |
| R0 准备 | 本机校验、fixture 自检、源码清单和用例登记 | 当前工作区可读；失败保留并处理 |
| R1 自动化 | Swift 核心→15 方法 UI→Release build/analyze；网页测试独立统计 | Mac 同源、依赖就绪、端口空闲；脚本结果真实留档 |
| R2 冒烟 | A01/A02、B01/B04、C01/C02/C06、D01/D04/D05、E01–E09、G01–G03 | 候选包可运行；使用同一源码和测试沙盒 |
| R3 功能 | 全部适用用例、导入边界、权限、下载竞态、站点兼容 | 对应数据/真机/外部环境具备 |
| R4 可靠性 | 弱网、内存、保存边界、长稳、24h、耗电与无障碍 | R2 核心问题解决；设备与采样工具就绪 |

8 小时脚本：每 20min 一轮，共 24 轮；浏览 5 页、搜索 3 次、开关 10 页、提取并缓存 1 篇、专注阅读 2min、播放/缓存视频并离线复开、删除本轮临时资产、后台 1min。每 4 轮加断网恢复和无痕隔离。每轮记资产数量/哈希、内存、错误和恢复耗时，每 2h 记电量/温度。单独做 1/8/24h 待机与系统回收；失败停止并保留证据，不静默重启算通过。

性能建议预算（执行前确认）：冷启动 P95≤3s、热启动≤1s、已加载切页≤500ms、输入≤100ms；每项至少 30 样本，最近秩 P95，失败单列。同设备网络比基线回退≤10%；视频和阅读不能持续卡死或白屏。最低支持机预算可单列，但不得测后改指标。

发布建议：所有适用 P0/P1 已执行且通过；无未解决隐私泄露、资产损坏、核心不可用及崩溃；P2 缺陷逐项评审；外部阻塞和未覆盖项如实列出，不能当通过。报告分别列“已执行/适用总数”和“通过/已执行数”，N/A 必须有范围依据。当前准备完成不等于发布验收完成。

## 6. 待确认/待补资源，不阻塞其他独立准备

- 支持的最低 iOS/设备正式范围；性能预算签字；文档版本声称数量与源码方法数不一致需在实际执行后更新报告。
- 从无痕主动保存文档/视频是否应保留、是否先提示；同站无痕子会话范围；清历史是否同时清普通已打开会话导航记录。未确认前相关分支标待确认，不盲判通过。
- 当前上限 50 页是否所有入口一致（恢复/无痕/弹窗）；恢复导入备份是否允许重复新增。发现违反已确认需求时记缺陷。
- 阅读跨域/懒加载完整性承诺；缓存提取失败是否应明确提示；进度近似恢复精度。
- 真机、签名、Apple 默认浏览器资格、AirPlay/HLS/翻译/证书测试站、POST 计数与支付沙盒、目标登录站尚需核对实物可用性。
