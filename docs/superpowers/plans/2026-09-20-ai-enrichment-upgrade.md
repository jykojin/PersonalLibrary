# 图书信息补全升级 Implementation Plan

> 本计划实现 `2026-09-19-ai-enrichment-upgrade-design.md` 的 2026-09-20 最终修订。步骤使用复选框跟踪；实现按 TDD 顺序推进。任何需求变化先回写 spec，再改代码。

**Goal:** 建立一个统一的单本补全 Interface，按豆瓣 → Goodreads → Open Library 补普通字段，再由带证据闸门的 AI 检索补余下空值并生成 AI简介；添加、编辑、批量和微信读书同步全部复用。

**Architecture:** `EnrichmentCoordinator` 是外部深模块，输入/输出均为值类型，不直接保存 SwiftData。普通来源和 AI 是两个内部 seams，分别注入生产 Adapter 与测试 Adapter。页面和后台任务只负责 `Book`/表单 ↔ `BookDraft` 转换和持久化。

**Tech Stack:** SwiftUI、SwiftData、Swift Concurrency、URLSession、Security/Keychain、Swift Testing、XcodeGen，iOS 17+。

**实施状态：** 主体功能已完成。本文前半保留原始 TDD 任务拆解作为决策历史；文末“实际实施记录”是当前代码、测试与部署的权威索引。

## Global Constraints

- UI 文案使用简体中文。
- 只填缺失字段，不覆盖已有字段；AI 不写 ISBN、封面或用户阅读数据。
- 所有真实远程调用必须位于可替换 Adapter 后；单元测试不依赖外网。
- 普通来源顺序固定：豆瓣 → Goodreads → Open Library。
- Open Library 永不供应图书简介和作者简介。
- AI 采用的每个字段必须有自己的来源 URL；AI简介也必须基于联网调研来源。
- API Key 只存 Keychain；禁止写入日志、UserDefaults、测试 fixture 或 git。
- 批量并发固定为 1；保留豆瓣 5 秒全局限速和每本 2 秒节奏。
- 不修改 `tools/ai_intro/`、`.claude/skills/ai-book-intro/`、封面模块或已有 AI简介存量。
- 不顺手重构相邻功能。
- 新增 Swift 文件后执行 `cd PersonalLibrary && xcodegen generate`。
- 仓库位于 Documents/iCloud 路径，完整 build/test 使用 `/tmp` 副本，避免原路径挂死。

## 2026-09-20 真机反馈修复

- [x] 复现百炼强制搜索仍无法读取 drand 原始 API，并确认旧探针会等待普通补全的 90 秒超时。
- [x] 先增加失败测试：百炼探针不依赖随机信标，必须同时具备搜索注入 token 与合法外部来源；连接探针可使用独立短超时。
- [x] 百炼改用适合 Chat Completions 搜索能力的双重证据探针；其他平台保留随机信标。
- [x] 连接测试增加 30 秒全流程硬截止，正常 AI 补全保留 90 秒单次请求超时。
- [x] 区分 Endpoint、认证、模型和联网证据错误。
- [x] 根据安全审查将百炼专用证据绑定到官方 Endpoint，并拒绝 Endpoint 敏感查询凭据。
- [x] 完整 build/test、代码审查、安全审查和真机覆盖安装。

## 2026-09-20 AI 响应时间优化

- [x] 先增加失败测试：AI 请求达到阶段时间预算后取消当前请求并返回可重试超时。
- [x] 增加失败测试：事实字段已完成、AI简介阶段超时时保留已验证字段。
- [x] 事实检索使用 60 秒短预算并关闭深度思考；按用户修订，AI简介百炼显式开启深度思考，并为每次生成使用独立的 600 秒阶段和 HTTP 请求时限。
- [x] 设置页提示模型选择会影响联网检索速度，并优先推荐平台默认模型。
- [x] 在模拟器运行 AI 定向测试、完整单元/集成测试和关键 UI 流程。

## Verification Commands

在 `/tmp/PersonalLibrary-ai-enrichment` 工作副本内执行：

```bash
cd PersonalLibrary
xcodegen generate
xcodebuild -scheme PersonalLibrary \
  -project PersonalLibrary.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-AI-DerivedData build
xcodebuild -scheme PersonalLibrary \
  -project PersonalLibrary.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-AI-DerivedData test
```

---

## Phase A — 建立统一数据与普通检索

### Task 1: 建立基线与测试文件

**Files**

- Create: `PersonalLibrary/PersonalLibraryTests/EnrichmentFixtures.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/BookDraftTests.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/EnrichmentCoordinatorTests.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/ISBNLookupEnrichmentTests.swift`

- [ ] 记录当前 `git status`，确认用户改动并避免覆盖。
- [ ] 在 `/tmp` 副本运行现有 build/test，记录基线测试数量和任何既有失败。
- [ ] 建立仅含静态字符串/JSON/HTML 的测试 fixture 类型，禁止测试访问豆瓣、Goodreads、Open Library 或 AI 平台。
- [ ] 建立三个空测试 Suite，使后续红灯都落在独立文件而不是继续扩大 `PersonalLibraryTests.swift`。
- [ ] 重生成 Xcode 工程，确认新测试文件被 target 收录。

**Done when:** 基线明确，新测试文件能编译，尚未改变产品行为。

### Task 2: `BookDraft`、字段枚举和唯一缺失判定

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/BookDraft.swift`
- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/EnrichmentTypes.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Models/Book.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/BookDraftTests.swift`

**Interface**

- `BookDraft`: 补全相关字段的 `Sendable` 值类型。
- `EnrichmentField`: 可补字段枚举。
- `EnrichmentMode`: `.full`、`.aiOnly`、`.aiIntroductionOnly`。
- `EnrichmentOutcome`: 最终 draft、字段变化、来源状态、终止原因、token usage。
- `BookDraft.missingFields`: 全系统唯一缺失判定。

- [ ] 先写缺失真值表测试：空白、未知作者、0/负页数、折叠简介、已有简介、已有 AI简介。
- [ ] 写“非空值不可被候选覆盖”的合并测试。
- [ ] 实现 `BookDraft` 和字段枚举，让测试转绿。
- [ ] 抽出统一出版日期解析，覆盖 `yyyy-MM-dd`、`yyyy-MM`、`yyyy` 及非法日期。
- [ ] 给 `Book` 增加 optional `lastAIEnrichmentDate`；测试默认 nil 和可设置。
- [ ] 保持 `Book.needsEnrichment` 对外行为兼容，内部允许委托给共享判定但不能改变现有批量范围。

**Done when:** 页面和数据库之外已有完整、纯值类型的补全模型；所有缺失语义只定义一次。

