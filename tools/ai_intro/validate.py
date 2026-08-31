"""AI介绍 的校验与归一化规则（纯函数，可单测）。

设计原则：**判据来自标杆样板本身**。《平面国》样板必须无条件通过，
库里现存的模板垃圾必须逐条被打回 —— 两端都锁在 test_validate.py 里。

阈值比契约给 agent 的目标区间宽（契约要 800–1100，这里放到 550–1400）：
契约是"往哪写"，校验是"什么绝不能要"。写得比样板略短略长不值得重跑一次。
"""

from __future__ import annotations

import re
from difflib import SequenceMatcher

# 篇幅红线（非空白字符数）。标杆样板实测 694 字，下限压到 550 留出余地。
MIN_CHARS = 550
MAX_CHARS = 1400

# 判定"抄豆瓣简介"的连续重合字数
PLAGIARISM_RUN = 40

# 结构下限
MIN_SECTIONS = 2
MIN_ITEMS = 4

# 分节标题的长度上限：超过就不是标题而是正文了
MAX_HEADING_CHARS = 20

# 条目行的缩进：契约初版写全角空格 U+3000，样板实际用半角空格 U+0020，两种都认
INDENT_CHARS = (" ", "　", "\t")

# 模板句 —— 现存 2856 条垃圾的病灶，逐条禁掉
TEMPLATE_PHRASES = (
    "创作或编著",
    "综合性读物",
    "本书重点涉及",
    "可通过摘录、仿写和修订",
    "兼顾信息、观点与阅读体验",
)

# 通用小标题 —— 用它们充数就等于没概括内容。精确匹配整行，
# 所以「这本书的独特价值」不会被「阅读价值」误伤。
GENERIC_HEADINGS = frozenset(
    {
        "内容概览",
        "内容简介",
        "主题与特色",
        "阅读价值",
        "简介",
        "概述",
        "总结",
        "基本信息",
    }
)

# 截断痕迹：豆瓣折叠版简介的残留标记，以及被截断的省略号
TRUNCATION_MARKERS = ("……", "展开全部")

# 占位符。故意**不**收「未知」—— 标杆样板里就有「对未知维度的推演」，
# 收了会把好文章打回。T1/T2 这类是旧模板真的漏出来过的。
PLACEHOLDER_PATTERN = re.compile(r"(?<![A-Za-z0-9])T[0-9](?![0-9])")
PLACEHOLDER_LITERALS = ("None", "undefined", "[待补充]")

# 行首 markdown 标记：App 里是 Text 直出，写了会原样显示
MARKDOWN_LINE_PATTERN = re.compile(r"^\s*(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|\|)")
MARKDOWN_INLINE_PATTERN = re.compile(r"\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`")


def char_count(text: str) -> int:
    """非空白字符数 —— 中文正文的"字数"用这个量最直观。"""
    return len(re.sub(r"\s", "", text))


def normalize_indent(text: str) -> str:
    """把条目行的缩进统一成一个半角空格（对齐标杆样板），并清掉行尾空白。

    agent 可能用全角空格、多个空格或 tab；2904 条里混着几种缩进会很难看，
    所以写回数据库前统一过一遍。
    """
    lines = []
    for line in text.split("\n"):
        line = line.rstrip()
        stripped = line.lstrip("".join(INDENT_CHARS))
        if stripped != line and stripped:
            line = " " + stripped
        lines.append(line)
    return "\n".join(lines)


def longest_common_run(a: str, b: str) -> int:
    """两段文本最长连续公共子串的长度。用来判是否整段照抄。"""
    if not a or not b:
        return 0
    return (
        SequenceMatcher(None, a, b, autojunk=False)
        .find_longest_match(0, len(a), 0, len(b))
        .size
    )


def _classify_lines(text: str) -> tuple[list[str], list[str], str]:
    """把正文切成 (分节标题, 条目行, 导语段)。"""
    lines = [line for line in text.split("\n") if line.strip()]
    if not lines:
        return [], [], ""

    lead = lines[0]
    headings: list[str] = []
    items: list[str] = []

    for line in lines[1:]:
        if line.startswith(INDENT_CHARS):
            items.append(line.strip())
        elif char_count(line) <= MAX_HEADING_CHARS:
            headings.append(line.strip())
        # 既没缩进又很长 = 段落式正文，不计入任何一类

    return headings, items, lead


def validate_intro(text: str, *, title: str, douban_intro: str = "") -> list[str]:
    """返回打回原因列表；空列表表示通过。"""
    reasons: list[str] = []

    if not text or not text.strip():
        return ["正文为空"]

    count = char_count(text)
    if count < MIN_CHARS:
        reasons.append(f"篇幅过短（{count} 字，下限 {MIN_CHARS}）")
    elif count > MAX_CHARS:
        reasons.append(f"篇幅过长（{count} 字，上限 {MAX_CHARS}）")

    headings, items, lead = _classify_lines(text)

    if title and title.strip() and title.strip() not in lead:
        reasons.append(f"导语段没出现书名「{title}」")

    if len(headings) < MIN_SECTIONS:
        reasons.append(f"分节标题只有 {len(headings)} 个，至少要 {MIN_SECTIONS} 个")

    if len(items) < MIN_ITEMS:
        reasons.append(f"缩进条目只有 {len(items)} 条，至少要 {MIN_ITEMS} 条")

    for heading in headings:
        if heading in GENERIC_HEADINGS:
            reasons.append(f"分节标题用了通用小标题「{heading}」")

    for phrase in TEMPLATE_PHRASES:
        if phrase in text:
            reasons.append(f"出现模板句「{phrase}」")

    for marker in TRUNCATION_MARKERS:
        if marker in text:
            reasons.append(f"出现截断痕迹「{marker}」")

    if text.rstrip().endswith("..."):
        reasons.append("正文以 ... 结尾（截断痕迹）")

    placeholder = PLACEHOLDER_PATTERN.search(text)
    if placeholder:
        reasons.append(f"出现占位符「{placeholder.group()}」")
    for literal in PLACEHOLDER_LITERALS:
        if literal in text:
            reasons.append(f"出现占位符「{literal}」")

    for line in text.split("\n"):
        if MARKDOWN_LINE_PATTERN.match(line):
            reasons.append(f"出现 markdown 行首标记：{line.strip()[:20]}")
            break
    inline = MARKDOWN_INLINE_PATTERN.search(text)
    if inline:
        reasons.append(f"出现 markdown 行内标记：{inline.group()[:20]}")

    if douban_intro:
        run = longest_common_run(text, douban_intro)
        if run >= PLAGIARISM_RUN:
            reasons.append(f"与豆瓣简介连续重合 {run} 字，判定为抄原文")

    return reasons
