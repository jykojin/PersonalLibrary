# 图书信息补全升级（原子化 + AI 补全） — 设计文档

**日期：** 2026-09-19
**状态：** 已批准（用户逐节确认，末节「批准」），待拆实现计划
**涉及范围：** 三处补全逻辑收敛为一个原子功能；Open Library 退出简介供给；新增 AI 补全子系统（配置 + 检索/生成两模式 + 单本/批量入口）；`Book` 新增一个标记字段
**不涉及：** 封面相关任何能力；线下管线 `tools/ai_intro/` 与 `ai-book-intro` skill（保持原样）；已有 2897 条 AI介绍 存量（不重写）

## 背景与问题

补全功能目前是「查豆瓣 / Open Library / Goodreads，补出版社、页数、作者、图书简介、作者简介」。
用户提出四件事：① 两个页面入口背后应共用一个原子功能，避免重复代码；
② 简介不再用 Open Library 查（其它字段仍用）；③ 搜索补完仍有空缺时自动用 AI 补，
AI 补全同时也是独立功能（单本 + 批量，与原有入口并列）；④ 配置页可填 AI endpoint 与密钥，支持百炼等国内平台。

## 代码事实（实测）

**入口实际是 3 个，不是 2 个**：

| 入口 | 位置 |
|---|---|
| 批量补全纸质书信息 | `AuthorPublisherMaintenanceView.swift:660`（视图 `DataMaintenanceView` 定义在同文件 `:7`） |
| 编辑页 智能补全缺失信息 | `EditBookView.swift:553`（另有微信读书书的外部源分支 `:507`） |
| **添加书页 智能补全书籍信息** | `AddBookView.swift:332` |

**共用层已存在一半**：三处都调 `ISBNLookupService.smartFill`（`:626`）。查询扇出不重复，
**重复的是它的上下两层**，且语义已经漂移：

| 层 | 批量 | 编辑页 | 添加页 |
|---|---|---|---|
| needs 判定 | 读 `Book`，用 `needsBookDescriptionRefresh`（认豆瓣折叠残留） | 读 `@State`，用 `Book.descriptionNeedsRefresh` | 读 `@State`，用 `bookDescription.isEmpty`（**不认折叠残留**） |
| apply 写回 | 写 `book.*` | 写 `@State` + 类型转换 | 写 `@State`，多一层 `if needsX` 守卫 |
| 日期解析 | `parsePublishDate` | `parsePublishDateString` | 不解析 |
| 本地作者简介 | 全库建字典 | `findLocalAuthorDescription(for:)` | 第三种写法 |

三处当初没能共用的**真实原因**是数据源不同：批量的源是 `Book` 模型，两个表单页的源是 `@State` 字符串。

**Open Library 到底供什么**（决定去掉简介的改动面）：

- ISBN 路径 `lookupFromOpenLibrary` 为拿简介**额外打一次 Works API**（`:294` `fetchOpenLibraryDescription`）；
  作者简介硬编码 `nil`（`:305`）
- 作者简介只来自**书名搜索**路径（`fetchOpenLibraryAuthorBio`，`:894-896`）
- Goodreads 从不供作者简介（`:483` 为 `nil`）；豆瓣两者都供（`:191`）

**既有文案已过期**：`AuthorPublisherMaintenanceView.swift:152` 写「从豆瓣 → Open Library → Google Books 查询补全」，
但 Google Books 早已从 `smartFill` 移除（`:649-650` 注释：800+ 本实测 0% 命中）。

**AI 相关代码为零**，全新建。`KeychainService` 已有 `save/loadString` 与两个 key 常量（`:70`/`:73`）可照抄模式。

## 方案

### 组件边界（新增 6 个文件，均不 import SwiftUI / SwiftData，可纯单测）

