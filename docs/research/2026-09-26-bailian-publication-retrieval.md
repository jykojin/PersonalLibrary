# 百炼图书出版信息检索参数核查

核查日期：2026-09-26。范围：仅阿里云官方 API/指南；未读取密钥、未调用用户 AI endpoint、未修改 App 代码。本文记录参数能力，不将官方功能描述当作本书检索成功的证据。

## 与本次漏补直接相关的结论

- `qwen-plus-latest` 列于联网搜索支持模型。`enable_search: true` 加 `search_options.forced_search: true` 是官方 Chat Completions 强制搜索写法；当前请求并非明显漏了搜索开关。[1]
- 默认策略是 `turbo`；可尝试 `max`，官方说明它采用“更全面的搜索策略，可调用多源搜索引擎”，但响应时间可能更长。官方未列出 `pro`、`standard` 两个值。更强检索不保证命中某一本书，也不能替代字段证据验证。[1][2]
- **OpenAI-compatible Chat Completions 不支持返回搜索来源**。`enable_source`、`enable_citation`、`citation_format` 仅供 DashScope；给现有 Chat 请求增加这几个参数不能建立可信的 provider 来源链。[1]
- 官方明确说 Chat 兼容响应“暂无法通过响应明确判断是否执行搜索”；输入 Token 相比原始问题明显增大只能作为检索发生的参考迹象。模型自己输出的 `sources` URL 不等于平台返回的已检索来源。[1]
- 未找到官方说明 `json_object` 或 `enable_thinking: false` 会关闭普通联网搜索。`Qwen-Plus` 非思考模式明确支持 JSON Object；不能据此断言复杂结构化提示词不会影响搜索意图改写，后者需真实对照请求验证。[1][2][3]

## 官方支持参数及边界

以下路径相对 HTTP JSON 请求体；Python SDK 需将非 OpenAI 标准字段放入 `extra_body`，原始 HTTP 不增加这一层。[2]

| 参数 | 官方行为 / 适用边界 |
| --- | --- |
| `enable_search` | 默认 `false`；`true` 开启检索能力，不单独保证每次搜索。 |
| `search_options.forced_search` | 默认 `false`；设 `true` 强制联网，需同时开启 `enable_search`。 |
| `search_options.search_strategy` | `turbo` 默认；`max` 多源更全面；`agent` 多轮搜索，限部分较新模型；`agent_max` 增加网页抓取并有更严格模型限制。`qwen-plus-latest` 未被列入 `agent` / `agent_max` 支持范围，不能通用设置。 |
| `search_options.enable_search_extension` | 垂域数据源；官方列天气、股票、汇率等，**未列图书出版元数据**，不能当作 ISBN 数据库开关。 |
| `search_options.freshness` | `7` / `30` / `180` / `365`，仅 `turbo`，不设置则不限；图书出版信息不应误加近期限制。 |
| `search_options.assigned_site_list` | 仅 `turbo`，最多 25 个站点，默认 `[]`；限制到指定站点，不是保证读取指定网页。无搜索结果时模型可能用自身知识回答。支持模型表写 `qwen-plus`，未单独确认 `qwen-plus-latest` 别名。 |
| `search_options.intention_options.prompt_intervene` | 自然语言干预搜索范围，官方示例配 `turbo`；不是原始搜索关键词透传参数，也不补足模型推理能力。支持列表写 `qwen-plus`，别名兼容需验证。 |
| `search_options.enable_source` | DashScope 专用；开启平台搜索结果列表。 |
| `search_options.enable_citation` | DashScope 专用，需 `enable_source: true`；在回答内加引用角标。 |
| `search_options.citation_format` | DashScope 专用，`[<number>]` 或 `[ref_<number>]`。 |
| `search_options.prepend_search_result` | DashScope 流式专用，提前返回来源；不支持 OpenAI 兼容方式。 |