### Task 3: `Book` Adapter 与表单 Adapter 契约

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/BookDraft+Book.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/BookDraftTests.swift`

**Interface**

- `BookDraft.init(book:)`
- `EnrichmentOutcome.apply(to book: Book)` 或等价的单一写回函数。

- [ ] 先写 Book → Draft → Book 往返测试，覆盖全部字段。
- [ ] 写“只应用 Outcome 变化，不覆盖调用后被用户编辑的新值”的冲突测试；写回需基于字段原值比较。
- [ ] 实现 SwiftData Adapter；纯 `BookDraft` 文件不 import SwiftData。
- [ ] 明确添加/编辑表单 Adapter 只负责组装和拆解值，不重复 missing 判定。

**Done when:** 批量和微信读书可共用 Book Adapter；页面只需极薄的状态映射。

### Task 4: 普通来源 port、候选值和可测试 HTTP seam

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/BookMetadataLookup.swift`
- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/HTTPDataClient.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Services/ISBNLookupService.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/ISBNLookupEnrichmentTests.swift`

**Internal seams**

- `BookMetadataLookup.lookup(draft:missingFields:) async -> MetadataLookupOutcome`
- `HTTPDataClient.data(for:) async throws -> (Data, HTTPURLResponse)`
- Production Adapter 使用 `URLSession`；测试 Adapter 返回固定响应或错误。

- [ ] 先写 Adapter 驱动测试：网络错误、HTTP 非 200、超大响应、取消都可区分。
- [ ] 把 `URLSession.shared` 从可测试查询路径移到 production Adapter。
- [ ] 保留现有 `lookup(isbn:)` 兼容入口，扫码封面流程不在本任务改写。
- [ ] `LookupSourceStatus` 扩展为可区分 retryable failure、fatal failure、validation rejected、cancelled；调整旧测试。

**Done when:** 普通检索不依赖真实网络即可完整测试，错误不再全部坍缩为 `notFound`。

### Task 5: 豆瓣单页解析、译者提取和身份核对

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Services/ISBNLookupService.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Services/DoubanDescriptionFetcher.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/ISBNLookupEnrichmentTests.swift`
- Fixture: `PersonalLibrary/PersonalLibraryTests/EnrichmentFixtures.swift`

- [ ] 先添加豆瓣 fixture：单译者、多译者、译者纯文本、无译者、折叠/完整简介并存。
- [ ] 写译者输出统一为 `", "` 的失败测试。
- [ ] 写同一 HTML 一次解析全部字段的测试。
- [ ] 写书名相同但作者不同必须拒绝的测试。
- [ ] 提取共享豆瓣页面解析函数，删除 ISBN 路径和简介抓取器之间的重复解析。
- [ ] 标题搜索只采用身份核对通过的结果，不再无条件取建议列表第一本。
- [ ] 保持 `DoubanRateLimiter` 全局 5 秒策略不变。

**Done when:** 豆瓣一次页面请求能提供全部允许字段和译者，并能拒绝明显串书结果。

### Task 6: 固定来源顺序与 Open Library 禁简介

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Services/ISBNLookupService.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/ISBNLookupEnrichmentTests.swift`

- [ ] 用三个固定 Adapter 写红灯测试，断言调用顺序严格为豆瓣 → Goodreads → Open Library。
- [ ] 写逐字段首个合法值胜出、低优先级只补剩余空值的测试。
- [ ] 写有 ISBN 但全部 ISBN 查询未命中后，按同一来源顺序执行书名+作者回退的测试。
- [ ] 改 Goodreads 结果映射；只采用实际存在的结构化字段。
- [ ] Open Library ISBN 路径删除 Works description 请求，作者 Bio 请求删除。
- [ ] 保留 Open Library 书名搜索的事实字段；明确把两类简介清为 nil。
- [ ] 删除 `smartFill` 中 Google Books 引用；保留扫码 `lookup(isbn:)` 所需兼容逻辑，直到该入口另案统一。
- [ ] 更新所有过期的“Google Books”补全文案和旧测试中的“四个源”注释。

**Done when:** 普通检索顺序、字段归属和回退路径都由测试锁定，Open Library 无法通过任何路径写简介。

---

## Phase B — AI 配置、网络和证据闸门

### Task 7: AI 配置模型与安全存储 Adapter

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/AIConfig.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Services/KeychainService.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/AIConfigTests.swift`

**Interfaces**

- `AIPlatformPreset`: 百炼、OpenAI、DeepSeek、OpenRouter、自定义。
- `AISearchStrategy`: 平台需要的联网参数策略。
- `AIConfig`: endpoint、model、strategy、可用性判定。
- `AIConfigStore`: production 使用 UserDefaults + Keychain，测试使用内存 Adapter。

- [ ] 先写百炼默认 endpoint 和推荐模型测试。
- [ ] 写平台切换、用户自定义 endpoint/model、配置缺项判定测试。
- [ ] 写 API Key 不进入 UserDefaults 的测试。
- [ ] 新增 `KeychainService.aiApiKey` 常量并实现 production store。
- [ ] 具体推荐模型 ID 在实现当日按供应商官方文档核对后写入 preset；不依赖模型列表调用成功才能启动设置页。

**Done when:** 配置可纯测试，敏感值与普通设置严格分离。

### Task 8: AI endpoint 安全策略

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/AIEndpointPolicy.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/AIConfigTests.swift`

- [ ] 先写拒绝 http、URL credentials、fragment、localhost、环回、私网、链路本地、IPv6 ULA、数值编码 IP 的测试。
- [ ] 写预设百炼/OpenAI/DeepSeek/OpenRouter endpoint 放行测试。
- [ ] 写 path 拼接测试：endpoint 有/无 `/v1`、尾斜杠时正确生成 `/models` 与聊天补全 URL。
- [ ] 写跨 host 重定向重新校验且不泄露 Authorization 的测试。
- [ ] 实现策略并在所有 AI 请求入口统一调用。

**Done when:** 自定义 endpoint 不会把密钥发送到本地/私网目标，所有请求共用同一策略。

### Task 9: OpenAI 兼容 Client、模型列表与错误分类

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/AICompletionClient.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/AICompletionClientTests.swift`
- Fixture: `PersonalLibrary/PersonalLibraryTests/EnrichmentFixtures.swift`

**Interface**

- `listModels(config:) async throws -> [AIModelOption]`
- `complete(request:config:) async throws -> AICompletionResponse`

- [ ] 先写 `/models` 正常/空列表/无效 JSON 测试。
- [ ] 写百炼 `enable_search`、OpenRouter `:online`、OpenAI web-search 参数和不支持联网策略的请求体测试。
- [ ] 写 Bearer header、Content-Type、超时、最大响应字节数测试。
- [ ] 写 usage 输入/输出/总 token 解码测试；usage 缺失时按 unknown 处理而非伪造 0。
- [ ] 写 401/403、429 + `Retry-After`、5xx、超时、取消和无效响应测试。
- [ ] 实现 429 一次退避重试；其他普通网络错误不在 Client 内无限重试。

**Done when:** 所有平台差异和 HTTP 错误被 Client 吸收，上层只处理统一错误。

### Task 10: AI 字段检索契约与证据验证

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/AIEnrichmentContract.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/AIEnrichmentContractTests.swift`

- [ ] 先写 prompt 测试：只请求 missing fields，明确禁止 ISBN/封面/覆盖已有值。
- [ ] 写逐字段 sources 解析与采用测试。
- [ ] 写 sources 缺失、空数组、非法 URL、AI endpoint 自身 URL 时拒绝测试。
- [ ] 写标题/作者身份不符导致整次拒绝的测试。
- [ ] 写页数、价格、出版日期、空字符串等字段级验证测试。
- [ ] 写完整 JSON 之外夹带说明文字、截断 JSON、未知字段的行为测试。
- [ ] 实现纯函数 `validateRetrievalResponse`，返回已验证候选和明确拒绝原因。

**Done when:** 模型输出只有通过证据和类型闸门的字段才能进入 Draft。

### Task 11: AI简介写作方向与纯函数闸门

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/AIIntroductionContract.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/AIIntroductionContractTests.swift`
- Fixture: `PersonalLibrary/PersonalLibraryTests/EnrichmentFixtures.swift`

