import SwiftUI
import UIKit

/// Single main screen (S3 §6.5): device, permissions, quick test (S3-0), experiment, active run, results.
@MainActor
struct MainView: View {
    @ObservedObject private var controller = RunController.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var presetId = "S3-1"
    @State private var channel: ProbeChannel = .AK
    @State private var delayMin = 2
    @State private var longHours = 10
    @State private var denseMin = 20
    @State private var prearm = true
    @State private var confirmStop = false

    private var preset: ScenarioPreset { ScenarioPreset.find(presetId) }

    var body: some View {
        NavigationStack {
            Form {
                deviceSection
                permissionSection
                quickTestSection
                if let cfg = controller.config {
                    runningSection(cfg)
                } else {
                    experimentSection
                }
                Section {
                    NavigationLink("Xem kết quả") { RunListView() }
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle("NapStop Probe")
            .alert("NapStop Probe", isPresented: messageShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.message ?? "")
            }
            .confirmationDialog("Dừng lượt này?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Dừng lượt", role: .destructive) { controller.userStop() }
            }
            .task { await controller.refreshDevice() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { controller.refreshDeviceSoon() }
            }
            .onChange(of: presetId) { _, id in
                channel = ScenarioPreset.find(id).channel
                delayMin = 2
            }
        }
    }

    private var messageShown: Binding<Bool> {
        Binding(
            get: { controller.message != nil },
            set: { shown in if !shown { controller.message = nil } }
        )
    }

    // MARK: - 1. Device

    private var deviceSection: some View {
        let d = controller.device
        return Section("Thiết bị") {
            row("Model", d.model)
            row("iOS", d.ios)
            row("Bundle ID", d.bundleId)
            row("Pin", d.batteryText)
            row("Chế độ nguồn điện thấp", d.lowPower ? "Bật" : "Tắt")
            row("Làm mới App ở chế độ nền", d.bgRefresh)
        }
    }

    // MARK: - 2. Permissions

    private var permissionSection: some View {
        let d = controller.device
        return Section("Quyền") {
            row("Vị trí", "\(d.locAuth) · \(d.locAccuracy)")
            actionButton("Cấp Khi dùng app") { controller.requestLocationWhenInUse() }
            actionButton("Nâng lên Luôn cho phép") { controller.requestLocationAlways() }
            row("Thông báo", d.notifAuth)
            row("Time Sensitive", d.timeSensitive)
            row("Âm thông báo · Màn khoá", "\(d.notifSound) · \(d.notifLock)")
            actionButton("Cấp quyền thông báo") { Task { await controller.requestNotifications() } }
            row("AlarmKit", d.alarmKitAuth)
            actionButton("Cấp quyền AlarmKit") { Task { await controller.requestAlarmKit() } }
            actionButton("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - 3. Quick test (S3-0)

    private var quickTestSection: some View {
        Section("Kiểm tra nhanh (S3-0)") {
            actionButton("Thử AlarmKit 10 giây") { Task { await controller.testAlarmKit(defaultSound: false) } }
            actionButton("Thử AlarmKit 10 giây — âm mặc định") { Task { await controller.testAlarmKit(defaultSound: true) } }
            actionButton("Thử thông báo 10 giây") { Task { await controller.testNotification() } }
        }
    }

    // MARK: - 4. Experiment

    private var experimentSection: some View {
        Section {
            Picker("Kịch bản", selection: $presetId) {
                ForEach(ScenarioPreset.all) { p in
                    Text(p.id).tag(p.id)
                }
            }
            Text(preset.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Kênh", selection: $channel) {
                ForEach(ProbeChannel.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            if preset.longRun {
                Stepper("Thời lượng: \(longHours) giờ", value: $longHours, in: 1...12)
                Stepper("Pha dày cuối: \(denseMin) phút", value: $denseMin, in: 5...60, step: 5)
            } else {
                Picker("Trễ tới mốc", selection: $delayMin) {
                    ForEach([1, 2, 5, 30], id: \.self) { m in
                        Text("\(m) phút").tag(m)
                    }
                }
            }
            Toggle("Báo dự phòng", isOn: $prearm)
            actionButton("Bắt đầu") {
                let p = preset
                Task {
                    await controller.start(
                        preset: p, channel: channel, delayMin: delayMin, longHours: longHours, denseMin: denseMin,
                        prearm: prearm
                    )
                }
            }
            actionButton("Bắt đầu đi bộ (S3-13)") { Task { await controller.startWalk() } }
        } header: {
            Text("Thí nghiệm")
        }
    }

    // MARK: - 5. Active run

    private func runningSection(_ cfg: RunConfig) -> some View {
        Section("Lượt đang chạy") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(cfg.runId).font(.footnote.monospaced())
                    Text("Đã chạy: \(DurationText.vi(context.date.timeIntervalSince(cfg.startedAt)))")
                    Text("Mốc: \(IsoTime.clock(cfg.deadline, offsetSeconds: TimeZone.current.secondsFromGMT(for: cfg.deadline)))")
                    Text("Số vị trí: \(controller.fixCount) · Pha: \(controller.phase == .dense ? "dày" : "thưa")")
                    Text("Vị trí cuối cách đây: \(lastFixText(now: context.date))")
                    Text("Vị trí: \(controller.locationRunning ? "đang chạy" : "đã dừng") · Báo: \(controller.fired ? "đã kích hoạt" : "chưa")")
                    if let exitAt = controller.selfExitAt {
                        Text("Tự thoát sau: \(max(0, Int(exitAt.timeIntervalSince(context.date)))) s")
                    }
                }
            }
            actionButton("Dừng lượt", role: .destructive) { confirmStop = true }
            actionButton("Dừng vị trí (giữ lượt)") { controller.suspendLocation() }
            actionButton("Tự thoát sau 30 giây") { controller.scheduleSelfExit() }
        }
    }

    private func lastFixText(now: Date) -> String {
        guard let last = controller.lastFixAt else { return "—" }
        return DurationText.vi(max(0, now.timeIntervalSince(last)))
    }

    // MARK: - Building blocks

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func actionButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}
