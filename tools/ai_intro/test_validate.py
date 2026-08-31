"""AI介绍 校验规则的测试。

标杆用真实的《平面国》样板（必须通过），反面用库里真实的模板垃圾（必须逐条被打回）。
"""

import pytest

from validate import longest_common_run, normalize_indent, validate_intro

# 契约里的标杆样板，实测 694 个非空白字符
FLATLAND = """《平面国》（Flatland）是英国学者埃德温·阿伯特于1884年出版的一部兼具高维数学启蒙与维多利亚时代社会讽刺的科幻寓言奇书。它以极具创意的几何视角，讲述了一个发生在二维平面的故事。

几何构筑的世界与阶级隐喻
 严格的几何阶级： 在这个只有长和宽的二维世界里，所有居民都是几何图形。图形的边数和对称性决定社会地位——底层的劳工和士兵是狭长的等腰三角形，中产阶级是正方形和正多边形，而统治阶层（祭司）则是边数极多、接近圆形的几何体。
 对现实的讽刺： 作者借由这种荒诞的几何设定，尖锐地讽刺了19世纪英国社会僵化的阶级固化、教条主义以及对女性的压迫（在平面国中，女性只是极其危险且没有任何社会地位的单一条线）。

跨越维度的思想冲击
 降维与升维的震撼： 主角是一个正方形。他先是在梦中遇到了零维（点国）和一维（线国）的居民，发现他们完全无法理解"长"或"宽"的概念；随后，一位来自三维立体国（Spaceland）的"球体"拜访了他，并将他拉出平面，让他亲眼见识了三维世界的奇妙。
 对未知维度的推演： 领悟了三维的正方形进而大胆推测：既然有三维，就一定存在四维乃至更高维度的世界。然而，原本扮演"启蒙者"的球体却对此感到被冒犯并愤怒否定。

这本书的独特价值
 数学与科幻启蒙： 它开创了用"低维想象高维"的思考模型。直到今天，许多物理学家（如讲解广义相对论或弦理论时）仍在使用《平面国》的逻辑来帮助人类大脑直观理解四维空间。
 人性的认知局限： 故事结尾，正方形因向平面国同胞宣扬"三维世界"而被视为异端关进监狱。它揭示了人类最深刻的悲剧之一：人们往往固执地坚信自己所见即是全部真相，并对超出认知范围的真理抱有天然的恐惧与排斥。"""

# 库里 pk=3 的真实数据，模板生成的垃圾
REAL_GARBAGE = """《S.》是由Dorst, Doug创作或编著的综合性读物，由Mulholland Books于2013年出版。

内容概览
One book. Two readers. A world of mystery, menace, and desire……

主题与特色
本书重点涉及T1。作品从具体问题出发组织材料，兼顾信息、观点与阅读体验。

阅读价值
适合先通过目录和章节标题把握结构，再围绕最关心的问题深入阅读并记录关键观点。"""


def reasons_for(text, title="平面国", douban_intro=""):
    return validate_intro(text, title=title, douban_intro=douban_intro)


class TestGoldStandard:
    def test_标杆样板必须通过(self):
        assert reasons_for(FLATLAND) == []

    def test_全角空格缩进的同一段也必须通过(self):
        # 契约初版写的是全角空格，跑批时两种都会出现，都得认
        swapped = FLATLAND.replace("\n ", "\n　")
        assert reasons_for(swapped) == []


class TestRealGarbage:
    def test_真实模板垃圾必须被打回(self):
        assert reasons_for(REAL_GARBAGE, title="S.") != []

    @pytest.mark.parametrize(
        "fragment",
        ["创作或编著", "综合性读物", "本书重点涉及", "占位符", "通用小标题", "截断"],
    )
    def test_打回原因覆盖各个病灶(self, fragment):
        joined = " ".join(reasons_for(REAL_GARBAGE, title="S."))
        assert fragment in joined


class TestLength:
    def test_太短打回(self):
        assert any(
            "过短" in r
            for r in reasons_for("《测试》是一本书。\n\n小标题\n 要点： 说明。")
        )

    def test_太长打回(self):
        bloated = FLATLAND + "补充说明。" * 200
        assert any("过长" in r for r in reasons_for(bloated))


class TestStructure:
    def test_缺少分节标题打回(self):
        flat = "《平面国》是一部小说。" + "内容展开说明。" * 90
        assert any("分节" in r for r in reasons_for(flat))

    def test_缺少条目打回(self):
        no_items = "《平面国》是一部小说。\n\n" + "\n\n".join(
            f"分节标题{i}\n" + "这里是没有缩进的大段说明。" * 20 for i in range(3)
        )
        assert any("条目" in r for r in reasons_for(no_items))

    def test_首段不含书名打回(self):
        assert any(
            "书名" in r for r in reasons_for(FLATLAND, title="另一本完全不同的书")
        )