- [ ] 建立按四个方向灵活写作的正向 fixture，以及模板化、虚构对比、抄原文、Markdown、截断等反向 fixtures。
- [x] 写精炼有效正文可低于建议目标、3000 接受且 3001 拒绝的非空白字符边界测试。
- [ ] 写四个 section 的协议结构测试；内容方向不做逐项关键词覆盖检查。
- [ ] 写书名版本装饰、标点和繁简容忍测试。
- [ ] 写去标点后连续重合 40 字的抄袭测试。
- [ ] 写无对比书、正文自然出现其他书名，以及 `comparison_books` 缺来源、理由无关、类型错误或对象残缺时仍接受有效正文的测试。
- [ ] 构建 prompt：综合情况；主题/特点/人物/写法；体验/感受/意义；读后感/主题对比/扩展阅读。
- [ ] 实现纯函数验证器，输出可反馈给第二次生成的失败原因。

**Done when:** 正向 fixture 稳定通过，各反向 fixture 被准确拒绝；不改线下 Python 管线。

### Task 12: AI 智能补全深模块

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/AIEnrichmentService.swift`
- Create: `PersonalLibrary/PersonalLibraryTests/AIEnrichmentServiceTests.swift`

**Interface**

- `AIEnriching.enrich(draft:targets:) async -> AIEnrichmentOutcome`

- [ ] 先用 mock `AICompletionClient` 写检索 → 合并 → AI简介生成的顺序测试。
- [ ] 写 `.aiOnly` 只补空值测试。
- [ ] 写 `.aiIntroductionOnly` 不请求事实字段测试。
- [ ] 写 AI简介第一次失败后携带原因重试一次、第二次失败留空测试。
- [ ] 写无来源时字段留空且 AI简介不伪造的测试。
- [ ] 写 token usage 累加测试。
- [ ] 写 auth、rate limit、retryable network、validation rejection、cancelled 的统一 Outcome 测试。
- [ ] 实现 AI 模块；不直接读 UserDefaults/Keychain，由调用方注入已解析配置和 Client。

**Done when:** AI 全部复杂行为位于一个小 Interface 后，调用者不需要理解 prompt、JSON 或平台差异。

---

## Phase C — 总协调器与产品入口

### Task 13: `EnrichmentCoordinator` 串联普通检索与 AI

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Services/Enrichment/EnrichmentCoordinator.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/EnrichmentCoordinatorTests.swift`

- [ ] 先写 `.full` 测试：本地作者简介 → 普通来源 → AI 检索 → AI简介。
- [ ] 写 AI 未配置时 `.full` 仍返回普通来源结果、AI 状态为 skipped 测试。
- [ ] 写 `.aiOnly` 不调用普通来源测试。
- [ ] 写 `.aiIntroductionOnly` 只调用 AI简介生成测试。
- [ ] 写普通来源填过的字段不会再向 AI 请求，AI 也不能覆盖测试。
- [ ] 写任一阶段取消后不继续下一阶段测试。
- [ ] 写 Outcome 来源状态、字段变化、终态和 token 汇总测试。
- [ ] 实现唯一公开 `enrich` Interface。
- [ ] 将旧 `SmartFillResult` 调用逐步迁移；迁移完成前用兼容 Adapter，完成后删除重复结构和无调用函数。

**Done when:** 删除协调器会迫使所有入口重新实现相同流程，证明模块具有足够 Depth 和 Leverage。

### Task 14: AI 设置页

**Files**

- Create: `PersonalLibrary/PersonalLibrary/Views/Settings/AISettingsView.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Views/Settings/ImportExportView.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/AIConfigTests.swift`

- [ ] 添加“AI 智能补全”设置入口。
- [ ] 平台选择默认百炼；切换预设时展示推荐 endpoint、模型和联网方式。
- [ ] API Key 使用 `SecureField`，保存前 trim，不在重新打开页面时明文展示。
- [ ] 添加“读取模型列表”，成功后 Picker 选择，失败后保留手填模型 ID。
- [ ] 添加“测试连接”；区分 endpoint、认证、模型和联网能力错误。
- [ ] 对 DeepSeek 等不支持联网的组合显示明确说明，并让 AI 补全不可用。
- [ ] 增加自动同步会消耗 token、评分/备注可能作为 AI简介原料发送的隐私提示。

**Done when:** 用户无需修改代码即可配置百炼或其他兼容平台，并能在运行前知道配置是否支持联网。

### Task 15: 添加页 Adapter 与两个按钮

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/AddBookView.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/EnrichmentEntryIntegrationTests.swift`

- [ ] 先写纯 Adapter 测试：表单 → Draft → Outcome → 表单，覆盖译者、日期、描述和 AI简介。
- [ ] 添加 `translator`、`publishDate` 和 `bookIntroduction` 必需状态/编辑区域，确保补全结果能保存进新书。
- [ ] 现有“智能补全书籍信息”改调 `.full`。
- [ ] 并列新增“AI智能补全”，调用 `.aiOnly`；AI 未配置时置灰并提供设置提示。
- [ ] 两按钮共享 loading、取消和结果展示；防止重复点击并发启动。
- [ ] 保留 ISBN 扫描、重复检查和封面下载现状。
- [ ] `saveBook` 写入新增的译者、出版日期和 AI简介状态。

**Done when:** 添加页不再自行决定来源和缺失规则，AI简介能被看见、编辑并保存。

### Task 16: 编辑页 Adapter 与两个按钮

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/EditBookView.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/EnrichmentEntryIntegrationTests.swift`

- [ ] 现有按钮改调 `.full`，并列新增“AI智能补全”调 `.aiOnly`。
- [ ] 保留微信读书先提供已有数据的行为，把后续统一交给 Coordinator。
- [ ] 删除页面内重复日期解析、needs 判定和来源拼接。
- [ ] 结果展示包含字段变化、各来源状态、AI 验证拒绝原因和 token。
- [ ] 完成一次后按钮仍可再次触发，不再被 `fillResult != nil` 永久替换。
- [ ] 保存仍只在用户点“保存”时写表单字段，补全过程不提前改 `Book`，微信读书自身同步字段除外。

**Done when:** 编辑页与添加页通过相同 Interface 获得相同行为，只有 Adapter 不同。

### Task 17: 两种批量入口

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Views/Settings/AuthorPublisherMaintenanceView.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/EnrichmentBatchTests.swift`

- [ ] 抽出批量候选纯函数并测试：普通批量仅纸质书；AI 批量覆盖全部载体。
- [ ] 现有普通批量逐本调用 `.full`。
- [ ] 新增“批量 AI 智能补全”，逐本调用 `.aiOnly`。
- [ ] 两种批量共用一个 runner；保留单一后台 `ModelContext`、顺序执行、取消传播、逐本保存和 `BatchEnrichmentState`。
- [ ] 普通批量只在搜索阶段达到终态时写 `lastEnrichmentDate`；临时网络失败/取消不写。
- [ ] AI 阶段按 spec 终态语义写 `lastAIEnrichmentDate`。
- [ ] UI 增加成功、无资料、失败、验证拒绝和累计 token；401/403 或最终 429 中止整批。
- [ ] 删除批量内重复字段 apply、日期解析和本地作者判定，只保留 Adapter/缓存构建。

**Done when:** 两个批量按钮只是候选范围和 mode 不同，单书处理完全一致。

### Task 18: 微信读书自动同步接入

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Services/WeReadSyncService.swift`
- Test: `PersonalLibrary/PersonalLibraryTests/WeReadAIEnrichmentTests.swift`