| 文件 | 职责 |
|---|---|
| `Services/Enrichment/BookDraft.swift` | 中立值对象 + `missingFields` **唯一**判定实现 |
| `Services/Enrichment/EnrichmentCoordinator.swift` | **原子功能**：`enrich(draft, options) async -> Outcome`，串两阶段 |
| `Services/Enrichment/AIEnrichmentService.swift` | OpenAI 兼容客户端 + 检索/生成两模式 |
| `Services/Enrichment/AIIntroContract.swift` | 四节契约 prompt 构建 + **纯函数校验闸门** |
| `Services/AIConfig.swift` | endpoint / model / 联网方式（UserDefaults）+ key（Keychain） |
| `Views/Settings/AISettingsView.swift` | 配置页（`ImportExportView` 第 5 个 NavigationLink） |

协调器只认 `BookDraft`，两端各配 adapter（`BookDraft(book:)` / `BookDraft(form:)`），
让批量走后台 context、表单页走 `@State` 各自不受影响，而判定与写回只有一份。
本地作者简介复用统一为入参 `localAuthorBio: (String) -> String?`（批量传全库字典闭包，表单页传单次查询）。

### 字段归属矩阵（硬约束）

| 字段 | 搜索阶段 | AI 检索模式 | AI 生成模式 |
|---|---|---|---|
| 书名 / 作者 / 出版社 / 页数 / 定价 / 出版日期 / 译者 | ✅ 豆瓣→OL→Goodreads | ❌ | ❌ |
| 图书简介 | ✅ 豆瓣 + Goodreads（**OL 退出**） | ✅ 需来源 URL | ❌ |
| 作者简介 | ✅ 豆瓣 + 本地库（**OL 退出**） | ✅ 需来源 URL | ❌ |
| AI介绍 | ❌ | ❌ | ✅ 四节契约 |
| 封面 | 现有 `CoverFetchService`，本次不动 | ❌ | ❌ |

**AI 绝不写事实字段。** 理由：LLM 编造的页数/出版社与真值外观一致、事后无法分辨，
而搜索源的值至少可追溯到豆瓣/Goodreads 页面。

OL 退出简介的连带清理：`fetchOpenLibraryDescription`、`searchOpenLibraryByTitle`、
`searchOpenLibraryByTitleOnce`、`fetchOpenLibraryAuthorBio` 四个函数全部变成死代码，一并删除
（`smartFill` 的 `:744-764` 整块只为简介存在）。**红利**：每本少一次 Works API 往返。
**后果**：作者简介搜索来源只剩豆瓣 + 本地库，英文书基本改由 AI 检索模式承担 —— 用户已确认接受。

### AI 子系统

**配置**：endpoint（**强制 https**）、API Key（Keychain 新 key `com.personallibrary.ai.apikey`）、
模型 ID（手填 + 「拉取可用模型」按钮调 `GET /models`，拉不到退回手填）、
联网方式三选（无 / `enable_search` 参数 / 模型名 `:online` 后缀）、连通性测试按钮。
温度、超时、重试次数硬编码不暴露。

联网方式做成三选而非布尔开关，是因为各平台机制不统一（百炼用 `enable_search`，OpenRouter 用 `:online`，
DeepSeek 官方 API 不支持）。**一个 HTTP 客户端即可覆盖，无需按平台写适配器。** 选「无」时检索模式不可用。

**检索模式**（图书简介 / 作者简介）：要求返回 JSON `{book_description, author_description, sources, status}`。
**`sources` 为空即整条丢弃、字段留空** —— 这是「绝不乱编」唯一可验证的防线。
照线下契约要求核对作者一致，只有书名对得上视为没查到。查不到则 `status: insufficient` + 留空。

**生成模式**（AI介绍）：四节契约 = 现有 `PROMPT.md` 的导语 + 三节，**新增第四节「推荐与读后感」**，
原料加进 `rating` 与 `notes`（有则用，无则写通用推荐）。篇幅 900–1200 字。
闸门：四节结构、禁 markdown / 模板句 / 占位符 / 截断痕迹、与 `bookDescription` 连续重合 ≥40 字判抄袭、书名与首句匹配。
不过闸门 → 重试 1 次 → 仍不过则留空 + 记日志，不写半成品。