class TestTitleWithEditionNoise:
    """库里大量书名带版本/丛书装饰，正文只该出现作品本名。

    这三个书名是跑批时真的被误判过的，锁在这里防回归。
    """

    @pytest.mark.parametrize(
        "full_title,lead_title",
        [
            ("倚天屠龙记(共四册)", "倚天屠龙记"),
            ("红楼梦（珍藏版 无障碍阅读）/语文新课标课外阅读丛书", "红楼梦"),
            ("走向世界的中国作家系列丛书：寻死无门（精装）", "寻死无门"),
            ("瓷器鉴藏全书(精)", "瓷器鉴藏全书"),
            ("侠客行(上下)", "侠客行"),
            ("字绘上海/手绘中国", "字绘上海"),
        ],
    )
    def test_正文用作品本名不算缺书名(self, full_title, lead_title):
        text = FLATLAND.replace("《平面国》", f"《{lead_title}》", 1)
        reasons = reasons_for(text, title=full_title)
        assert not any("书名" in r for r in reasons), reasons

    def test_丛书名整体出现也放行(self):
        text = FLATLAND.replace("《平面国》", "《三国英雄记5：鼎足成三分》", 1)
        assert not any(
            "书名" in r for r in reasons_for(text, title="三国英雄记5：鼎足成三分")
        )

    def test_写成完全另一本书仍要打回(self):
        text = FLATLAND.replace("《平面国》", "《水浒传》", 1)
        assert any("书名" in r for r in reasons_for(text, title="倚天屠龙记(共四册)"))


class TestTitleVariantForms:
    """库里书名与正文的合理变体：繁简、插入标点。

    这两例是跑第 003 批时真的被误判过的，而 agent 写的其实比库里的更准。
    """

    def test_库里繁体正文简体不算缺书名(self):
        # 库里 '尋找家園'（高尔泰），正文写简体《寻找家园》—— 全中文界面里简体才对
        text = FLATLAND.replace("《平面国》", "《寻找家园》", 1)
        reasons = reasons_for(text, title="尋找家園")
        assert not any("书名" in r for r in reasons), reasons

    def test_正文补上引号不算缺书名(self):
        # 库里 '对伪心理学说不'，正文写《对"伪心理学"说不》—— 这才是该书实际书名
        text = FLATLAND.replace("《平面国》", '《对"伪心理学"说不》', 1)
        reasons = reasons_for(text, title="对伪心理学说不")
        assert not any("书名" in r for r in reasons), reasons

    def test_繁简兜底不会放过另一本书(self):
        text = FLATLAND.replace("《平面国》", "《水浒传》", 1)
        assert any("书名" in r for r in reasons_for(text, title="尋找家園"))


class TestForbiddenPatterns:
    def test_省略号结尾打回(self):
        assert any("截断" in r for r in reasons_for(FLATLAND[:-1] + "……"))

    def test_展开全部残留打回(self):
        assert any("展开全部" in r for r in reasons_for(FLATLAND + "(展开全部)"))

    def test_markdown_符号打回(self):
        with_md = FLATLAND.replace(
            "几何构筑的世界与阶级隐喻", "## 几何构筑的世界与阶级隐喻"
        )
        assert any("markdown" in r.lower() for r in reasons_for(with_md))

    def test_占位符打回(self):
        assert any(
            "占位符" in r for r in reasons_for(FLATLAND.replace("阶级固化", "T1"))
        )


class TestPlagiarism:
    def test_整段照抄豆瓣简介打回(self):
        stolen = FLATLAND.split("\n")[3][1:]  # 拿一整条正文当作"豆瓣原文"
        assert any("抄" in r for r in reasons_for(FLATLAND, douban_intro=stolen))

    def test_短句重合不算抄(self):
        assert (
            reasons_for(FLATLAND, douban_intro="讲述了一个发生在二维平面的故事") == []
        )


class TestLongestCommonRun:
    def test_找出最长连续重合(self):
        assert longest_common_run("abcdefg", "xxcdexx") == 3

    def test_无重合为零(self):
        assert longest_common_run("abc", "xyz") == 0

    def test_空串安全(self):
        assert longest_common_run("", "abc") == 0


class TestNormalizeIndent:
    def test_全角缩进归一为半角(self):
        assert normalize_indent("小标题\n　要点： 说明") == "小标题\n 要点： 说明"

    def test_多个空格压成一个(self):
        assert normalize_indent("小标题\n   要点： 说明") == "小标题\n 要点： 说明"

    def test_标题行不受影响(self):
        assert normalize_indent("小标题\n 要点： 说明") == "小标题\n 要点： 说明"

    def test_行尾空白清掉(self):
        assert normalize_indent("小标题  \n 要点： 说明  ") == "小标题\n 要点： 说明"