- [ ] 用 mock WeRead 数据源 + mock Coordinator 写平台书缺 AI简介自动调用 `.aiIntroductionOnly` 的测试。
- [ ] 写用户导入书调用 `.full`，普通来源与 AI简介都可补的测试。
- [ ] 写已有 AI简介不调用 AI、不覆盖的测试。
- [ ] 写历史 `wereadEnrichedDate != nil` 但 AI简介为空仍进入 AI 队列的测试。
- [ ] 写 AI 未配置、网络失败、取消不写 `lastAIEnrichmentDate`，下次可重试的测试。
- [ ] 写终态无资料/验证拒绝写时间戳，避免每次同步重复消费的测试。
- [ ] 平台书不调用普通网页来源；用户导入书用同一 Coordinator 替换原 `CB_` 直调 `smartFill`。
- [ ] AI 处理后逐本保存，确保同步中断不丢已生成 AI简介。

**Done when:** 微信读书自动同步不再有第五套补全逻辑，并能自动生成缺失 AI简介。

---

## Phase D — 收尾、回归与交付

### Task 19: 删除兼容层和更新文案

**Files**

- Modify: `PersonalLibrary/PersonalLibrary/Services/ISBNLookupService.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/AddBookView.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/EditBookView.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Views/Settings/AuthorPublisherMaintenanceView.swift`
- Modify: `README.md`
- Modify: `PROJECT_NOTES.md`

- [ ] `rg "smartFill\("`，确认除 Coordinator/兼容测试外不再有页面或同步直接调用。
- [ ] `rg "Google Books"`，修正智能补全相关过期文案，但保留真实扫码 lookup 说明。
- [ ] 删除无调用的旧结果结构、重复日期解析和重复本地作者简介 apply 逻辑。
- [ ] 更新 README 功能、平台配置、安全说明和测试数量。
- [ ] 更新 PROJECT_NOTES 功能表、版本时间线、关键设计决策和已知限制。
- [ ] 不修改线下 AI 管线和封面代码。

**Done when:** 搜索结果证明所有产品入口只经过统一模块，文档与实际来源一致。

### Task 20: 全量验证与人工验收

- [ ] 在 `/tmp` 干净副本运行 `xcodegen generate`。
- [ ] 运行全量 build，必须 `BUILD SUCCEEDED`。
- [ ] 运行全量 test，必须无新增失败。
- [ ] 模拟器走添加页 full/AI-only、编辑页 full/AI-only、普通批量、AI 批量和停止流程。
- [ ] 使用真实百炼 Key 测试模型列表和连接。
- [ ] 真机同步一本文读平台书和一本用户导入书，确认缺失 AI简介自动生成。
- [ ] 人工抽查至少 5 本：中文小说、英文小说、非虚构、作者同名风险书、资料不足书。
- [ ] 对每本核对事实字段来源、人物与情节、相似书比较和推荐理由；无资料时应留空。
- [ ] 检查 token 统计、401/429 提示、取消后重试和时间戳候选行为。
- [ ] `git diff --check` 和 `git diff` 自审，确认无 API Key、无越界改动、无生成垃圾。

**Done when:** spec 的验证标准全部有自动或人工证据，才允许交付。

## Suggested Commit Boundaries

1. `test: establish enrichment fixtures and draft contract`
2. `refactor: add BookDraft and enrichment outcome types`
3. `refactor: make metadata lookup injectable`
4. `feat: reorder book sources and parse douban translators`
5. `feat: add AI configuration and endpoint policy`
6. `feat: add OpenAI-compatible completion client`
7. `feat: validate sourced AI metadata and AI introductions`
8. `feat: add unified enrichment coordinator`
9. `feat: connect add and edit enrichment actions`
10. `feat: add batch AI enrichment`
11. `feat: generate AI introductions during WeRead sync`
12. `docs: update enrichment behavior and verification notes`

---

## 实际实施记录（As Built）

### 1. 原子能力与调用链

产品入口统一调用 `BookEnriching.enrich(_:mode:localAuthorDescription:)`，生产实现为 `EnrichmentCoordinator`：

```text
添加 / 编辑 / 普通批量 / AI 批量 / 微信读书同步
                    │
                    ▼
           EnrichmentCoordinator
              │              │
              ▼              ▼
 SequentialBookMetadataLookup  AIEnrichmentService
 豆瓣 → Goodreads → OL        事实检索 → AI简介
              │              │
              └──────┬───────┘
                     ▼
              EnrichmentOutcome
                     │
          调用方负责表单回写或 SwiftData 保存
```

| 职责 | 生产代码 | 测试代码 |
|---|---|---|
| 单本流程编排 | `Services/Enrichment/EnrichmentCoordinator.swift` | `EnrichmentCoordinatorTests.swift` |
| 唯一缺失语义和只填空值 | `BookDraft.swift`、`BookDraft+Book.swift` | `BookDraftTests.swift` |
| 普通来源顺序与逐字段合并 | `BookMetadataLookup.swift`、`ISBNMetadataSourceAdapter.swift` | `ISBNLookupEnrichmentTests.swift` |
| 豆瓣单页解析、译者和 ISBN 凭据 | `DoubanBookPage.swift`、`DoubanDescriptionFetcher.swift` | `ISBNLookupEnrichmentTests.swift`、`EnrichmentFixtures.swift` |
| AI 事实字段证据契约 | `AIEnrichmentContract.swift` | `AIEnrichmentContractTests.swift` |
| AI简介提示词与内容闸门 | `AIIntroductionContract.swift` | `AIIntroductionContractTests.swift` |
| AI 阶段、重试、超时和 token 汇总 | `AIEnrichmentService.swift` | `AIEnrichmentServiceTests.swift` |
| OpenAI 兼容协议与联网探针 | `AICompletionClient.swift`、`HTTPDataClient.swift` | `AICompletionClientTests.swift` |
| Endpoint/SSRF 策略 | `AIEndpointPolicy.swift` | `AIConfigTests.swift` |
| 平台配置与 Keychain | `Services/AIConfig.swift`、`KeychainService.swift` | `AIConfigTests.swift` |
| UI/批量/微信同步接入 | `AddBookView.swift`、`EditBookView.swift`、`AuthorPublisherMaintenanceView.swift`、`WeReadSyncService.swift` | `EnrichmentEntryIntegrationTests.swift`、`EnrichmentBatchTests.swift`、`WeReadAIEnrichmentTests.swift`、UI tests |
| 短时后台执行 | `EnrichmentBackgroundExecution.swift`、添加/编辑/批量入口 | `EnrichmentEntryIntegrationTests.swift` |

### 2. 代码实施方式

