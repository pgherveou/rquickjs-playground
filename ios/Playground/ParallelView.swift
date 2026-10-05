import SwiftUI

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

/// Appends each console line on the main thread, in the order the sandboxes log them.
final class MainThreadConsole: ConsoleListener {
    private let append: @MainActor @Sendable (String) -> Void

    init(append: @escaping @MainActor @Sendable (String) -> Void) {
        self.append = append
    }

    func onLine(line: String) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.append(line) } }
    }
}

struct ParallelView: View {
    @State private var count = 10
    @State private var log: [String] = []
    @State private var summary: String?
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Stepper("Sandboxes: \(count)", value: $count, in: 1...100)
                    .disabled(isRunning)
                CodeBlock(title: "Script for sandbox 1", text: WorkerScript.source(worker: 1))
                Button(isRunning ? "Running…" : "Run") { Task { await run() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                if let summary {
                    Text(verbatim: summary).font(.headline)
                }
                if !log.isEmpty {
                    CodeBlock(title: "Console, in arrival order", text: log.joined(separator: "\n"))
                }
            }
            .padding()
        }
        .navigationTitle("Parallel sandboxes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        log = []
        summary = nil
        isRunning = true
        let sandboxes = count
        let console = MainThreadConsole { log.append($0) }
        let started = ContinuousClock.now
        await withTaskGroup(of: (Int, String?).self) { group in
            for worker in 1...sandboxes {
                group.addTask { (worker, await runScript(source: WorkerScript.source(worker: worker), listener: console).error) }
            }
            for await case (let worker, let error?) in group {
                log.append("worker \(worker) failed: \(error)")
            }
        }
        let elapsed = started.duration(to: .now).formatted(.units(allowed: [.milliseconds]))
        summary = "\(sandboxes) sandboxes finished in \(elapsed)"
        isRunning = false
    }
}
