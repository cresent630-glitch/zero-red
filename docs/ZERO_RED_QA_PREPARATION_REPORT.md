# zero red 0.2 本轮测试准备报告

日期：2026-11-07（Asia/Shanghai）。结论：**项目用例、执行登记与本地测试资源已准备；原生执行仍有同源/端口及真机资源前置条件。** 本报告不是 APP 验收通过报告。

## 本轮交付

- [108 条项目专用用例](ZERO_RED_TEST_CASES.md)：依据当前 Swift 源码和产品要求，覆盖浏览、书签历史、页面真实预览与恢复、完整文本提取/全屏阅读/专注缓存、五种文档导入、视频多入口/统一控制/缓存离线、隐私与可靠性。
- [执行指南](ZERO_RED_TEST_EXECUTION.md)：范围裁剪、数据清单、模拟器/真机步骤、批次与发布门槛、待确认规则。
- `apps/ios/scripts/prepare_qa.py`：可重复生成源码哈希、逐条待执行 JSON、数据样本和环境检查结果；不清理真实资料库。
- `apps/ios/Fixtures/qa/`：会话隔离/权限、GET 表单输入及外部协议测试页。
- 修复网页 PDF 测试在 Windows 上的 worker 路径：使用标准 file URL，未修改 APP 产品逻辑。已安装项目声明的 fake-indexeddb 6.0.0 测试依赖，并用 npm registry 发布的 SHA-512 integrity 校验下载内容。

## 实际检查与证据

| 项目 | 本轮结果 | 证据/限制 |
| --- | --- | --- |
| 用例完整性 | 108 条、ID 无重复；全部初始化 NOT_RUN | 最终登记 `../apps/ios/TestResults/qa-prep-20261107T144353Z-432102/execution.json` |
| 工程引用/Info.plist | 通过 | `../apps/ios/TestResults/qa-prep-20261107T144245Z-b03f75/run-local-project.log` |
| 网页单测 | 73 通过，0 失败 | 同目录 `run-local-web-{core,reading,storage,media,download-flow}.log`，分别 38/18/5/7/5 |
| HTTP fixture | 17 项通过 | 最终目录 `readiness.json`；含来源禁用返回 503 再恢复、MP4 哈希比对；不是浏览器操作验收 |
| 测试数据 | 已生成文本/字幕/坏文件/PDF/DOCX 和 20MiB±1B | 最终目录 `fixtures/` 与 `fixture-manifest.json`；大文件为真实合成文本，不代表合法大型 PDF |
| 源码基线 | 当前工作区哈希与 Git 状态已记录 | 最终目录 `source-manifest.json`，含未提交开发改动；未回退/覆盖这些改动 |
| 脚本语法/差异空白检查 | 通过 | Python py_compile、git diff --check |
| 本机原生工具 | Windows 缺 Swift/Xcode | 本轮没有执行 Swift 核心、Xcode build 或 UI suite |
| 云 Mac | 只读连接成功，Xcode 27.0/27A266a、iOS 27 模拟器、约37GiB可用磁盘 | iPhone 18 Pro UDID `F75E896E-D837-4A23-98E2-8C52E6124E90`；执行时需重新核实 |
| 原生自动化数量 | 源码当前含 15 个 test 方法 | 已与具体用户用例映射；历史文档的 7/8/11 不作为本轮执行数量 |

早期准备探测暴露 loopback 沙盒访问限制、缺测试依赖和 Windows PDF 路径问题；依赖与路径已处理，fixture 自检在获准的本地网络执行中通过。失败日志保留，以上只报告最终对应检查；未通过的数据不会混算成 APP 测试通过。

## 尚未满足的执行条件

1. 云端抽查 10 文件中，NativePlayer.swift 和 ZeroRedUITests.swift 与本地哈希不同，其余抽查 8 文件相同。未上传覆盖云端；执行前比对全清单并明确候选源码，或用隔离运行目录。
2. 云端 8765 当时由 Python PID 92325 监听；未结束进程。当前脚本固定使用该端口，需确认服务归属并安排互斥，避免 UI 测试误用旧 fixture。核心/UI 测试应串行。
3. 真机签名与设备、AirPlay、合法 HLS/长视频、可信 HTTPS 权限/证书站、POST 计数后端、支付沙盒和目标登录站需另行核实。默认浏览器资格尚依赖 Apple 授权。
4. 无痕主动保存资产、全文跨域/懒加载边界、最低支持系统正式范围等规则待确认；工程部署目标 17.0，不能据此宣称 17–27 全部已验收。

下一批顺序：先对齐原生候选源码和 fixture 服务，再执行 Swift 核心→15 方法 UI→Release build/analyze，随后按专用用例执行阅读/视频冒烟、真机功能与可靠性专项。73 项网页单测不能替代任何未执行的原生/真机结论。