1. `BookDraft` 是边界值对象，集中定义缺失字段；任何远程结果都先变成 Draft，再以 `fillingMissingFields` 合并，因此不会覆盖用户已有值。
2. `SequentialBookMetadataLookup` 对来源排序并按字段白名单逐一补齐。Open Library 的白名单从类型层面排除图书简介、作者简介和译者。
3. `ISBNMetadataSourceAdapter` 同时封装 ISBN 查询与书名回退；所有结果在 `.found` 前核验 ISBN、书名与作者。来源是否真正提供 ISBN 由 `ISBNLookupResult.isbnIsSourceVerified` 明确表示，避免把请求参数伪装成响应证据。
4. `AIEnrichmentService` 先请求缺失事实字段，再用本轮合并后的 Draft 生成 AI简介。事实阶段关闭百炼深度思考，输出预算按 4096 → 8192 扩容；AI简介开启深度思考，`thinking_budget=4096`，总补全预算按 12288 → 16384 扩容，最多两次生成，每次有独立 600 秒硬截止。
5. AI 返回先过纯函数 Contract，再进入 Draft。事实字段要求逐字段来源 URL、身份一致和类型/范围合法；AI简介要求整体来源、身份、基本结构、3000 字安全上限、非模板、非 Markdown 和非抄袭。1000–1100 字只是生成建议，不设最低验收字数；四方面只指导生成，不强制逐项覆盖；扩展阅读可省略或自然写入正文，不要求独立结构化字段，也不参与整篇采用判断。
6. `OpenAICompatibleAIClient` 只处理协议差异、搜索参数、token usage 与统一错误；`SecureAIHTTPDataClient` 负责 HTTPS、公网地址、重定向、超时和 2 MB 流式响应上限。AI 文本预算除显示字符外还约束 Unicode scalar 与 UTF-8 字节，最终 HTTP 请求体不得超过 256 KB。
7. `AIConfigStore` 把平台、Endpoint、模型、联网方式和验证状态写入 `UserDefaults`；API Key 只进入设备 Keychain，采用 destination binding 和 `WhenUnlockedThisDeviceOnly`。
8. UI 只选择模式并展示 Outcome；批量和微信同步按每本提交，失败或取消不会抹掉已完成结果，也不会把可重试失败标记为终态。
9. 添加、编辑和批量入口用 `EnrichmentBackgroundExecution` 持有 iOS 短时后台租约。页面消失不再取消任务；添加/编辑补全期间禁止下拉关闭和保存，只有“停止补全”或导航栏“取消”明确取消。后台额度到期只结束系统租约，保留 Swift Task 供回到前台后继续。

### 3. 产品入口实际映射

| 入口 | 调用模式 | 持久化边界 |
|---|---|---|
| 添加页“智能补全书籍信息” | `.full` | 用户点保存后创建 `Book` |
| 添加页“AI智能补全” | `.aiOnly` | 用户点保存后创建 `Book` |
| 编辑页“智能补全缺失信息” | `.full` | 用户点保存后修改 `Book` |
| 编辑页“AI智能补全” | `.aiOnly` | 用户点保存后修改 `Book` |
| 普通批量 | `.full` | 每本完成后立即保存 |
| 批量 AI 智能补全 | `.aiOnly` | 每本完成后立即保存 |
| 微信读书用户导入书 | `.full` | 每本同步后立即保存 |
| 微信读书平台书 | `.aiIntroductionOnly` | 每本 AI简介完成后立即保存 |

### 4. TDD 与安全修复记录

- 主功能通过独立 Swift Testing suites 覆盖 Draft、普通来源、AI 配置、HTTP Client、事实契约、AI简介契约、协调器、入口、批量和微信同步。
- 2026-09-20 安全审查发现：ISBN 成功命中曾绕过只位于书名回退分支的 `BookIdentityMatcher`，错误来源结果可能进入自动微信同步保存。
- 修复按红→绿逐片完成：冲突 ISBN；ISBN 相同但书名/作者冲突；ISBN-10/ISBN-13 等价；ISBN-only 缺少来源凭据；异常 ISBN 换算失败。
- 首轮策略位于 `ISBNMetadataSourceAdapter` 合并边界：来源侧 ISBN 冲突直接拒绝；已知书名/作者必须继续一致；ISBN-only 必须有来源已验证凭据。
- 低危复核发现扫码/快速添加仍直接调用 `ISBNLookupService.lookup(isbn:)`。新增公开 seam 测试先复现“请求 `9787020002207` 却接受 `9787020002214`”，再在该入口对每个来源统一要求 `isbnIsSourceVerified` 且 `BookIdentityMatcher.isbnMatches`。
- 第二个红→绿切片保持 Google Books 兼容：从 `volumeInfo.industryIdentifiers` 读取来源 ISBN，匹配后才返回；书名+作者回退仍允许同一作品的其他版本 ISBN。
- 修复前安全差异扫描（Scan ID `3b9dcc6c-1016-411a-808d-aae53fe1bea5`，报告 `/private/var/folders/kx/6gs9wm0n6yv69bx9zv6p00980000gn/T/codex-security-scans-zTKq7x/私人图书馆/80a00a105b2892ef370ce2dd5d950767187fcb8f_20260920T134743Z_bnop9z_7/report.md`）确认 3 个低危问题。修复前红灯证据保存在 `/tmp/PersonalLibrary-Red-Security-20260920-2220.xcresult`，55 项定向测试中产生 7 个预期问题；首轮绿灯保存在 `/tmp/PersonalLibrary-Green-Security-20260920-2227.xcresult`，55 项全部通过。
- `Retry-After` 修复：新增统一 `AIRetryDelayPolicy`，`NaN`/`Infinity` 使用 1 秒安全默认值，其他值限制在 0–10 秒；OpenAI 兼容 Client 和连接测试外层重试都经过同一有限值闸门。
- AI 身份修复：请求含有效 ISBN 时，无论书名是否存在，AI 事实响应都必须提供等价的 `matched_isbn`；缺失或冲突时整次拒绝。
- 普通来源修复：ISBN 候选只有在 `isbnIsSourceVerified == true`、ISBN 等价且书名/作者一致时直接采用；被拒绝但输入有书名时继续同来源 title/author fallback，保留跨版本回退能力。
- 新增边界后的 4 个安全套件绿灯保存在 `/tmp/PersonalLibrary-Green-Security-20260920-2230.xcresult`，共 88 项通过；6 个相关套件联合回归共 109 项通过。
- 2026-09-21 资源与隐私收口继续按垂直 TDD 切片执行：归档微信书自动 AI 调用、豆瓣建议无上限展开、普通元数据完整缓冲三个红灯分别复现后，增加归档候选闸门、5 个豆瓣候选上限和共享的 5 MB 流式响应缓冲；三个对应套件均独立转绿。
- AI简介长度闸门移动到高成本重复窗口、语义和抄袭分析之前；当前超出 3000 字立即拒绝，避免异常模型响应制造大量临时字符串。红灯为旧实现先报段落不完整，绿灯为稳定返回 `invalidLength`。
- 后续安全扫描确认 DNS 预校验与 `URLSession` 实际连接间存在 TOCTOU。按 TDD 将 AI 传输替换为 Network.framework 固定地址连接：只拨号本轮已校验的数值 IP，原域名继续用于 TLS SNI/证书和 HTTP `Host`；同源重定向逐跳重新解析固定，故障转移不回退 hostname。确定性测试覆盖数值地址、主机身份、重定向重固定、已校验地址内故障转移、分块响应、上限与取消；VPN Fake-IP 兼容性保留真机验证。
- 最终 Spec 独立审查发现普通来源身份拒绝仍被压成 `.notFound`，会让批量误写普通补全完成时间戳。按 TDD 修正为 `.validationRejected`：书名/作者冲突、来源 ISBN 冲突和缺少来源 ISBN 凭据分别有明确原因；合法的同来源书名回退仍返回 `.found`。红灯证据为 `/tmp/PersonalLibrary-Red-ValidationStatus-20260920-2255.xcresult` 与 `/tmp/PersonalLibrary-Red-ValidationStatus-Provenance-20260920-2306.xcresult`，逐片绿灯最终保存在 `/tmp/PersonalLibrary-Green-ValidationStatus-Final-20260920-2308.xcresult`。
- 2026-09-22 后台连续性按两个垂直 TDD 切片完成：先用生命周期策略复现 `onDisappear` 在 `scenePhase` 仍为 active 时误取消，再固定为页面消失永不取消；随后用可控后台任务管理器验证系统额度到期只释放租约、不取消等待中的补全。添加/编辑页运行中禁止隐式下拉关闭和保存，明确“取消”仍传播取消。

