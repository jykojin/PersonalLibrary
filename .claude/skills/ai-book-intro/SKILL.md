---
name: ai-book-intro
description: 为《私人图书馆》的藏书批量生成或补写「AI介绍」字段（Book.bookIntroduction）。用于全量重写、增量补新书、或修复某一批质量不达标的介绍。涉及 .plbackup 数据库的读写与 xlsx 导出。
---

# AI介绍 批量生成

给《私人图书馆》的书补 `Book.bookIntroduction`（Excel 第 32 列「AI介绍」）。
写作标准在 `PROMPT.md`，那是唯一的契约；本文只讲**怎么跑**。

## 什么时候用

- 全量重写（换风格、旧数据是模板货）
- 增量补新书（`export-batches --only-empty`）
- 某些书的介绍不达标，要重做

## 铁律

1. **原始 `.plbackup` 绝不改**。所有操作在 `/tmp/pl-ai-intro/work.sqlite` 副本上做，
   `original.sqlite` 留作最终比对的基准。
2. **动手前先 `archive`**。一次性迁移只跑一次，跑错没有第二次机会。
3. **`checkpoint` 不能省**。库是 WAL 模式，写完不 checkpoint 就会留下 `-wal` 边车；
   App 的 `restoreBackup` 只复制主文件 + 可选边车，用户只传主文件时改动会**静默丢失**。
4. **只碰 `ZBOOKINTRODUCTION` 一列**。`ZBOOKDESCRIPTION`（豆瓣书籍简介）和
   `ZAUTHORDESCRIPTION`（作者简介）是生成用的**原料**，是不同的字段，不许动。
   `verify` 会逐行比对来证明这一点。
5. **按 `Z_PK` 写回，不要按 ISBN 匹配**。库里套书各卷共用 ISBN（张居正、曾国藩、余罪都是），
   按 ISBN 回填会一条介绍写到多本书上 —— v0.64 就出现过 2853 条写了 2854 本。

## 完整流程

```bash
cd <repo>
BACKUP="/path/to/PersonalLibrary_YYYYMMDD_HHMMSS.plbackup"
mkdir -p /tmp/pl-ai-intro/{in,out,archive}
cp "$BACKUP" /tmp/pl-ai-intro/work.sqlite      # 要改的副本
cp "$BACKUP" /tmp/pl-ai-intro/original.sqlite  # 比对基准

python3 tools/ai_intro/pipeline.py archive          # 1. 存档现有介绍
python3 tools/ai_intro/pipeline.py clear            # 2. 清空字段（全量重写才需要）
python3 tools/ai_intro/pipeline.py export-batches   # 3. 切批 → in/batch_NNN.json
#    增量补新书用： export-batches --only-empty （跳过 clear）

#  4. 生成 —— 见下节，跑 Workflow

python3 tools/ai_intro/pipeline.py merge            # 5. 收集校验 → merged.json
python3 tools/ai_intro/pipeline.py write-db         # 6. 按 Z_PK 写回
python3 tools/ai_intro/pipeline.py checkpoint       # 7. WAL 并回主文件 + 清边车
python3 tools/ai_intro/pipeline.py verify           # 8. 证明只有 AI介绍 变了
python3 tools/ai_intro/pipeline.py export-xlsx --out /tmp/pl-ai-intro/AI介绍.xlsx
python3 tools/ai_intro/pipeline.py publish <文件...> --dest "<iCloud 目录>"
```

第 5 步之后必看 `merge_report.json`：`rejected` 非空就把那些批次的 `out/` 删掉重跑，
`insufficient` 是查不到资料而合理留空的书（不是失败）。

## 第 4 步：跑生成

`export-batches` 会打印批数。分两轨：

| 轨 | 判据 | 批大小 | agent 行为 |
|---|---|---|---|
| A | 豆瓣简介 ≥ 50 字 | 25 | 只用本地原料，**禁联网**（联网会慢一个数量级） |
| B | 豆瓣简介缺失/过短 | 10 | **先 WebSearch 查证**，查不到就 `insufficient_data` 留空 |

批数超过十几个就用 **Workflow**（需用户明确同意多 agent 编排）：
`parallel()` 扇出，每个 agent 读 `PROMPT.md` + 自己那批的输入文件，写输出文件，
**只回统计数字**（把 2900 段正文回传会撑爆编排层的上下文）。

agent 回报 `input_book_count` 与 `results_written`，不相等就自动重跑一次。
真正的质量闸门是第 5 步的 `merge`，不是 agent 的自我汇报。

批数少（≤15）时直接用 Agent 工具分波跑也行。

## 校验规则

`validate.py` 是纯函数 + pytest：

```bash
cd tools/ai_intro && python3 -m pytest test_validate.py -q
```

判据锚在两端 —— 《平面国》标杆样板必须通过，库里真实的模板垃圾必须被打回。
改阈值前先跑测试；两端都锁着，改坏了会立刻红。

阈值（`validate.py` 顶部常量）比契约给 agent 的目标区间宽：契约说"往哪写"（700–1000 字），
校验说"什么绝不能要"（600–1400 字）。

但**缝隙不能留太大**。下限一度设在 550，结果 110 段（13%）挤在 550–599 —— agent 优化的是
闸门而不是目标，缝隙大就会出现「顶到刚过线」的最小补丁。同一个模式在这个项目里出现了三次
（删标点绕抄袭红线、545 字顶到 573 字、这一次）。现在下限与目标只差 100，并有测试锁住这个差距。

## 踩过的坑

- **`ZPUBLISHDATE` 有脏数据**：实测有一条换算出公元 20208 年。`publish_year()` 对
  超出 `1000..今年+1` 的一律返回 `None` —— 宁可导语段不写年份，也不能把假年份当事实喂给 agent。
- **契约的缩进约定与样板不一致**：契约初版写"全角空格"，而《平面国》样板实际用半角空格。
  `validate.py` 两种都认，`normalize_indent()` 在写回前统一成半角（对齐样板）。
  跑批中途**不要**改契约 —— 先后启动的 agent 会用不同约定，比统一用错更糟。
- **`未知` 不能列为禁用占位符**：标杆样板里就有「对未知维度的推演」。契约初版列了它，
  是自相矛盾的，已修。
- **xlsx 表头前 5 列必须逐字匹配** `ExcelImportExportService.parseIntroductionEntries`
  读的 `书名/作者/ISBN/微信读书ID/AI介绍`，否则 App 的「导入 AI介绍」认不出来。
- **App 的 `backfill` 只补空值**，不覆盖。想用 xlsx 走 App 路径回填，必须先清空字段。
