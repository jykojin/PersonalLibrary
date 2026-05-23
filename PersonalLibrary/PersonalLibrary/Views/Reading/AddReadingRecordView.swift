import SwiftUI
import SwiftData

struct AddReadingRecordView: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var startPage: String = ""
    @State private var endPage: String = ""
    @State private var durationMinutes: String = ""
    @State private var note: String = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("阅读页码") {
                    TextField("起始页", text: $startPage)
                        .keyboardType(.numberPad)
                    TextField("结束页", text: $endPage)
                        .keyboardType(.numberPad)
                }

                Section("阅读时间") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("阅读时长（分钟）", text: $durationMinutes)
                        .keyboardType(.numberPad)
                }

                Section("笔记（可选）") {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("记录阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveRecord() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                startPage = "\(book.currentPage)"
            }
        }
    }

    private var isValid: Bool {
        guard let start = Int(startPage),
              let end = Int(endPage),
              end > start,
              end <= book.totalPages else {
            return false
        }
        return true
    }

    private func saveRecord() {
        guard let start = Int(startPage),
              let end = Int(endPage) else { return }

        let record = ReadingRecord(
            book: book,
            date: date,
            startPage: start,
            endPage: end,
            durationMinutes: Int(durationMinutes) ?? 0,
            note: note.isEmpty ? nil : note
        )
        modelContext.insert(record)

        // 更新书籍当前页码
        book.currentPage = end

        // 如果读完了，自动标记为已读
        if end >= book.totalPages {
            book.status = .finished
            book.statusChangedDate = Date()
            book.finishedDate = Date()
        } else if book.status == .idle || book.status == .wishlist {
            book.status = .reading
            book.statusChangedDate = Date()
        }

        dismiss()
    }
}