### 5. 运行时与真实服务记录

- 百炼“测试连接”使用短探针、30 秒全流程截止，不开启深度思考；模拟器真实调用约 12 秒通过。
- AI简介正式生成开启深度思考，百炼使用 `thinking_budget=4096` 与 `max_completion_tokens=12288 → 16384`，每次尝试最多 600 秒；`finish_reason=length` 或不完整 JSON 不会写入并会扩容重试。
- API Key 未写入仓库、日志或测试 fixture；真实测试只读取模拟器已有 Keychain 配置。
- 微信同步集成测试必须显式注入测试补全器，不得依赖模拟器是否存在个人 AI Keychain 配置；最终测试已修正为 hermetic，不会把测试书目发送到真实 Endpoint。

### 5.1 2026-09-21 真机残缺 JSON 修复

- 以 `AICompletionClient.complete`、`AIEnrichmentService.enrich` 和 `AIIntroductionContract` 为公开测试 seam，先复现响应截断、`finish_reason=length`、简介字数临界和 `NSURLErrorNetworkConnectionLost (-1005)`。
- 客户端解码结束原因并对 -1005 重试一次；服务层仅对可修复的截断/不完整 JSON 使用第二档预算，取消和其他失败语义保持不变。
- 规格审查补出 `finish_reason=length` 且 `content=null` 的边界：客户端现在保留截断状态给服务层扩容重试，不会在看到结束原因前误报普通无效响应；该切片已完成独立红→绿验证。
- 简介提示词以 1000–1100 个非空白字符为建议目标；真机反馈证明最低 900 字门槛会拒绝可靠的精炼正文，因此已移除最低验收字数，当前安全上限为 3000 字。
- 关键三个测试套件共 59 项通过，证据为 `/tmp/PersonalLibrary-Bug-IncompleteJSON-Green-Final`。
- 模拟器真实调用 qwen3.7-plus 生成《大一统的制度密码》AI简介，约 128 秒通过完整合同，证据为 `/tmp/PersonalLibrary-Live-AI-E2E-Qwen37-PromptFix`；临时真实联网测试随后从仓库移除。

### 6. 最终自动验证（2026-09-20）

| 验证项 | 结果 | 证据 |
|---|---:|---|
| AI/普通来源联合回归 | 109 项 / 6 suites 通过 | `/tmp/PersonalLibrary-Related-Final-20260920-2310.xcresult` |
| 完整单元/集成测试 | 499 项 / 79 suites 通过 | `/tmp/PersonalLibrary-Unit-Final-20260920-2312.xcresult` |
| UI 测试 | 3 项通过 | `/tmp/PersonalLibrary-UI-Final-20260920-2314.xcresult` |
| App 全体行覆盖率 | 22.11%（6947/31422） | `xccov`，包含大量 SwiftUI 声明式代码 |

### 6.1 截断修复回归（2026-09-21）

| 验证项 | 结果 | 证据 |
|---|---:|---|
| 截断、预算、网络重试与简介合同 | 59 项 / 3 suites 通过 | `/tmp/PersonalLibrary-Bug-IncompleteJSON-Green-Final` |
| 完整单元/集成测试 | 506 项 / 79 suites 通过 | `/tmp/PersonalLibrary-Final-20260921/Logs/Test/Test-PersonalLibrary-2026.09.21_01-09-21-+0800.xcresult` |
| UI 测试 | 3 项通过 | `/tmp/PersonalLibrary-Final-UI-20260921/Logs/Test/Test-PersonalLibrary-2026.09.21_01-17-54-+0800.xcresult` |
| App 全体行覆盖率 | 24.55%（7729/31487） | `xccov`，来自上述最终 506 项测试 |
| qwen3.7-plus 真实 AI简介 | 约 128 秒，通过完整合同 | `/tmp/PersonalLibrary-Live-AI-E2E-Qwen37-PromptFix` |

### 6.2 最终安全收口回归（2026-09-21）

- 阶段截止由结构化任务组改为锁保护的一次性 continuation 竞速；30ms 测试面对 2 秒且不响应取消的客户端仍立即返回，证明 60/600 秒预算是真正硬截止。
- Spec 末轮复审发现事实检索的 4096 → 8192 重试曾各自取得完整 60 秒。新增回归先在旧实现失败，再让两次请求共享同一单调时钟 deadline，并把每次 HTTP timeout 同步收窄为剩余预算。
- 普通元数据重定向分别覆盖“同主机降级 HTTP”和“跨主机 HTTPS”，两者均在跟随后拒绝。
- 微信书除入队过滤外，还在 AI 与划线调用前重读归档状态；入队后并发归档的红灯测试证明旧实现会继续外发，修复后 AI 与划线调用数均为 0。
- 旧微信同步测试显式注入 no-op 补全器，不再因模拟器 Keychain 中存在真实 AI 配置而访问外网或超时。
- 用户真机使用 qwen-plus 先后复现“AI简介四个板块不完整”和“对比或扩展阅读缺少真实书名、理由或来源”，确认旧合同把写作方向误实现为逐项关键词及 `comparison_books` 闸门。按垂直 TDD 先后复现缺少独立来源、正文出现其他书名、理由泛化/无关、错误类型和残缺对象；最终删除 `comparison_books` 响应要求与全部关联校验，同时保留四个 section 作为协议/排版结构，以及整体来源、身份、长度、纯文本、模板、截断和抄袭闸门。
- 用户随后真机复现“AI简介字数不够”。模拟器真实请求对《辞职上山》约 140 秒成功，说明网络和配置正常；确定性契约测试则证明 450 字的结构完整、来源有效正文会被旧 900 字下限拒绝。按红→绿移除最低字数门槛；该阶段的 1200 字资源上限随后已放宽为 3000 字。
- 独立 Spec 复审继续发现每个标题至少 4 字、每段正文至少 50 字的隐藏下限。新增短标题/短段落回归先稳定复现 `.incompleteSections`，随后移除这两个固定门槛；非空、四段结构、低信息重复、身份、来源和全文资源上限仍保留，最终上限以 3000 字修订为准。
- 独立安全复审发现书名、作者被直接插入 AI简介控制指令区。新增恶意书名/作者隔离测试后，控制区只引用 `book_data.title` / `book_data.author`，实际外部文字仅存在于 `<book_data>` JSON 中。
- 清理临时门禁前，iPhone 16 Pro 模拟器以“添加新书”草稿对《辞职上山》执行真实 `AI智能补全`，约 50 秒出现“已补全”结果，完整 UI 用例约 70 秒通过；随后取消草稿，未写入书库。证据为 `/tmp/PersonalLibrary-AIIntro-HiddenFloor-Live-E2E-Run.xcresult`。
- 3000 字修订继续按垂直 TDD 完成：先将边界测试改为 3000 接受/3001 拒绝并确认旧 1200 闸门红灯，再修改合同与 Prompt；随后分别用组合附加符复现 AI简介、事实字段和 Prompt 预算绕过，并用超大 JSON body 复现发送前缺少总字节闸门。
- 资源修复集中在 `AITextBudget`：保留 `Character` 作为显示字数，补充 Unicode scalar/UTF-8 预算并逐 Character 安全截断；`OpenAICompatibleAIClient` 在序列化后以 256 KB 为最终请求边界。输出超限拒绝，输入超限截断，均不改变正常字段和 3000 字简介行为。

