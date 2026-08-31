"""AI介绍 的校验与归一化规则（纯函数，可单测）。

设计原则：**判据来自标杆样板本身**。《平面国》样板必须无条件通过，
库里现存的模板垃圾必须逐条被打回 —— 两端都锁在 test_validate.py 里。

阈值比契约给 agent 的目标区间宽（契约要 700–1000，这里放到 550–1400）：
契约是"往哪写"，校验是"什么绝不能要"。写得比样板略短略长不值得重跑一次。
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from difflib import SequenceMatcher

# 篇幅红线（非空白字符数）。标杆样板实测 694 字，契约目标 700–1000。
# 下限刻意只比目标低 100：实测下限设在 550 时，109 段（13%）挤在 550–599 ——
# agent 优化的是闸门而不是目标，缝隙太大就会出现「顶到刚过线」的最小补丁。
MIN_CHARS = 600
MAX_CHARS = 1400

# 判定"抄豆瓣简介"的连续重合字数
PLAGIARISM_RUN = 40

# track B 查不到资料时的合法留空标记（AGENT_TASK.md 教 agent 这么写）
INSUFFICIENT_MARKER = "[资料不足]"

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
PLACEHOLDER_LITERALS = ("[待补充]",)

# 这两个词只有「裸露」出现时才是脏数据（Python 值漏进正文）。
# 正文允许写英文书名，`And Then There Were None`、`None of the Above` 都是正常内容，
# 早先按子串匹配会把它们连坐 —— pk 1308《无人生还》实际踩过，agent 只能删掉英文原名才过。
PLACEHOLDER_WORDS = ("None", "undefined")
_ENGLISH_TAIL = re.compile(r"[A-Za-z][A-Za-z'’-]*\s*$")
_ENGLISH_HEAD = re.compile(r"[A-Za-z]")


def duplicate_pks(pks: Iterable[int]) -> list[int]:
    """找出出现多于一次的 pk（升序、每个只列一次）。

    两个 agent 并发 Edit 同一份稿件时会写出重复的 `### pk` 段。
    这种稿件必须打回：`merge` 只会让后写的那份静默覆盖前一份，
    质量更好的那版可能就这么没了，且不留痕迹。
    """
    seen: set[int] = set()
    dupes: set[int] = set()
    for pk in pks:
        if pk in seen:
            dupes.add(pk)
        seen.add(pk)
    return sorted(dupes)


def leaked_placeholders(text: str) -> list[str]:
    """找出裸露的占位符值。夹在英文词之间的一律视为正常英文行文。"""
    hits: list[str] = []
    for word in PLACEHOLDER_WORDS:
        pattern = re.compile(rf"(?<![A-Za-z0-9]){re.escape(word)}(?![A-Za-z0-9])")
        for m in pattern.finditer(text):
            before, after = text[: m.start()], text[m.end() :]
            in_english = bool(_ENGLISH_TAIL.search(before)) or bool(
                _ENGLISH_HEAD.match(after.lstrip())
            )
            if not in_english:
                hits.append(word)
                break
    return hits


# 行首 markdown 标记：App 里是 Text 直出，写了会原样显示
MARKDOWN_LINE_PATTERN = re.compile(r"^\s*(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|\|)")
MARKDOWN_INLINE_PATTERN = re.compile(r"\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`")


def title_candidates(title: str) -> list[str]:
    """书名的可接受写法集合。

    库里大量书名带版本/丛书装饰 —— `倚天屠龙记(共四册)`、
    `红楼梦（珍藏版 无障碍阅读）/语文新课标课外阅读丛书`、
    `走向世界的中国作家系列丛书：寻死无门（精装）`。正文该写作品本名，
    要求整个字符串原样出现会把正确的文章全部误判掉（跑批时真的发生了）。

    这个判定的目的是抓「写成了另一本书」，不是核对版本字样，所以宁宽勿严：
    任何一种候选写法出现在导语段即放行。
    """
    raw = (title or "").strip()
    if not raw:
        return []

    candidates = {raw}
    # 斜杠后多是丛书名：`字绘上海/手绘中国`
    candidates.add(raw.split("/")[0])
    # 冒号两侧：`丛书名：作品名` 与 `三国英雄记5：鼎足成三分`
    for part in re.split(r"[：:]", raw):
        candidates.add(part)
    # 去掉括号及其内容：`(共四册)`、`（精装）`、`(精)`、`(上下)`
    stripped = re.sub(r"[（(\[【][^）)\]】]*[）)\]】]?", "", raw)
    candidates.add(stripped)
    candidates.add(stripped.split("/")[0])
    for part in re.split(r"[：:]", stripped):
        candidates.add(part)

    # 两字以下的碎片没有区分力（会把任意正文都判成命中）
    return sorted(
        {c.strip() for c in candidates if len(c.strip()) >= 2}, key=len, reverse=True
    )


# 比对书名时要忽略的标点与空白（正文常补上引号、书名号）
TITLE_PUNCT_PATTERN = re.compile(
    r"[\s“”\"'‘’（）()\[\]【】《》〈〉「」『』·,，.。、:：;；!！?？~～—\-–_/\\|]+"
)

# 繁简/异体兜底：核心书名有多少比例的字出现在导语段里才算命中
TITLE_OVERLAP_RATIO = 0.5
TITLE_OVERLAP_MIN_CHARS = 3


def strip_title_punct(text: str) -> str:
    return TITLE_PUNCT_PATTERN.sub("", text or "")


LEAD_TITLE_PATTERN = re.compile(r"《([^》]{1,80})》")


def title_matches_lead(title: str, lead: str) -> bool:
    """导语段里的书名是否对得上库里的书名。

    三层放行，从严到宽：
    1. 候选写法原样出现（含去掉版本装饰后的本名）
    2. 双方都去掉标点后出现 —— 正文补引号的情况，如库里 `对伪心理学说不`
       而正文写《对"伪心理学"说不》（后者才是该书实际书名）
    3. 核心书名的字有一半以上出现在导语段 —— 繁简差异的兜底，如库里繁体
       `尋找家園` 而正文写简体《寻找家园》。没装 opencc/zhconv，用字符重合率替代
    """
    candidates = title_candidates(title)
    if not candidates:
        return True

    if any(c in lead for c in candidates):
        return True

    lead_clean = strip_title_punct(lead)
    if any(strip_title_punct(c) in lead_clean for c in candidates):
        return True

    core = strip_title_punct(min(candidates, key=len))
    if len(core) >= TITLE_OVERLAP_MIN_CHARS:
        hit = len(set(core) & set(lead_clean)) / len(set(core))
        if hit >= TITLE_OVERLAP_RATIO:
            return True

    return False


def title_mismatch(title: str, lead: str) -> str | None:
    """书名对不上时返回一句供人工确认的说明，对得上返回 None。

    **这不是打回理由。** 书名校验在实测中的误判率约 7%（75 本里 5 次），
    每次误拒都要重跑一轮；而 agent 拿着某本书的确切原料、写进以 pk 为键的槽位，
    写错书的概率极低。三类合法差异 `title_matches_lead` 都盖不住：
    繁简（`納蘭詞箋注` → `纳兰词笺注`，字符重合率仅 0.2）、
    中译名（`Harry Potter and the Chamber of Secrets` → `哈利·波特与密室`，零重合）、
    以及正文自行补全的实际书名。

    所以改为：格式问题（连书名号都没有）才打回；书名对不上只登记，由人汇总看。
    """
    if title_matches_lead(title, lead):
        return None
    found = LEAD_TITLE_PATTERN.search(lead)
    written = found.group(1) if found else "（无）"
    return f"库里「{title}」，正文写《{written}》"


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


# 比对抄袭前要剥掉的东西：空白与各类标点。
# 「连续 N 字」这个指标不剥标点就是摆设 —— 跑批时真有 agent 把 46 字的照抄段
# 删掉一个逗号变成 29 字连续就放行了，正文仍是逐字照搬。
COMPARE_NOISE_PATTERN = re.compile(
    r"[\s，。、；：！？“”‘’（）《》〈〉「」『』—…·,.;:!?\"'()\[\]{}<>/\\|~\-–_*#&@]+"
)


def strip_for_compare(text: str) -> str:
    return COMPARE_NOISE_PATTERN.sub("", text or "")


def longest_common_run(a: str, b: str) -> int:
    """两段文本最长连续公共子串的长度。用来判是否整段照抄。

    调用方应先过 `strip_for_compare`，否则删几个标点就能绕过阈值。
    """
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


def is_insufficient(text: str) -> bool:
    """这一段是 track B 查不到资料时的合法留空标记。"""
    return (text or "").strip().startswith(INSUFFICIENT_MARKER)


def validate_intro(text: str, *, title: str, douban_intro: str = "") -> list[str]:
    """返回打回原因列表；空列表表示通过。"""
    reasons: list[str] = []

    if not text or not text.strip():
        return ["正文为空"]

    # track B 查不到资料时的合法留空。契约教 agent 这么写，校验就必须认 ——
    # 否则 agent 照文档做会陷入永远达不到「全部合格」的死循环（跑批时真的发生了）。
    if is_insufficient(text):
        return []

    count = char_count(text)
    if count < MIN_CHARS:
        reasons.append(f"篇幅过短（{count} 字，下限 {MIN_CHARS}）")
    elif count > MAX_CHARS:
        reasons.append(f"篇幅过长（{count} 字，上限 {MAX_CHARS}）")

    headings, items, lead = _classify_lines(text)

    # 书名对不对得上不在这里判（误判率高，见 title_mismatch 的说明）；
    # 这里只管格式：导语段必须有《书名号》，否则是没照契约写
    if not LEAD_TITLE_PATTERN.search(lead):
        reasons.append("导语段没有《书名号》包住书名")

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
    for word in leaked_placeholders(text):
        reasons.append(f"出现占位符「{word}」")

    for line in text.split("\n"):
        if MARKDOWN_LINE_PATTERN.match(line):
            reasons.append(f"出现 markdown 行首标记：{line.strip()[:20]}")
            break
    inline = MARKDOWN_INLINE_PATTERN.search(text)
    if inline:
        reasons.append(f"出现 markdown 行内标记：{inline.group()[:20]}")

    if douban_intro:
        # 先剥标点再比：否则删一个逗号就能把 46 字连续拆成 29 字蒙过去
        run = longest_common_run(
            strip_for_compare(text), strip_for_compare(douban_intro)
        )
        if run >= PLAGIARISM_RUN:
            reasons.append(f"与豆瓣简介连续重合 {run} 字（已忽略标点），判定为抄原文")

    return reasons
