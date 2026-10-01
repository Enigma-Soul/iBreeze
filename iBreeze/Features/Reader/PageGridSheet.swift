import SwiftUI

/// 页码网格：两百页的本子靠滑杆很难定位，这里一格一页直接点
struct PageGridSheet: View {
    let pages: [ChapterPage]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 54), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                            cell(index: index)
                        }
                    }
                    .padding(AppTheme.Spacing.page)
                }
                // 打开就停在当前页，而不是从第一页开始找
                .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func cell(index: Int) -> some View {
        let isCurrent = index == currentIndex

        return Button {
            onSelect(index)
            dismiss()
        } label: {
            Text("\(index + 1)")
                .font(.subheadline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isCurrent ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(index)
    }
}