| 验证项 | 结果 | 证据 |
|---|---:|---|
| 完整单元/集成测试 | 517 项 / 79 suites 通过 | `/tmp/PersonalLibrary-AIIntro-Flexible-Final3-Unit.xcresult` |
| UI 测试 | 3 项通过 | `/tmp/PersonalLibrary-AIIntro-Flexible-Final3-UI.xcresult` |
| App 全体行覆盖率 | 24.51%（7765/31680） | `xccov`，来自上述 517 项测试 |

本次主要能力文件的行覆盖率：

- `EnrichmentCoordinator.swift` 100.00%
- `DoubanBookPage.swift` 97.80%
- `BookIdentityMatcher.swift` 95.05%
- `AIEnrichmentService.swift` 88.76%
- `AICompletionClient.swift` 84.55%
- `ISBNMetadataSourceAdapter.swift` 84.14%
- `ISBNLookupService.swift` 76.05%
- `WeReadSyncService.swift` 72.72%

### 6.3 并发持久化与统一取消收口（2026-09-21）

- 批量补全在每本外发前通过短生命周期 `ModelContext` 重读候选；网络返回后再次读取并提交。图书已删除、归档或不再符合候选条件时 fail-closed，不发送或不落库。
- AI 返回结果提交前基于最新 `BookDraft` 做三方 rebase：用户在等待期间修改的字段优先，其他无冲突的 AI 字段仍可保存；统计使用实际提交后的 outcome。
- 微信读书 AI 同步复用同一提交边界；AI 等待期间归档不落库，后续划线阶段也使用新的 context，避免旧 `Book` 对象在稍后保存时回写 AI 字段。
- `WeReadSyncService.sync` 自己持有并登记核心 Task；自动同步、登录后同步和手工同步都由同一个 `cancelCurrentSync()` 取消。运行槽以 UUID 原子 claim，旧任务 cleanup 不能清除新任务。
- 两套硬截止实现合并为共享泛型竞速器；`EnrichmentField` 的 JSON 键名以及 `BookDraft` 字段比较/复制集中到领域类型，减少新增字段时的漂移。

### 6.4 最终闭环回归（2026-09-21）

- 微信书架拉取期间发生归档或删除时，提交阶段重新读取持久层状态：已归档书不再接受远端更新，已删除书不会被重新导入；AI 等待后归档也不会继续发出划线请求。
- Endpoint 来源校验拒绝尾点域名、IPv6 等价写法、IPv4-mapped IPv6，以及十进制、十六进制和混合分段等历史 IPv4 数字写法，避免通过地址别名绕过来源边界。

| 验证项 | 结果 | 证据 |
|---|---:|---|
| 完整单元/集成测试 | 550 项通过 | `/tmp/PersonalLibrary-FinalTests3.RDqfxu/UnitTests.xcresult` |
| UI 测试 | 3 项通过 | `/tmp/PersonalLibrary-FinalUI.JLcT7G/UITests.xcresult` |
| App 全体行覆盖率 | 25.08%（8109/32336） | `xccov`，来自上述 550 项测试 |
| 测试目标行覆盖率 | 97.93%（10181/10396） | `xccov`，来自上述 550 项测试 |

### 6.5 后台连续性回归（2026-09-22）

- 定向 `EnrichmentEntryIntegrationTests` 8 项通过，包含生命周期时序和后台额度到期语义。
- 完整单元/集成测试 552 项、79 suites 全部通过；正式 UI 测试 3 项全部通过。
- iPhone 16 Pro 模拟器使用已有 Keychain AI 配置执行临时真实 UI 验证：添加页启动《辞职上山》AI 智能补全，按 Home 后后台停留 5 秒，再激活 App，补全没有变成“已停止补全”；随后点“取消”明确终止，未保存测试书。临时 UI 用例验证后已删除。

| 验证项 | 结果 | 证据 |
|---|---:|---|
| 完整单元/集成测试 | 552 项通过 | `/tmp/PersonalLibrary-Background-Full-Unit.xcresult` |
| UI 测试 | 3 项通过 | `/tmp/PersonalLibrary-Background-UI.xcresult` |
| App 全体行覆盖率 | 25.04%（8135/32485） | `xccov`，来自上述 552 项测试 |
| 测试目标行覆盖率 | 97.94%（10247/10462） | `xccov`，来自上述 552 项测试 |
| 真实前后台切换 | 通过 | `/tmp/PersonalLibrary-Background-Live3.xcresult` |

### 6.6 豆瓣跨版本译者修复（2026-09-22）

- 以《大便书》真实豆瓣 HTML 结构新增红灯测试，复现标签外冒号被解析成作者/译者片段；修复后作者和译者不再含 `:`。
- 以《大便书（纪念版）》ISBN `9787536486003` 为集成样本新增红灯测试：精确版本无译者时，用去除版本装饰后的书名检索身份匹配版本，只合入译者“吴锵煌”。
- 精确 ISBN 版本的书名、ISBN 和其他版本相关字段保持不变；跨版本候选继续经过书名与作者身份闸门。
- 定向 `ISBNLookupEnrichmentTests` 31 项通过；完整单元/集成测试 554 项、79 suites 全部通过。
- 覆盖率：App 25.18%（8183/32503），测试目标 97.95%（10304/10520）；`DoubanBookPage.swift` 97.80%，`BookTextNormalizer.swift` 96.97%，`ISBNMetadataSourceAdapter.swift` 86.88%。
- 完整测试证据：`/tmp/PersonalLibrary-DoubanTranslator-Full/Logs/Test/Test-PersonalLibrary-2026.09.22_01-45-14-+0800.xcresult`。

### 6.7 《人生问答》invalidJSON 误分类修复（2026-09-22）

