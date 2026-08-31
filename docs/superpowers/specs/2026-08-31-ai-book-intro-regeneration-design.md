# AI介绍 全量重写 — 设计文档

**日期：** 2026-08-31
**状态：** 已批准（用户「认可，用方案B」），实施中
**涉及范围：** `Book.bookIntroduction` 的全量重写；新增 `tools/ai_intro/` 管线与 `ai-book-intro` skill
**不涉及：** 任何 Swift 代码。App 侧一行不改。

## 背景与问题

用户导出备份 `PersonalLibrary_20260830_222821.plbackup`（103 MB，2904 本），
要求清空「AI介绍」后按《平面国》风格重新生成，写回数据库并导出 excel。

现存 2856 条是**模板拼出来的**，实测病灶：

| 症状 | 实例（库里 pk=3《S.》） |
|---|---|
| 模板句 | `是由Dorst, Doug创作或编著的综合性读物` |
| 通用小标题 | 每本都是「内容概览／主题与特色／阅读价值」 |
| 抄原料还截断 | `内容概览` 段是豆瓣简介前若干字 + `……` |
| 占位符漏出 | `本书重点涉及T1。` |
| 末段万能空话 | `适合先通过目录和章节标题把握结构…` |

篇幅平均 395 字。用户给的《平面国》样板是 694 字的结构化正文，
每个分节标题都是这本书特有的，每个条目都给具体信息。

## 数据事实（实测）

| 项 | 值 |
|---|---|
| 总书数 | 2904（已归档 36） |
| 有 AI介绍 | 2856 |
| 豆瓣简介 ≥50 字（可作原料） | 2794 |
| 豆瓣简介缺失/过短 | 110 |
| 有作者简介 | 2202 |
| 豆瓣简介平均/最长 | 493 / 7158 字 |
| `journal_mode` | **wal** |
| 原始备份旁的 `-wal` 边车 | 无（自包含单文件） |

《平面国》**不在**这个库里 —— 它是风格样板，不是待处理的一行。

## 方案

### 风格契约

单一来源 `.claude/skills/ai-book-intro/PROMPT.md`：
「导语段 + 三个分节（末节固定谈价值/局限）」，条目缩进一个空格 + `短语：` + 说明，
纯文本（App 里是 `Text` 直出，markdown 会原样显示）。
契约同时收录《平面国》标杆与《S.》垃圾作为正反样板。

### 分轨

| 轨 | 判据 | 本数 | 批大小 | 批数 | agent 行为 |
|---|---|---|---|---|---|
| A | 豆瓣简介 ≥ 50 字 | 2794 | 25 | 112 | 只用本地原料，禁联网 |
| B | 豆瓣简介缺失/过短 | 110 | 10 | 11 | 先 WebSearch 查证，查不到则留空 |
| | | **2904** | | **123** | |

track B 允许 `insufficient_data`：**留空是可接受的结果，编造不是**。

### 管线

`tools/ai_intro/pipeline.py` 九个子命令：
`archive → clear → export-batches →`（生成）`→ merge → write-db → checkpoint → verify → export-xlsx → publish`。

agent 只写文件、只回统计数字；数据库由脚本按 `Z_PK` 精确写回。
把 2904 段正文经编排层回传会撑爆上下文，且 agent 的自我汇报不能当质量闸门 —— 闸门是 `merge`。

### 校验

`tools/ai_intro/validate.py` 纯函数 + 27 个 pytest。判据锚在两端：
《平面国》样板必须通过，《S.》垃圾必须被打回。规则为篇幅 550–1400 字、
≥2 个分节标题、≥4 个缩进条目、导语含书名、无模板句/通用小标题/占位符/markdown/截断痕迹、
与豆瓣简介连续重合 <40 字。

阈值刻意比契约的目标区间（800–1100）宽：契约说"往哪写"，校验说"什么绝不能要"。

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 生成通道 | Claude Code 子 agent（非 API） | 用户无可用 API key，走订阅额度 |
| 模型 | Claude Opus 5 | 用户选定；中文文学性与冷门中文书知识面最好 |
| 写回方式 | 直接 UPDATE 到 `.plbackup` 副本 | 用户一步恢复。按 `Z_PK` 比 xlsx 路径按 ISBN 精确 |
| 缺料书 | 联网查证，查不到留空 | 用户选定。不在藏书库里留编造内容 |
| `Z_OPT` | 不动 | Core Data 的乐观锁版本号只在会话内做冲突检测 |
| 归档书（36 本） | 一并处理 | 占 1.2%，留着字段才一致 |

