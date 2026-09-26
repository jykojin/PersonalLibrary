import Foundation

enum EnrichmentFixtures {
    // JSON-LD identity/edition excerpt fetched on 2026-09-26 from
    // https://www.goodreads.com/book/isbn/9787559860774 -> /book/show/213682104.
    static let goodreadsNanLastHundredDaysHTML = #"""
    <html><head><script type="application/ld+json">
    {"@type":"Book","name":"南怀瑾的最后100天(增订版)(精)",
     "author":[{"@type":"Person","name":"王国平"},{"@type":"Person","name":"WANG GUO PING"}],
     "isbn":"9787559860774","numberOfPages":0}
    </script></head></html>
    """#

    // Minimal excerpt fetched on 2026-09-25 from /isbn/9787559860774/ -> /subject/36432215/.
    static let doubanNanLastHundredDaysHTML = """
    <html><body><span property="v:itemreviewed">南怀瑾的最后100天</span><div id="info">
    <span><span class="pl"> 作者</span>:<a href="/search/author">王国平</a></span><br/>
    <span class="pl">出版社:</span><a>广西师范大学出版社</a><br>
    <span class="pl">ISBN:</span> 9787559860774<br/>
    </div></body></html>
    """

    // Minimal identity/publisher excerpt fetched on 2026-09-25 from
    // https://book.douban.com/isbn/9787573031891/ -> /subject/38546905/.
    static let doubanCultureYouthHTML = """
    <html><body>
    <span property="v:itemreviewed">文化中国的青春岁月（上下卷）《文化的江山》《走进宋画》作者  刘刚 李冬君 重磅力作</span>
    <div id="info">
    <span><span class="pl"> 作者</span>:
    <a href="/search/author">刘刚  李冬君 著</a></span><br/>
    <span class="pl">出版社:</span><a>海南出版社</a><br>
    <span class="pl">ISBN:</span> 9787573031891<br/>
    </div></body></html>
    """

    static let doubanSingleTranslatorHTML = """
    <html><head><meta property="og:image" content="https://img.example/cover.jpg"></head><body>
    <span property="v:itemreviewed">示例图书</span>
    <div id="info">
    <span class="pl">作者:</span> <a>示例作者</a><br/>
    <span class="pl">译者:</span> <a>示例译者</a><br/>
    <span class="pl">出版社:</span> 示例出版社<br/>
    <span class="pl">出版年:</span> 2026-8<br/>
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

    static let doubanTrailingColonTranslatorHTML = """
    <html><body><span property="v:itemreviewed">大便书</span><div id="info">
    <span><span class="pl"> 作者</span>:
    <a>[日] 寄藤文平</a> / <a>[日] 藤田纮一郎</a></span><br/>
    <span><span class="pl"> 译者</span>:
    <a>吴锵煌</a></span><br/>
    <span class="pl">ISBN:</span> 9787531723103<br/>
    </div></body></html>
    """

    static let doubanCommemorativeWithoutTranslatorHTML = """
    <html><body><span property="v:itemreviewed">大便书（纪念版）</span><div id="info">
    <span><span class="pl"> 作者</span>:
    <a>(日) 藤田纮一郎</a> / <a>（日）寄藤文平</a></span><br/>
    <span class="pl">出版社:</span> 四川科学技术出版社<br/>
    <span class="pl">出版年:</span> 2017-7-1<br/>
    <span class="pl">ISBN:</span> 9787536486003<br/>
    <span class="pl">页数:</span> 192<br/>
    <span class="pl">定价:</span> 39<br/>
    </div></body></html>
    """
}
