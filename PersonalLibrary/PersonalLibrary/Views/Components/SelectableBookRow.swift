import SwiftUI
import SwiftData

/// 多选模式下的书籍行（checkbox + BookRowView）
struct SelectableBookRow: View {
    let book: Book
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .orange : .secondary)
                .padding(.leading, 16)

            BookRowView(book: book)
                .padding(.leading, -16)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