- iPhone 16 Pro 模拟器使用已保存的百炼 `qwen-plus` 配置重放：译者事实检索连续返回语法完整的 `status:error` JSON，随后 AI简介返回完整 JSON 并通过合同。诊断未读取、打印或落盘 API Key。
- 第一层根因是 `AIEnrichmentContract` 用同一个 `guard` 同时判断 JSON 可解析性和 `status == "ok"`，导致完整非成功响应被误标为 `invalidJSON`；拆分解析后可独立识别 `unsuccessfulStatus`。
- 用户随后确认“《人生问答》未找到资料”仍是误导语义。以 `AIEnrichmentService.enrich` 为公开 seam，新红灯稳定复现 `.notFound` 和单次请求；修复后非 `ok` 响应在共享 60 秒预算内重试一次，仍失败则返回 `.validationRejected("AI 未按约定返回可验证结果")`。
- 提示词同时明确：已核实书籍但所有目标字段均无法确认时，仍返回 `status:ok` 与空 `fields`。因此合法空结果保持字段为空且不报字段错误，而 `status:error` 不再伪装成整本书未找到。
- 真正无法解析的 JSON 仍按 4096 → 8192 扩容重试，证据和身份闸门不变。
- AI Client、事实合同、AI简介合同和服务层定向回归 102 项通过；完整单元/集成测试 555 项、79 suites 全部通过。
- 覆盖率：App 25.20% （8195/32515），测试目标 97.95% （10328/10544）；完整测试证据为 `/tmp/PersonalLibrary-LifeQuestions-Full.xcresult`。

### 6.8 《大一统的制度密码》出版日期修复（2026-09-22）

- 读取真实豆瓣详情页确认该书出版年为 `2026-8`；旧 `PublicationDateParser` 只接受补零后的 `yyyy-MM` / `yyyy-MM-dd`，所以常规补全虽然抓到字符串，转换到 `BookDraft` 时变成 `nil`。
- 先以 `2026-8` 和 `2017-7-1` 建立红灯，随后把月份和日期宽度放宽为 1–2 位；非法日期 `2024-19-42` 仍被拒绝。
- 豆瓣集成 fixture 改用 `2026-8`，从页面解析、来源 Adapter 到草稿合并均断言得到 2026-08-01。
- 定向 `BookDraftTests` 7 项和 `ISBNLookupEnrichmentTests` 31 项通过；完整单元/集成测试 556 项、79 suites 全部通过。
- 覆盖率：App 25.20%（8195/32519），测试目标 97.95%（10343/10559）；完整证据为 `/tmp/PersonalLibrary-Enrichment-Date-Full.xcresult`。

### 7. 最终独立审查

- Standards 多代理审查：最终修改文件无阻塞性问题，测试边界闭合，`git diff --check` 通过。
- Spec 多代理审查：先后发现普通来源身份拒绝误归类为 `.notFound`、事实检索两轮各自取得完整 60 秒；均按 TDD 修复。最终复审确认新书导入、未归档书更新及来源验证语义均无剩余偏差。
- Codex Security 最终多代理差异扫描：Scan ID `36d22883-e520-45f4-8d77-9552e94279cd`，47 个源码/测试文件全部覆盖，确认漏洞 0；3 个低危问题均闭合。报告位于 `/private/var/folders/kx/6gs9wm0n6yv69bx9zv6p00980000gn/T/codex-security-scans-zTKq7x/私人图书馆/80a00a105b2892ef370ce2dd5d950767187fcb8f_20260920T143230Z_m5hhbo70/report.md`。
- 扫描后 `.validationRejected` 状态语义增量又做了独立安全复核，确认拒绝候选仍不会合入、合法书名回退仍需书名/作者匹配，未引入安全回归。
- 最终 Codex Security 扫描（Scan ID `0c1f4f2b-b6f8-4188-9ae7-75b66d3b8121`）针对不可变的较早工作区快照记录 1 个低危归档外发问题；当前工作区已按报告建议增加初始与逐调用归档闸门并通过回归。报告位于 `/private/var/folders/kx/6gs9wm0n6yv69bx9zv6p00980000gn/T/codex-security-scans-zTKq7x/私人图书馆/80a00a105b2892ef370ce2dd5d950767187fcb8f_20260920T165709Z_arq45jqw/report.md`。两条 DNS rebinding 路径仍需受控 iOS DNS/TLS 环境动态验证。
- 上一轮工作区曾经独立安全代理只读复审；当时的 AI简介合同与测试摘要 SHA-256 为 `c2168b544e72a0cf5805e7fe72f37e83c06e992b11c0f5ee8cf4586d2446c4e4`，未发现报告级问题。共享 deadline、密钥与 Endpoint 绑定、重定向限制、流式响应上限和微信归档 fail-closed 闸门均有效。后续根据用户语义澄清移除了可选对比书的正文书名—理由—来源绑定；来源正文尚未由 App 二次抓取核验，整体来源和百炼联网探针仍属于启发式证据，这些作为产品可信度限制保留。
- 最终正式不可变快照 Security Scan（Scan ID `a5b1982c-409f-437a-8507-1e3de725e3a6`）完整覆盖目标变更，报告记录 2 个中危和 1 个低危问题；当前工作树已分别通过书架提交时状态复查和 Endpoint 数字地址规范化完成修复，并补齐回归测试。扫描报告位于 `/private/var/folders/kx/6gs9wm0n6yv69bx9zv6p00980000gn/T/codex-security-scans-zTKq7x/私人图书馆/80a00a105b2892ef370ce2dd5d950767187fcb8f_20260921T123652Z_kzybngbo/report.md`；扫描覆盖状态为 complete，总计使用 84,441,698 tokens（其中缓存输入 79,071,776）。
- 扫描后最终安全复审仅检查上述两项修复及邻近边界，确认等待期间归档/删除 fail-closed，历史 IPv4、八/十六进制和 IPv4-mapped IPv6 均无法绕过来源校验，无剩余阻断性安全问题。

### 8. 最终部署（2026-09-21）

- iPhone 16 Pro 模拟器（UDID `230F698B-902D-4099-96D0-C3FD5B4E6374`）：使用最终 550+3 测试后的 Debug 构建覆盖安装，`simctl launch` 成功，`get_app_container` 确认 `com.joe.PersonalLibrary` 已安装。未卸载 App、未清除数据或 Keychain，保留了用户配置的 AI Endpoint 与密钥。
- “多洛霍夫”iPhone 14 Plus（UDID `00008110-000118911185401E`）：最终源码重新完成 arm64 真机构建并签名，`BUILD SUCCEEDED`；随后通过数据线使用 `devicectl device install app` 覆盖安装。设备端回读确认“私人图书馆”版本 `0.67`（Build `1`）、Bundle ID `com.joe.PersonalLibrary`，并成功启动。未执行卸载、数据清理或 Keychain 清理。
- 最终部署产物分别来自 `/tmp/PersonalLibrary-Final-DerivedData/Build/Products/Debug-iphonesimulator/PersonalLibrary.app` 和 `/tmp/PersonalLibrary-AI-FinalClosure-Device/Build/Products/Debug-iphoneos/PersonalLibrary.app`。这些 `/tmp` 构建产物仅作为本机部署证据，不属于版本库交付物。

### 8.1 后台连续性部署（2026-09-22）

- iPhone 16 Pro 模拟器已覆盖安装包含后台连续性修复的 Debug 构建并成功启动；未卸载 App、未清数据、未清 Keychain。
- “多洛霍夫”iPhone 14 Plus 已从最新源码重新完成 arm64 构建与签名，并通过数据线覆盖安装、成功启动。设备回读为版本 `0.67`（Build `1`）、Bundle ID `com.joe.PersonalLibrary`；未卸载 App、未清数据、未清 Keychain。真机构建产物位于 `/tmp/PersonalLibrary-Background-Device/Build/Products/Debug-iphoneos/PersonalLibrary.app`。
