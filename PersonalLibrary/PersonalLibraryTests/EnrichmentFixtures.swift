import Foundation

enum EnrichmentFixtures {
    static let doubanSingleTranslatorHTML = """
    <html><head><meta property="og:image" content="https://img.example/cover.jpg"></head><body>
    <span property="v:itemreviewed">示例图书</span>
    <div id="info">
    <span class="pl">作者:</span> <a>示例作者</a><br/>
    <span class="pl">译者:</span> <a>示例译者</a><br/>
    <span class="pl">出版社:</span> 示例出版社<br/>
    <span class="pl">出版年:</span> 2024-03<br/>
    <span class="pl">页数:</span> 320<br/>
    <span class="pl">定价:</span> 58.00元<br/>
    <span class="pl">ISBN:</span> 978-7-0200-0220-7<br/>
    </div>
    <div class="intro"><p>完整图书简介。</p></div>
    <div class="indent"><span>作者简介</span><div class="intro"><p>完整作者简介。</p></div></div>
    </body></html>
    """

    static let doubanMultipleTranslatorsHTML = """
    <html><body><span property="v:itemreviewed">示例图书</span><div id="info">
    <span class="pl">作者:</span> <a>示例作者</a><br/>
    <span class="pl">译者:</span> <a>译者甲</a> / <a>译者乙</a><br/>
    </div></body></html>
    """

    static let doubanPlainTextTranslatorHTML = """
    <html><body><span property="v:itemreviewed">示例图书</span><div id="info">
    <span class="pl">作者:</span> <a>示例作者</a><br/>
    <span class="pl">译者:</span> 译者丙 / 译者丁<br/>
    </div></body></html>
    """

    static let doubanMixedTranslatorHTML = """
    <html><body><span property="v:itemreviewed">示例图书</span><div id="info">
    <span class="pl">作者:</span> <a>示例作者</a><br/>
    <span class="pl">译者:</span> <a>译者甲</a> / 译者乙<br/>
    </div></body></html>
    """
}
