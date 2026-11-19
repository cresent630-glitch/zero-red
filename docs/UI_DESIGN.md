# zero red 界面设计（iOS 27 · 原生 Liquid Glass）

本轮把界面改成 iOS 27 的原生外观：能交给系统控件的就不自绘，层次由系统玻璃负责，产品本身仍是黑白单色。最低部署版本保持 iOS 17，玻璃在 iOS 26 以下回退到系统材质，布局与命中区不变。

## 设计原则

- **单色**：只用 `.primary` / `.secondary` / 系统背景色。玻璃不加大面积彩色 tint，红只留在名字里。
- **内容优先**：网页、正文、视频占满可用区域；控件是悬浮胶囊，不用整条不透明工具条压住内容。
- **一屏一个主入口**：起始页唯一文本输入是地址框；浏览页地址栏同时是搜索、跳转与页面操作入口。
- **系统原生优先**：资料库用原生 `TabView`（系统玻璃标签栏），设置用 `Form`，阅读排版用 `Menu` + `Picker`，播放用系统 `Slider`、`AVRoutePickerView`。

## 界面结构

| 界面 | 结构 | 玻璃用法 |
| --- | --- | --- |
| 起始页 | 字标 `zero red` + 副标题 + 地址胶囊 + 最近访问胶囊 | 地址框 `.glassEffect(.regular.interactive(), in: .capsule)`；快捷胶囊同款 |
| 浏览页 | 顶部地址胶囊、细线进度、网页全屏；底部悬浮操作栏 | 底栏 `GlassEffectContainer` + 交互玻璃胶囊 |
| 页面总览 | 2 列卡片网格、无痕开关卡、最近关闭列表 | 卡片圆角 20、关闭按钮圆形玻璃、工具栏玻璃按钮 |
| 资料库 | 原生 `TabView`：书签 / 历史 / 视频 / 阅读 / 下载；设置移入工具栏齿轮 | 系统玻璃标签栏；`Done` 用 `.glassProminent` |
| 阅读 | 悬浮玻璃工具栏（返回 / 缓存 / Aa / 专注）+ 正文 + 底部进度胶囊；`#`/`##`/`###` 段落渲染为标题层级 | 顶部胶囊 + `.regular` 玻璃；专注模式只留一枚圆形玻璃专注按钮 |
| 播放器 | 顶部信息胶囊（关闭 / 标题 / 画中画）+ 传输控制胶囊（进度、播放、倍速、字幕、AirPlay、缓存） | 两枚悬浮胶囊，`.regular` 玻璃随系统深浅色自适应 |
| 网站设置 / 网站数据 / 文本编辑 | 原生 `Form` / `List` + 玻璃确认按钮 | `.glassProminent`，`[.large]` 弹出尺寸 |

## Liquid Glass 组件映射

| 用途 | 原生 API | 实现位置 | iOS 17–25 回退 |
| --- | --- | --- | --- |
| 玻璃表面 | `.glassEffect(_:in:)` | `zeroRedGlass(_:interactive:)` | `.ultraThinMaterial` + 0.5pt 描边 |
| 玻璃分组 | `GlassEffectContainer(spacing:)` | `zeroRedGlassGroup(spacing:)`、`GlassDock` | 直接返回内容 |
| 工具栏图标按钮 | `.buttonStyle(.glass)` | `GlassToolbarButton` | 普通按钮 |
| 主操作按钮 | `.buttonStyle(.glassProminent)` | `GlassProminentButton` | `.borderedProminent` |
| 资料库分页 | `TabView` + `.tabItem` | `LibraryView` | 系统标签栏 |
| 禁用/可用态 | 系统 `.disabled` | 底栏前进后退 | 相同 |

玻璃只出现在四类位置：悬浮底栏、地址/查找胶囊、工具栏按钮、卡片内的小圆形按钮。正文与列表行不加玻璃，避免层次过载。

## 尺寸与排版

| Token | 值 |
| --- | --- |
| 触控区 | 44 pt（底栏 44、工具栏 42、圆形关闭 30–38） |
| 底栏按钮间距 | 2 pt，胶囊内边距 6 / 4 |
| 卡片圆角 | 20 pt（页面卡片、无痕卡） |
| 内容圆角 | 26 pt（播放器控制胶囊） |
| 正文最大宽度 | 浏览 560 pt，阅读 740 pt |
| 字标 | 34 pt rounded semibold，tracking −0.8 |
| 进度线 | 3 pt 胶囊 |

## 兼容与回退

所有玻璃调用都在 `#available(iOS 26.0, *)` 分支内（`LiquidGlass.swift`），iOS 17–25 走材质回退。回退只替换观感，不改变间距、命中区、标识符或交互路径，因此同一套界面测试在两端都成立。

## 无障碍与测试标识

- 主要操作保持 44 pt 命中区；动态字体、减少动画、VoiceOver 标签沿用原实现。
- 既有标识符全部保留：`addressInput`、`addressGo`、`pageActions`、`tool.house`、`tool.books.vertical`、`tool.chevron.left/right`、`videoURLInput`、`downloadVideo`、`offlineVideo.<name>`、`readerContent`、`readerBack`、`offlinePlayer`。
- 新增 `tool.tabs`（页面总览按钮）与 `testDesignScreenshots`（视觉验收截图）。

## 验证方式与边界

| 环节 | 位置 | 说明 |
| --- | --- | --- |
| Swift 编译、核心测试、模拟器 Release 与静态分析 | GitHub Actions `xcode-27` | 本页所有改动都必须先过这一关 |
| 界面测试 | 同一云运行器 | 覆盖既有交互；`testDesignScreenshots` 依次截取首页、网页、页面总览、资料库、阅读、设置 |
| 截图导出 | 工作流 `Export UI screenshots` | 从 `.xcresult` 导出 PNG 到 `build/ui-screens`，随构建日志一起发布 |
| 真机视觉与手感 | 用户 iPhone | 玻璃真实景深、动态字体极限字号、VoiceOver 全流程、横屏、深色实机观感仍需人工验收 |

截图是模拟器渲染结果，不能代替真机验收；界面测试在托管运行器上对视频类用例不稳定，失败时以截图与本地设备为准。

## 已验证与已知限制

- 云编译、54 项核心测试、模拟器 Release 与静态分析在 `xcode-27` 运行器通过；`testDesignScreenshots`、`testEnglishMinimalHome`、`testChineseMinimalHome` 通过并导出 7 张截图（首页、网页、页面总览、资料库书签/历史、阅读、设置）。
- 截图设备是模拟器 `iPhone Duo`：它的状态栏浮在内容之上、顶部安全区为 0，所以截图里状态栏会压住地址栏与标签行。真机（灵动岛机型）会按安全区留出空间，这一点应在真机复核。
- 托管运行器首启 iOS 模拟器约 10–13 分钟，界面测试整体约 20–25 分钟；因此界面测试是工作流的可选步骤，默认只跑核心测试出包。
- 尚未验证：深色模式的玻璃观感、动态字体极限字号、VoiceOver 全流程、横屏、真机手感与视频播放器控制条。