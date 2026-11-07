# zero red

黑白极简原生 iPhone 浏览器，SwiftUI + WebKit + AVFoundation。当前版本 0.2。

**状态：已在 Xcode 27 / iOS 27 模拟器通过 Debug/Release 编译、8 项界面测试和 Release 静态分析；真机验收仍待完成。** 完整验证记录见项目根目录的 `docs/TEST_REPORT.md`；云 Mac 使用说明见 `docs/CLOUD_MAC.md`。

## 本轮功能

- 原生多标签、最近关闭、URL/历史/滚动恢复、无痕 WebKit 数据隔离、后台媒体暂停和内存回收。
- 原生网页窗口、JS 对话框、HTTP 鉴权、上传、分站媒体权限、域名/HTTPS 信息、默认 TLS 验证及 WebKit 欺诈警告。
- 搜索引擎、桌面网站、缩放、系统分享、复制链接、页内查找、系统设置、基础广告/追踪拦截和分站数据清理。
- 普通文件及视频下载管理，后台任务、进度、暂停/取消/重试、可用时续传、文件预览/导出。
- 当前文章阅读模式；文本、Markdown、HTML、PDF、DOCX 导入；离线资料、全文/标签搜索、目录、排版、文本导出/备份和系统正文翻译。
- 统一显隐的视频控制栏，倍速、内嵌和外部字幕、AirPlay、画中画、MP4/MOV 缓存与 HLS 离线任务。
- 不包含跨设备同步。默认浏览器资格仍需 Apple 授权；受保护视频和所有真实网站兼容性不能由代码交付保证。

## Mac 上打开

1. 安装完整 Xcode，打开 `ZeroRed.xcodeproj`。
2. Xcode 会解析固定版本 ZIPFoundation 0.9.19，用于 DOCX 文档内的 ZIP 读取。此为原生工程新引入的依赖；跨平台核心测试无需它。
3. 选择 iPhone 模拟器运行；真机请选择自己的 Team 和唯一 Bundle ID。
4. iOS 27 验证需对应的 Xcode/SDK/Simulator Runtime。下载真实系统版本与所用 Xcode版本应记录到验收日志。
5. 默认浏览器 entitlement 未启用，说明与模板在 `Configuration/`。

## 测试

```sh
bash scripts/test-core.sh
xcrun simctl list devices available
IOS_SIMULATOR_ID='<iPhone Simulator UDID>' bash scripts/test-ios.sh
```

第一条需要 Swift 6+、Python 3，并使用回环地址启动真实 HTTP fixture。第二/三条仅适用于装有完整 Xcode 的 Mac。测试结果放在 `TestResults/`；完整 UI、后台下载、HLS、AirPlay、PiP、翻译、网站兼容性验收步骤见功能覆盖表。

网页预览：[zero red preview](https://zero-red-preview.alpinefoam3.chatgpt.site)。它用于体验交互，无法代替原生浏览器或 iOS 27 的系统功能验证。
