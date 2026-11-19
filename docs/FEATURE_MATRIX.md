# zero red 0.2 功能覆盖与验收状态

本轮按浏览器评估表实现，排除跨设备同步，并把界面改为 iOS 27 原生样式 + Liquid Glass（见 `docs/UI_DESIGN.md`）。**2026-11-19 起改由 GitHub Actions 的 `xcode-27` 运行器执行编译、核心测试与真机 IPA 打包；界面测试为可选步骤，截图随构建日志发布。仍未完成真机和全部功能专项验收。**

| 评估项 | 原生 iOS 工程现状 | 网页预览现状 / 实际限制 |
| --- | --- | --- |
| 真实网页、登录、支付、验证码、弹窗、上传 | WKWebView；JS alert/confirm/prompt；HTTP Basic/Digest；链接新窗口；可配置弹窗；WebKit 原生 file input 和系统相机/麦克风授权 | 外站在新标签打开；无法在本预览内运行完整的第三方网站。实际登录、支付、验证码与上传兼容性未验收 |
| 标签页、恢复与内存 | 独立 WKWebView；常规会话恢复；最近关闭恢复；常驻最多 6 个 WebView；后台暂停媒体；内存警告释放非当前 WebView | 多页面、独立前后退/草稿/位置、最近关闭已实现。恢复是 URL/历史/滚动位置，不恢复 POST、表单或网站完整 JS 状态 |
| 无痕 | 独立 nonPersistent WebKit 数据存储；不写历史、恢复或最近关闭；结束会话释放；切后台遮挡无痕内容 | 仅预览标签不记历史、不恢复。无法控制外部浏览器新标签中的 Cookie；不等同系统无痕窗口 |
| Cookie、缓存、权限 | 全部/分站网站数据清理；相机/麦克风策略；弹窗与拦截开关；系统权限入口 | 可清理预览自己的数据；不能控制外部网站权限。定位等权限仍由 iOS / WebKit 系统交互决定 |
| 安全交互 | 域名与 HTTPS 状态；系统默认 TLS 校验，无证书绕过；WebKit 欺诈警告；点击外部协议时确认 | 显示地址与连接说明；不能提供跨站的安全过滤服务。没有宣称 HTTPS 等于内容安全 |
| 分享与系统打开 | UIActivityViewController / ShareLink；复制链接；文件导出；文档接收；zerored URL scheme | Web Share / 剪贴板（浏览器需支持）；文件下载导出 |
| 普通下载 | 后台 URLSession；WebKit 下载转接；进度、暂停、取消、resumeData、重试、持久化、QuickLook 与文件导出 | CORS 允许的 HTTPS 下载；100 MB；暂停/失败保留部分数据，Range 续传；需要保持页面打开 |
| 阅读 | 当前网页正文提取；TXT/MD/HTML/PDF/DOCX 导入；文字与原文件缓存；全文/标签搜索；标题与标签编辑；目录；文本导出和 JSON 备份；进度；系统正文翻译 | 对应交互已实现。外部网页提取需要 CORS；翻译在用户操作后打开 Google Translate，超过 5000 字需先选择文字。无 OCR，不支持旧 .doc |
| 浏览设置 | Bing/Google/DuckDuckGo/百度；桌面请求；缩放；语言与外观 | 搜索引擎和内容缩放可体验；网页不能切换浏览器 UA 来替代原生桌面站点 |
| 默认浏览器 | 系统设置入口、HTTP/HTTPS onOpenURL 路由，以及未启用的 entitlement 模板 | **未完成外部前置条件**：需要 Apple 对真实 App ID 授权和匹配签名。不能靠改代码或网页按钮获取资格 |
| 视频 | 网页内联播放；AVPlayerLayer 播放器；统一显隐的播放/进度/缓存控制；倍速；内嵌与 SRT/VTT 字幕；AirPlay；PiP；匹配 Cookie 传递；MP4/MOV 后台下载；AVAssetDownloadURLSession HLS 离线任务 | 播放、统一控制显隐、倍速、字幕、缓存；PiP/投屏入口按宿主浏览器能力显示。受保护、MSE/blob、特殊鉴权视频无法承诺通用下载 |
| 广告/追踪/弹窗 | WKContentRuleList 本地基础域名和广告选择器规则；额外域名；按站关闭；弹窗默认限制 | 网页预览不伪装成可过滤其他网站的浏览器。基础规则不是完整广告过滤订阅服务 |
| 无障碍与稳定性 | 44pt 主要操作触控区；VoiceOver 标签；动态字体；减少动画；VoiceOver 时播放器不自动隐藏；错误状态、低存储预检；iOS 27 Liquid Glass 原生外观（悬浮玻璃底栏、玻璃地址栏与工具栏，iOS 17–25 回退系统材质）；测试脚本与 CI 配置 | 基本键盘操作、可访问标签、减少动画。完整 VoiceOver、横屏、弱网、低内存与真实页面兼容性仍需设备验收 |
| 跨设备同步 | 按要求不实现 | 不实现 |

## 不能省略的后续验收

1. Xcode 编译已通过；继续处理测试日志中的音频主线程和 SwiftUI 状态发布运行时警告。
2. iOS 27 模拟器 UI 测试及 Release 静态分析已通过；仍需用 iPhone 验证系统翻译、AirPlay、PiP、HLS、后台下载与系统权限。系统翻译不能只靠模拟器验证。
3. 建立实际目标网站清单，逐站测试登录、支付返回、验证码、第三方授权、上传、弹窗和视频。WebKit 接入不能自动保证每个网站兼容。
4. 由账号持有人申请 Apple 默认浏览器资格；批准后接入 entitlement 和签名，才能验收系统默认浏览器切换。

## 测试与交付

- Linux：54 项 Swift 核心测试通过，含旧 VideoDownloader 路径的真实 HTTP 测试；它们**不覆盖新的 Apple 后台下载代理、WKWebView、AVPlayer、PDFKit 和 SwiftUI 界面**。
- 网页：73 项 Node 单元测试通过，含标签/隐私、PDF/DOCX 解析、IndexedDB 模拟迁移、播放器控制状态，以及下载字节/Range 恢复流程。IndexedDB 使用 fake-indexeddb；下载流程使用 Response/ReadableStream 受控响应。
- App/UI Swift 源码语法检查、OpenStep 工程引用和 Info.plist 检查通过。
- Xcode 27 构建与 Release 静态分析：**云端已通过**。界面测试为可选步骤，结论与导出的 `ui-screens` 截图以当次运行日志为准。真机测试、实际网页浏览器点击回归仍未执行。
- `.github/workflows/ios-cloud-build.yml` 在 GitHub 托管 macOS 运行器上执行核心测试、模拟器 Release 与真机 IPA 打包；交付入口见 `docs/DEV_TO_DELIVERY.md`。
