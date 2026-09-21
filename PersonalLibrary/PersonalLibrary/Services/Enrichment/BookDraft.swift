import Foundation

struct BookDraft: Equatable, Sendable {
    var title: String
    var author: String
    var translator: String?
    var isbn: String?
    var publisher: String?
    var publishDate: Date?
    var totalPages: Int
    var price: String?
    var bookDescription: String?
    var authorDescription: String?
    var aiIntroduction: String?
    var rating: Int?
    var notes: String?

    init(
        title: String,
        author: String,
        translator: String? = nil,
        isbn: String? = nil,
        publisher: String? = nil,
        publishDate: Date? = nil,
        totalPages: Int = 0,
        price: String? = nil,
        bookDescription: String? = nil,
        authorDescription: String? = nil,
        aiIntroduction: String? = nil,
        rating: Int? = nil,
        notes: String? = nil
    ) {
        self.title = title
        self.author = author
        self.translator = translator
        self.isbn = isbn
        self.publisher = publisher
        self.publishDate = publishDate
        self.totalPages = totalPages
        self.price = price
        self.bookDescription = bookDescription
        self.authorDescription = authorDescription
        self.aiIntroduction = aiIntroduction
        self.rating = rating
        self.notes = notes
    }

    var missingFields: Set<EnrichmentField> {
        var fields = Set<EnrichmentField>()
        if Self.isBlank(title) { fields.insert(.title) }
        if Self.isBlank(author) || author.trimmingCharacters(in: .whitespacesAndNewlines) == "未知作者" {
            fields.insert(.author)
        }
        if Self.isBlank(translator) { fields.insert(.translator) }
        if Self.isBlank(publisher) { fields.insert(.publisher) }
        if publishDate == nil { fields.insert(.publishDate) }
        if totalPages <= 0 { fields.insert(.totalPages) }
        if Self.isBlank(price) { fields.insert(.price) }
        if Self.descriptionNeedsRefresh(bookDescription) { fields.insert(.bookDescription) }
        if Self.descriptionNeedsRefresh(authorDescription) { fields.insert(.authorDescription) }
        if Self.isBlank(aiIntroduction) { fields.insert(.aiIntroduction) }
        return fields
    }

    func fillingMissingFields(
        from candidate: BookDraft,
        limitedTo fields: Set<EnrichmentField>
    ) -> BookDraft {
        var result = self
        let accepted = fields
            .intersection(missingFields)
            .subtracting(candidate.missingFields)

        for field in accepted {
            result.copyValue(for: field, from: candidate)
        }
        return result
    }

    func hasSameValue(as other: BookDraft, for field: EnrichmentField) -> Bool {
        switch field {
        case .title: return title == other.title
        case .author: return author == other.author
        case .translator: return translator == other.translator
        case .publisher: return publisher == other.publisher
        case .publishDate: return publishDate == other.publishDate
        case .totalPages: return totalPages == other.totalPages
        case .price: return price == other.price
        case .bookDescription: return bookDescription == other.bookDescription
        case .authorDescription: return authorDescription == other.authorDescription
        case .aiIntroduction: return aiIntroduction == other.aiIntroduction
        }
    }

    mutating func copyValue(for field: EnrichmentField, from source: BookDraft) {
        switch field {
        case .title: title = source.title
        case .author: author = source.author
        case .translator: translator = source.translator
        case .publisher: publisher = source.publisher
        case .publishDate: publishDate = source.publishDate
        case .totalPages: totalPages = source.totalPages
        case .price: price = source.price
        case .bookDescription: bookDescription = source.bookDescription
        case .authorDescription: authorDescription = source.authorDescription
        case .aiIntroduction: aiIntroduction = source.aiIntroduction
        }
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func descriptionNeedsRefresh(_ value: String?) -> Bool {
        isBlank(value) || value?.contains("展开全部") == true
    }
}
