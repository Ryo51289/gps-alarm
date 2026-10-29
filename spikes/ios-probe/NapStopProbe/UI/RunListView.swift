import SwiftUI

/// List of runs (newest first) + the log of events outside runs (S3-0 quick tests, proc_start).
@MainActor
struct RunListView: View {
    @State private var runs: [String] = []
    @State private var share: ShareItem?

    var body: some View {
        List {
            Section("Lượt") {
                if runs.isEmpty {
                    Text("Chưa có lượt nào.").foregroundStyle(.secondary)
                }
                ForEach(runs, id: \.self) { run in
                    NavigationLink(run) { SummaryView(runId: run) }
                        .font(.footnote.monospaced())
                        .frame(minHeight: 44)
                }
            }
            Section("Ngoài lượt") {
                Button {
                    share = ShareItem(items: [EventLog.shared.fileURL(run: "")])
                } label: {
                    Text("Chia sẻ log ngoài lượt (orphan.jsonl)").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        .navigationTitle("Kết quả")
        .onAppear { runs = EventLog.shared.listRuns() }
        .sheet(item: $share) { item in
            ShareSheet(items: item.items)
        }
    }
}