**契约双份的处理**（项目已因「同一件事两套实现」踩坑三次）：Python `validate.py` 继续服务线下管线，
两者是**包含关系而非竞争关系** —— Python 闸门 600–1400 字 / ≥2 节，Swift 四节 900–1200 字落在其内部，
即 App 产出必然也过 Python 闸门。这一点写进两边文件头互相指名；
《平面国》标杆样板与反面样板抽为共享 fixture，两边测试必须给出相同判定。

### 入口全景（5 个触发点，共用 1 个原子功能）

| 入口 | 位置 | 阶段 |
|---|---|---|
| 智能补全书籍信息 | 添加书页 | 搜索 → 仍缺 → AI |
| 智能补全缺失信息 | 编辑页 | 微信读书前置 → 搜索 → 仍缺 → AI |
| 批量补全纸质书信息 | 数据维护 | 循环：每本 搜索 → 仍缺 → AI |
| **新** AI 补全 | 编辑页（与智能补全并列） | 只跑 AI 阶段 |
| **新** 批量 AI 补全 | 数据维护（与批量补全并列） | 循环，只跑 AI 阶段 |

差异全部由 options 表达：

```swift
struct EnrichmentOptions {
    var runSearchPhase: Bool            // AI 专用入口置 false
    var runAIPhase: Bool                // AI 未配置时自动 false
    var localAuthorBio: (String) -> String?
}
```

AI 未配置时前三个入口静默跳过 AI 阶段（行为等同今天），两个 AI 专用入口置灰并提示去配置。
`:152` 的过期文案一并改对（去掉 Google Books、写明 AI 兜底）。

**批量 AI 补全的候选范围**：**不限载体** —— 电子书/有声书同样需要 AI介绍，
而既有「批量补全纸质书信息」限 `bookType == .paper` 是因为微信读书的书走同步补全，这个限制不适用于 AI。
条件为「未归档 且 `lastAIEnrichmentDate == nil` 且（AI介绍 为空 或 图书简介为空 或 作者简介为空）」。
既有「批量补全纸质书信息」的 `.paper` 限制与 `lastEnrichmentDate == nil` 条件**保持不变**。

### 运行时行为

- 搜索阶段**保持顺序 + 每本 2s 不变**（PROJECT_NOTES §4.6：并发导致过热，已回退到此节奏）
- AI 阶段不加额外 sleep（LLM 本身慢），但**并发固定为 1**，同样依 §4.6 并避免平台限流
- 取消复用现有 `withTaskCancellationHandler` + detached task；URLSession async API 原生响应取消
- 每本处理完**立即 save**（沿用现有做法，中断不丢已完成的）
- 复用 `BatchEnrichmentState.shared`，`BackgroundCover` 继续自动让路
- 批量页显示 已处理/总数 + **累计 token**，跑飞了可见

错误分层（关键是区分「跳过这本」与「中止整批」）：

| 情况 | 行为 |
|---|---|
| AI 未配置 | 跳过 AI 阶段，不报错 |
| 网络失败 / 超时 | 记日志，跳过这本，继续下一本 |
| 401 / 403 | **立即中止整批** + 弹窗（否则 2900 本全部失败刷屏） |
| 429 | 退避重试 1 次；仍 429 则中止整批 |
| 生成不过闸门 | 重试 1 次 → 留空 |
| 检索模式无 `sources` | 留空，不重试 |

### 新增字段

`Book.lastAIEnrichmentDate: Date?`，与现有 `lastEnrichmentDate`（`Book.swift:89`）对称。
不加则「AI 查过但确实查不到」的书每次批量都被重查，2900 本规模下是真实浪费。
optional Date 属 SwiftData 轻量迁移，Schema 不变、无需 migration plan（v0.64 加 `bookIntroduction` 同法，有成功先例）。
不进 Excel 导出（内部标记，非用户数据）。

## 关键决策（用户拍板记录）

1. **AI 只写文字类三字段，事实字段一律只由搜索源填。**
2. **AI介绍 是生成而非检索**的产物（介绍 + 分析 + 推荐 + 读后感，主观色彩强）。
3. **形态扩展为四节**：现有三节 + 新增「推荐与读后感」，吃进评分与备注。
   全库将出现两种形态并存（存量 2897 条三节、新写四节），**存量不重写**。
