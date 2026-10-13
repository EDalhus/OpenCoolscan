import SwiftUI
import AppKit

// MARK: - Progress window (batch status, queue and log)

struct ProgressWindow: View {
    @EnvironmentObject var scanner: ScannerManager
    @EnvironmentObject var settings: ScanSettings
    @AppStorage("autoSaveAfterScan") private var autoSaveAfterScan = false
    var onClose: () -> Void

    @State private var tab = Tab.queue

    enum Tab { case queue, log }

    var body: some View {
        AquaWindow {
            VStack(spacing: 0) {
                AquaTitleBar(title: "Progress", height: 16, fontSize: 12, showsAllLights: false, onClose: onClose)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(headline)
                            .font(.lucida(12.5))
                            .foregroundColor(.aquaText)
                            .lineLimit(1)
                        Spacer()
                        Text(timeLeft)
                            .font(.lucida(12))
                            .foregroundColor(Color(hex: 0x6A6A6A))
                    }
                    .frame(height: 18)
                    .padding(.top, 8)

                    HStack(spacing: 9) {
                        AquaProgressBar(value: scanner.isBusy ? max(0.03, scanner.scanProgress) : 0,
                                        animating: scanner.isBusy)
                            .frame(height: 13)
                        AquaPushButton(title: "Stop", disabled: !scanner.isBusy) {
                            scanner.cancelCurrentOperation()
                        }
                        .frame(width: 48, height: 18)
                    }
                    .padding(.top, 8)

                    Text(destinationLine)
                        .font(.lucida(11))
                        .foregroundColor(Color(hex: 0x3A3A3A))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 9)

                    HStack(spacing: -1) {
                        AquaTab(title: "Queue", selected: tab == .queue) { tab = .queue }
                        AquaTab(title: "Log", selected: tab == .log) { tab = .log }
                    }
                    .frame(height: 18)
                    .padding(.top, 8)
                    .padding(.leading, -2)
                    .zIndex(1)

                    HStack(alignment: .top, spacing: 8) {
                        Group {
                            if tab == .queue { queueList } else { logList }
                        }
                        .background { Color.white }
                        .overlay(Rectangle().stroke(Color(hex: 0x8A8A8A), lineWidth: 1))

                        if tab == .queue {
                            Button { scanner.scanQueue = [] } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [Color(hex: 0xFBFBFB), Color(hex: 0xDCDCDC)],
                                                             startPoint: .top, endPoint: .bottom))
                                    RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x7A7A7A), lineWidth: 1)
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: 0x222222))
                                }
                                .frame(width: 24.5, height: 24.5)
                            }
                            .buttonStyle(.plain)
                            .disabled(scanner.isBusy || scanner.scanQueue.isEmpty)
                            .help("Clear finished queue")
                        }
                    }
                    .padding(6)
                    .background { Color(hex: 0xE2E2E2) }
                    .overlay(Rectangle().stroke(Color(hex: 0x9A9A9A), lineWidth: 1))
                    .padding(.top, -1)
                    .padding(.bottom, 10)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: Text

    private var headline: String {
        if scanner.isScanning, let cur = scanner.currentScanFrame {
            let total = scanner.scanQueue.count
            let pos = (scanner.scanQueue.firstIndex(of: cur) ?? 0) + 1
            return total > 1 ? "Batch scan · frame \(pos) of \(total)" : "Scanning frame \(cur + 1)"
        }
        if scanner.isPreviewScanning { return "Preview · frame \(scanner.selectedFrame + 1)" }
        if scanner.isAutoPreviewingAll, let cur = scanner.currentScanFrame {
            return "Thumbnails · frame \(cur + 1)"
        }
        return scanner.statusMessage
    }

    private var timeLeft: String {
        guard scanner.isBusy, let start = scanner.operationStartedAt else { return "" }
        let p = scanner.scanProgress
        guard p > 0.02 else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, elapsed * (1 - p) / p)
        return "\(Int(remaining.rounded())) s left"
    }

    private var formatLabel: String {
        "\(settings.outputFormat.rawValue) \(settings.bitDepth == .bit8 ? "8" : "16")-bit"
    }

    private var destinationLine: String {
        let mode = settings.colorSpace == .gray ? "Grayscale" : "Calibrated RGB"
        let dest: String
        if autoSaveAfterScan {
            let dir = ScanimageLocator.scratchDirectory.appendingPathComponent("AutoSave").path
            dest = (dir as NSString).abbreviatingWithTildeInPath + "/Scan_###"
        } else {
            dest = "manual save"
        }
        return "\(formatLabel) · \(mode) → \(dest)"
    }

    // MARK: Lists

    private var queueFrames: [Int] {
        scanner.scanQueue.isEmpty ? scanner.selectedFrames.sorted() : scanner.scanQueue
    }

    private var highlightedFrame: Int { scanner.currentScanFrame ?? scanner.selectedFrame }

    private var queueList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(queueFrames.enumerated()), id: \.element) { idx, frame in
                        queueRow(frame: frame, index: idx).id(frame)
                    }
                }
            }
            .onChange(of: scanner.currentScanFrame) { f in
                if let f { withAnimation { proxy.scrollTo(f, anchor: .center) } }
            }
        }
    }

    private func queueRow(frame: Int, index: Int) -> some View {
        let selected = frame == highlightedFrame
        return HStack(spacing: 8) {
            Group {
                if let img = scanner.framePreviews[frame] {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Color(hex: 0x3A4664)
                }
            }
            .frame(width: 26, height: 16)
            .clipped()
            .overlay(Rectangle().stroke(Color(hex: 0x1A1A1A), lineWidth: 1))

            Text("Frame \(frame + 1) · \(formatLabel)")
                .lineLimit(1)
            Spacer()
            Text(statusText(for: frame))
        }
        .font(.lucida(12))
        .foregroundColor(selected ? .white : .aquaText)
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background { selected ? Color.aquaSelection : (index.isMultiple(of: 2) ? Color.white : Color.aquaRowAlt) }
        .contentShape(Rectangle())
        .onTapGesture { if !scanner.isBusy { scanner.selectFrame(frame) } }
    }

    private func statusText(for frame: Int) -> String {
        switch scanner.jobState(for: frame) {
        case .done:            return "Done"
        case .active(let p):   return "\(Int((p * 100).rounded()))%"
        case .waiting:         return "Waiting"
        case .idle:            return "Ready"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(scanner.log) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.timeFormatter.string(from: entry.date))
                                .foregroundColor(Color(hex: 0x777777))
                            Text(entry.message)
                                .foregroundColor(.aquaText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.lucida(10.5))
                        .id(entry.id)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: scanner.log.count) { _ in
                if let last = scanner.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
