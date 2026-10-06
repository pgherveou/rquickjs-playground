import SwiftUI
import Synchronization

/// The script for one parallel sandbox, with its number written into the source.
enum WorkerScript {
    static func source(worker: Int) -> String {
        """
        console.log("worker \(worker) start");
        await new Promise((resolve) => setTimeout(resolve, 200));
        console.log("worker \(worker) done");
        """
    }
}

struct LogEntry {
    let line: String
    let arrival: Duration
}

/// Records console lines from any thread with their arrival time, without touching the main thread,
/// which builds the web views being measured.
final class ConsoleRecorder: ConsoleListener {
    private let started = ContinuousClock.now
    private let entries = Mutex<[LogEntry]>([])

    func onLine(line: String) {
        entries.withLock { $0.append(LogEntry(line: line, arrival: started.duration(to: .now))) }
    }

    var log: [LogEntry] { entries.withLock { $0 } }
    var elapsed: Duration { started.duration(to: .now) }
}

/// What one engine did with a batch of workers started at once.
struct BatchResult {
    let workers: Int
    let log: [LogEntry]
    let failures: [String: Int]
    let total: Duration
    let appMemoryGrowth: UInt64
    /// WebContent processes of the batch's web views; nil where iOS hides them.
    var webKitMemory: UInt64? = 0

    var lastStart: Duration? { log.last { $0.line.hasSuffix(" start") }?.arrival }

    static func run(workers: Int, console: ConsoleRecorder, worker run: @escaping @Sendable (String) async -> String?) async -> BatchResult {
        var failures: [String: Int] = [:]
        let appMemoryGrowth = await AppMemory.peakGrowth {
            await withTaskGroup(of: (Int, String?).self) { group in
                for worker in 1...workers {
                    group.addTask { (worker, await run(WorkerScript.source(worker: worker))) }
                }
                for await case (let worker, let error?) in group {
                    console.onLine(line: "worker \(worker) failed: \(error)")
                    failures[error, default: 0] += 1
                }
            }
        }
        return BatchResult(workers: workers, log: console.log, failures: failures, total: console.elapsed, appMemoryGrowth: appMemoryGrowth)
    }
}

struct ParallelView: View {
    private static let counts = 1...5000

    @State private var count = 10
    @State private var quickJS: BatchResult?
    @State private var webView: BatchResult?
    @State private var isRunning = false
    @State private var liveWebViews: HiddenWebViews?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Sandboxes")
                    TextField("Sandboxes", value: $count, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Spacer()
                    Stepper("Sandboxes", value: $count, in: Self.counts)
                        .labelsHidden()
                }
                .disabled(isRunning)
                CodeBlock(title: "Script for sandbox 1", text: WorkerScript.source(worker: 1))
                Button(isRunning ? "Running…" : "Run") { Task { await run() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || !Self.counts.contains(count))
                if let quickJS, let webView {
                    ResultsTable(quickJS: quickJS, webView: webView)
                    CodeBlock(title: "QuickJS console", text: quickJS.console)
                    CodeBlock(title: "WebView console", text: webView.console)
                }
            }
            .padding()
        }
        .navigationTitle("Parallel sandboxes")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { liveWebViews?.close() }
    }

    private func run() async {
        liveWebViews?.close()
        quickJS = nil
        webView = nil
        isRunning = true
        let workers = count

        let quickJSConsole = ConsoleRecorder()
        let quickJSResult = await BatchResult.run(workers: workers, console: quickJSConsole) {
            await runScript(source: $0, listener: quickJSConsole).error
        }

        let webViewConsole = ConsoleRecorder()
        let webViews = HiddenWebViews(console: webViewConsole)
        var webViewResult = await BatchResult.run(workers: workers, console: webViewConsole) { await webViews.run($0) }
        webViewResult.webKitMemory = webViews.webContentFootprint()

        // Shown only now, so drawing the QuickJS results does not count toward the web view batch's memory.
        quickJS = quickJSResult
        webView = webViewResult
        liveWebViews = webViews
        isRunning = false
    }
}

private extension BatchResult {
    var console: String {
        log.map { "[\($0.arrival.inMilliseconds)] \($0.line)" }.joined(separator: "\n")
    }
}

private extension Duration {
    var inMilliseconds: String { "\(Int((self / .milliseconds(1)).rounded())) ms" }
}

private func megabytes(_ bytes: UInt64) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576)
}

struct ResultsTable: View {
    let quickJS: BatchResult
    let webView: BatchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("QuickJS").bold()
                    Text("WebView").bold()
                }
                row("Total time") { $0.total.inMilliseconds }
                row("Last start") { $0.lastStart?.inMilliseconds ?? "-" }
                row("Failed") { "\($0.failures.values.reduce(0, +))" }
                row("App memory") { "+" + megabytes($0.appMemoryGrowth) }
                row("WebKit memory") { $0.webKitMemory.map(megabytes) ?? "n/a" }
                row("Per sandbox") { result in
                    result.webKitMemory.map { megabytes((result.appMemoryGrowth + $0) / UInt64(result.workers)) } ?? "n/a"
                }
            }
            ForEach([("QuickJS", quickJS), ("WebView", webView)], id: \.0) { engine, result in
                ForEach(result.failures.sorted { $0.value > $1.value }, id: \.key) { reason, count in
                    Text(verbatim: "\(engine): \(count) × \(reason)").font(.caption).foregroundStyle(.red)
                }
            }
            Text("App memory: peak growth of this app's process. WebKit memory: the WebContent processes of the live web views, read when the batch ends. The simulator allows reading them; a device does not (n/a). Web views stay alive until the next Run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, value: (BatchResult) -> String) -> some View {
        GridRow {
            Text(label)
            Text(value(quickJS))
            Text(value(webView))
        }
        .monospacedDigit()
    }
}