来源：[1] 的“核心能力”“强制联网搜索”“设置搜索量级策略”“限定搜索来源站点”“通过自然语言控制检索范围”；基础请求类型另见 [2]。

## 来源响应路径

DashScope 原生 `POST .../api/v1/services/aigc/text-generation/generation` 开启 `parameters.enable_search` 与 `parameters.search_options.enable_source` 后，官方示例为：[1]

```text
output.search_info.search_results[]
  .index / .title / .url / .site_name / .icon
output.choices[0].message.content
usage.plugins.search.count
```

该来源列表用于核对模型引用的 URL 是否实际出现在搜索结果中；示例没有保证提供网页全文、逐字段证据摘录或最终事实正确性。不能仅靠来源 URL 出现就认定页数/价格可靠。

Responses API 在专门“获取搜索来源”章节的路径是 `output[type=web_search_call].action.sources[]`，与 Chat 不同；其工具方案和模型兼容也不同，不能在现有 Chat JSON 解码器中假定出现。[1] 同页总览表把 Responses“返回搜索来源”标作不支持，与后面的专门章节不一致；本轮不据此推动协议迁移。

## JSON、思考和指定 URL

`response_format: {"type":"json_object"}` 约束格式而非事实可靠性，且 system/user message 必须出现 `JSON` 关键词；`Qwen-Plus` 非思考模式在支持列表。官方对思考模式 JSON 的支持有按型号区分，不应把某个新模型规则泛化到所有 `qwen-plus` 别名。[3]

普通联网搜索文档没有“按提供的原始 query 原封不动搜索”参数；FAQ 描述原始问题经过多次 query 改写。因此，书名、作者、ISBN 和结构化任务可能如何改写，是需要实际对照的变量，不能靠 `forced_search` 证明搜索到正确书。[1]

直接网页阅读是独立 `web_extractor` 能力。Chat 方案要求 `enable_search: true`、`search_strategy: agent_max`、思考及流式输出；`qwen-plus-latest` 未列入支持模型。官方网页抓取文档与联网搜索文档对部分较新型号范围存在差异，但均未列本轮旧别名。因此不能仅把 URL 放入提示词就宣称模型已经打开并读过该页。[1][4]

另一个确定边界是账号级联网搜索 15 RPS：超限时 API 不报错但不触发搜索；本次单书连续请求并不足以证明触发此条件。[1]

## 对修复的建议（非已验证结果）

优先做同模型、同字段、同截止时间下的简单自然语言问题与结构化提示词对照，以及 `turbo` / `max` 对照；记录真实返回和延迟，保持身份证据及空值规则。若需证明 provider 实际检索过哪些页面，应另行评估 DashScope 原生来源返回，而非伪装成 Chat 支持。不要自动切模型或协议、不硬编码本书资料、不因书店/出版社页数冲突猜填。

## 后续真机对照与修复结果

同日主代理在用户授权下，使用 App 内保存的百炼配置完成了只读对照；本节与上面的官方文档核查阶段区分，不导出密钥，也不把诊断结果写入书库。

- 原单条结构化消息在默认策略、`max`、搜索意图干预三组中都未返回事实。原生来源列表显示主要搜到作者人物页和其他图书。
- 将合同与简短图书问题分为 system/user 后，平台来源列表能定位目标书及增订版；但让模型自写 URL 仍出现虚构链接，不能把字段碰巧匹配当成证据可靠。
- 原生启用来源与引用角标后，模型输出 `[ref_n]`，App 将其映射到同次平台结果并继续原 URL/身份/字段校验。两次生产逻辑真机调用均获得 `2023-08-01`、`人民币88.00元` 和 `376` 页；前两项与独立公开资料核查一致，页数仍有 376/356 冲突。没有升级或切换用户模型。
- 实现及边界见设计第 27 节、计划 6.16/8.5；正常构建通过 604+3 测试并无线安装。本修复没有采用实验中无效的 `max`/搜索干预参数，也没有给 Chat 接口添加它不支持的来源选项。

