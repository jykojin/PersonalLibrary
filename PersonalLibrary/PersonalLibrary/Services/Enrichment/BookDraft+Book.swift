import Foundation

extension BookDraft {
    init(book: Book) {
        self.init(
            title: book.title,
            author: book.author,
            translator: book.translator,
            isbn: book.isbn,
            publisher: book.publisher,
            publishDate: book.publishDate,
            totalPages: book.totalPages,
            price: book.price,
            bookDescription: book.bookDescription,
            authorDescription: book.authorDescription,
            aiIntroduction: book.bookIntroduction,
            rating: book.rating,
            notes: book.notes
        )
    }
}

extension EnrichmentOutcome {
    func rebased(on currentDraft: BookDraft) -> EnrichmentOutcome {
        var merged = currentDraft

        for field in EnrichmentField.allCases
        where !draft.hasSameValue(as: originalDraft, for: field)
            && currentDraft.hasSameValue(as: originalDraft, for: field) {
            merged.copyValue(for: field, from: draft)
        }

        return EnrichmentOutcome(
            originalDraft: currentDraft,
            draft: merged,
            sourceReports: sourceReports,
            aiStatus: aiStatus,
            evidence: evidence,
            rejections: rejections,
            tokenUsage: tokenUsage,
            termination: termination
        )
    }

    func apply(to book: Book) {
        let merged = rebased(on: BookDraft(book: book)).draft
        book.title = merged.title
        book.author = merged.author
        book.translator = merged.translator
        book.publisher = merged.publisher
        book.publishDate = merged.publishDate
        book.totalPages = merged.totalPages
        book.price = merged.price
        book.bookDescription = merged.bookDescription
        book.authorDescription = merged.authorDescription
        book.bookIntroduction = merged.aiIntroduction
    }
}