## 实施中发现的问题

1. **`ZPUBLISHDATE` 有脏数据** —— 一条换算出公元 20208 年，直接让 `datetime` 抛
   `ValueError: year 20208 is out of range`。`publish_year()` 现对超出 `1000..今年+1`
   的值返回 `None`：宁可导语段不写年份，也不能把假年份当事实喂给 agent。

2. **契约与样板的缩进约定不一致** —— 契约初版写"一个全角空格 U+3000"，
   样板实际用**半角空格 U+0020**。发现时批量已在跑，中途改契约会让先后启动的 agent
   用不同约定（比统一用错更糟），故：校验器两种都认，`normalize_indent()`
   在写回前统一成半角，契约留到跑完再修。

3. **契约把 `未知` 列为禁用占位符，而标杆样板里就有「对未知维度的推演」** ——
   自相矛盾。校验器不收 `未知`，只认 `T[0-9]` 这类真的漏出过的占位符。

4. **契约的目标篇幅（800–1100）高于样板本身（694 字）** —— 保留不改：
   更长意味着更充实，且校验下限压到 550，不会因此打回。

## 编排方式：方案 B 失败，回落方案 A

原定用 Workflow 工具做 123 批 `parallel()` 扇出。**实测失败并已停止**：

- 日志 `started 87 / failed 10`，**零 `completed`**，`out/` 产出 0 个文件
- 失败 agent 的最后一条记录是 `[Request interrupted by user]` —— agent 每次刚读完契约
  就被中断，workflow 随即重启，循环 80 余轮
- 同期主会话的 Bash 调用亦报 `claude-sonnet-5 temporarily unavailable`，
  判断为该时段上游不稳定叠加打断
- 代价：约 87 次 agent 空转启动，每次约 25K input（子 agent 系统提示含 386 条 skill 清单），
  估计浪费 2M 量级 input token，零产出

**教训：编排层的可靠性要先用一个批次验证，再扇出到上百个。**
先跑 1 批确认端到端能落盘，比直接铺开 123 批省得多。

回落为方案 A：由主会话分波调 Agent，每波结果直接可见，不依赖会被打断的编排层。

## 验证标准

- `pytest tools/ai_intro/test_validate.py` 全绿（27 passed，已达成）
- `verify` 子命令：行数一致；`ZTITLE/ZAUTHOR/ZBOOKDESCRIPTION/ZAUTHORDESCRIPTION/ZISBN/`
  `ZPUBLISHER/ZNOTES/ZSTATUS/ZISARCHIVED/ZRATING/ZCURRENTPAGE/ZTOTALPAGES/`
  `ZWEREADBOOKID/ZCOVERIMAGEDATA` 逐行与原库相同（差异必须为 0 行）；无 `-wal`/`-shm` 残留
- 抽 10 本（含 3 本 track B 缺料书）人工读正文
- `merge_report.json` 的 `rejected` 清零

## 交付物

| 文件 | 说明 |
|---|---|
| `PersonalLibrary_20260831_AI重写.plbackup` | App「数据备份 → 恢复」一步导入 |
| `AI介绍_20260831.xlsx` | 6 列 + 字数；前 5 列表头与 App 导入端兼容 |
| `旧AI介绍_存档_20260831.xlsx` | 旧 2856 条备份（唯一退路） |
| `report.md` | 成功/留空/打回清单 |

原始 `.plbackup` 一个字节都不改。

## 范围红线（本次不做）

- 不改任何 Swift 代码，不加 App 功能
- 不碰 `ZBOOKDESCRIPTION`（豆瓣书籍简介）与 `ZAUTHORDESCRIPTION`（作者简介）
- 不改 `Book` 模型、不改 Excel 列布局
- 不清理库里的重复书（PROJECT_NOTES 遗留事项，另案）
- 不顺手重构相邻代码