## 官方来源（索引）

1. 阿里云《联网搜索》：<https://help.aliyun.com/zh/model-studio/web-search>。重点锚点：策略 `#5a7d30420fc5k`；强制搜索 `#6f83c89f7dw0v`；来源 `#17ac5c28bdahf`；限定站点 `#95oc6uryup2j2`；自然语言范围 `#f58e95a5cam6f`；是否执行搜索 `#32e3bcbbe7fi3`；Responses 来源 `#ws_resp_get_sources`。
2. 阿里云《OpenAI 兼容-Chat》：<https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions>。
3. 阿里云《结构化输出》：<https://help.aliyun.com/zh/model-studio/json-mode>（正文链接亦使用 <https://help.aliyun.com/zh/model-studio/qwen-structured-output>）。
4. 阿里云《网页抓取》：<https://help.aliyun.com/zh/model-studio/web-extractor>。

## 后续核查：DashScope 原生非流式诊断请求

继续只读核对官方文档，未发送以下请求。原生接口可返回平台搜索来源，适合区分“没有检索结果”与“模型没有采用检索结果”，但并不承诺解决漏补。

官方 [Base URL 总览](https://help.aliyun.com/zh/model-studio/base-url) 明确旧 `dashscope.aliyuncs.com` 等共享域名仍可使用，原生 API 在相同地域域名下使用 `/api/v1`。北京原生文本请求 URL：`https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation`。不要为此将既有密钥发送到不同地域、用户未配置或未验证的域名。

请求头为 `Authorization: Bearer <既有密钥>`、`Content-Type: application/json`。非流式不发送 `X-DashScope-SSE: enable`；HTTP 的 `stream` 不是必需项。下面是仅用于诊断的最小有界请求体；关键词中的具体书仅为复现用例，不能硬编码进产品逻辑。

```json
{
  "model": "qwen-plus-latest",
  "input": {
    "messages": [
      {
        "role": "user",
        "content": "请联网查询《南怀瑾的最后100天》，作者王国平，ISBN 9787559860774。只按实际来源报告出版日期、人民币定价与页数；无可靠来源请说明，不要编造。"
      }
    ]
  },
  "parameters": {
    "enable_thinking": false,
    "enable_search": true,
    "search_options": {
      "forced_search": true,
      "enable_source": true
    },
    "result_format": "message",
    "max_tokens": 4096
  }
}
```

如需 JSON，可在 `parameters` 加 `"response_format":{"type":"json_object"}`，并在 message 中明确写出 `JSON`。`result_format` 管外层结构（`message` vs `text`），`response_format` 管模型回答文本，两个参数不是同义。`max_tokens` 已标记未来弃用，但当前仍有官方定义；不要直接改用旧模型未列支持的 `max_completion_tokens`。

解码顺序/路径：先检查 HTTP 状态，再读取 `output.choices[0].message.content`（本模型为字符串；JSON 回答需二次解码）、`output.choices[0].finish_reason`、`output.search_info.search_results[]`、`usage.input_tokens` / `output_tokens` / `total_tokens`、`usage.plugins.search.count` 与 `request_id`。`finish_reason: length` 是截断而不是完整空结果；`search_results` 元素包含 `index`、`title`、`url`、`site_name`、`icon`，未承诺包含全文。不要要求 Python SDK 的 `status_code` 字段一定出现在原始 HTTP 成功 JSON 中。

依据：[DashScope API 参考](https://help.aliyun.com/zh/model-studio/qwen-api-via-dashscope) 的请求参数和“chat 响应对象”章节；[深度思考支持模型](https://help.aliyun.com/zh/model-studio/deep-thinking#78286fdc35hlw) 明确列出 `qwen-plus-latest` 为混合思考、默认关闭；联网搜索支持及来源字段另见 [1]。所有模型可用性还受账号授权、地域和实际服务返回约束，本轮未以文档替代真实请求成功证明。