4. **图书简介 / 作者简介 由 AI「代笔」但不是生成，而是 AI 搜索，绝不乱编** →
   落地为「必须返回来源 URL，无来源即留空」。
5. **批量补全跑完搜索自动接 AI，不弹确认**；添加新书同样自动接。
6. 架构取**中立值对象 + 两个 adapter**（否决了「统一到 Book 模型」与「只做 AI 不动重复」）。
7. 模型配置取**手填 ID + 拉取可用模型按钮**（否决了内置预设清单、检索/生成分开配两个模型）。
8. 只支持 https 云端 endpoint（不支持本地 Ollama）；温度/超时/重试不暴露给用户。

## 验证标准

- `BookDraft.missingFields` 真值表：折叠残留 / 空串 / `"未知作者"` / `totalPages == 0` 均算缺
- adapter 往返不丢字段；**两个日期解析函数合并后，两边原有输入格式都仍能过**
  （§4.8 通则二：删掉看似冗余的分支前先证明它冗余）
- `AIIntroContract` 闸门：标杆样板必须过、反面样板必须被打回且原因准确；
  篇幅造越界数据 899/900/1200/1201（§4.8 通则三）；抄袭判定**删标点不能绕过**；
  书名匹配容忍版本装饰、繁简差异、补入标点
- 检索模式 sources 防线：有 → 采用，无 / 空数组 → 留空
- 错误分层：401 中止整批、网络失败跳过继续
- OL 退出简介的回归：「OL 有简介、豆瓣没有」时简介**不被** OL 填充，但出版社/页数**仍被** OL 填充
- HTTP 抽成 `AICompletionClient` 协议以便注入 mock（照 `MockWeReadDataSource` 成例），真 LLM 调用不进单测
- `xcodebuild build` + `test` 全绿。⚠️ 项目在 `~/Documents`（iCloud 目录）下 xcodebuild 会挂死，**必须复制到 `/tmp` 跑**
- 五个入口在模拟器/真机各走一遍
- **用真 key 手跑 3–5 本，人工读一遍生成的四节文章** —— 闸门挡不住「格式全对但内容空洞」，此步不可省

## 交付物

- 6 个新文件（上表）
- 改动：`ISBNLookupService`（OL 退出简介 + 删 4 个死函数）、`EditBookView`、`AddBookView`、
  `AuthorPublisherMaintenanceView`（含 `:152` 文案）、`ImportExportView`、`Book`（+1 字段）
- 测试：上述验证标准对应的用例
- `PROJECT_NOTES.md` 第 2 节功能表 + 第 6 节版本时间线更新；README 功能特性更新

## 范围红线（本次不做）

| 不做 | 理由 |
|---|---|
| 把已有 2897 条三节稿件重写成四节 | 两种形态并存已获接受；存量不动，只补空缺 |
| AI 写事实字段 | 决策 1 |
| 本地 Ollama / http endpoint | 只需云平台 |
| 温度 / 超时 / 重试 暴露给用户 | 避免配置页变旋钮墙 |
| 多平台预设清单、自动填 endpoint | 会过期；已选手填 + 拉取 |
| 改造或退役 `tools/ai_intro/` | 它能联网查证且有人工抽查，保持原样 |
| AI 结果的人工审核队列 / diff 预览 | 超出本次范围 |
| token 预算硬熔断 | 只显示累计用量 |
| 封面相关任何 AI 能力 | 与本次目标无关 |

## 已知风险

1. **检索模式依赖模型联网能力**。配了不支持联网的平台（如 DeepSeek 官方 API）又选了「无」，
   检索模式不可用；若选错联网方式，模型可能凭参数记忆编造 —— `sources` 防线是唯一拦截，
   但无法验证 URL 内容是否真支持那段文字。
2. **两种 AI介绍 形态并存**会让全库观感不一致，直到某天把存量也重跑一遍。
3. **契约双份**（Python / Swift）仍有漂移风险，共享 fixture 只能让漂移被发现、不能阻止。
4. **成本**：全库生成约 400–500 万输出 token。不做硬熔断，依赖用户看进度条。
