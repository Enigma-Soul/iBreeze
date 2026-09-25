import SwiftUI

/// 阅读设置：目前只有方向，后续的缩放/亮度等也放这里
struct ReaderSettingsSheet: View {
    @AppStorage(SettingsKey.readingDirection) private var direction = ReadingDirection.vertical.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("阅读方向", selection: $direction) {
                        ForEach(ReadingDirection.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("翻页")
                } footer: {
                    Text("纵向连续适合长条漫画；左右翻页适合单页作品，右到左是日漫的常见顺序。")
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
