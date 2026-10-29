import SwiftUI

/// Summary of one run: RunAnalyzer.render (selectable), share summary / log, delete (S3 §6.5 item 6).
@MainActor
struct SummaryView: View {
    let runId: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = "Đang đọc log…"
    @State private var share: ShareItem?
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section {
                button("Chia sẻ tóm tắt") { share = ShareItem(items: [text]) }
                button("Chia sẻ log") { share = ShareItem(items: [EventLog.shared.fileURL(run: runId)]) }
                button("Làm mới") { Task { await load() } }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Xoá lượt").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        .navigationTitle(runId)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $share) { item in
            ShareSheet(items: item.items)
        }
        .confirmationDialog("Xoá log của lượt này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá lượt", role: .destructive) {
                EventLog.shared.deleteRun(runId)
                dismiss()
            }
        }
    }

    private func load() async {
        let run = runId
        text = await Task.detached(priority: .userInitiated) {
            SummaryView.summaryText(run: run, now: Date())
        }.value
    }

    /// Off the main thread: a 10-hour log has tens of thousands of lines.
    nonisolated static func summaryText(run: String, now: Date) -> String {
        let parsed = EventLog.shared.readRun(run)
        if parsed.events.isEmpty { return "Không đọc được log của lượt \(run)." }
        let summary = RunAnalyzer.render(RunAnalyzer.analyze(parsed.events, now: now))
        // The "Gợi ý: …" line stays last.
        return parsed.corrupt > 0 ? "(\(parsed.corrupt) dòng log hỏng đã bỏ qua)\n" + summary : summary
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}
