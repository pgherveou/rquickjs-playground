import SwiftUI

/// The script for one parallel sandbox, with its number written into the source.
enum WorkerScript {
    static func source(worker: Int) -> String {
        """
        await new Promise((resolve) => setTimeout(resolve, 200));
        console.log("worker \(worker) done");
        """
    }
}

struct WorkerResult: Identifiable {
    let worker: Int
    let outcome: ScriptOutcome
    var id: Int { worker }

    var line: String {
        let duration = String(outcome.durationMs)
        let padding = String(repeating: " ", count: max(0, 4 - duration.count))
        return "\(padding)\(duration) ms  " + (outcome.error ?? outcome.console.joined(separator: " "))
    }
}

struct ParallelView: View {
    @State private var count = 10
    @State private var results: [WorkerResult] = []
    @State private var total: Duration?
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
                if let total {
                    Text(verbatim: "\(results.count) sandboxes finished in \(total.formatted(.units(allowed: [.milliseconds])))")
                        .font(.headline)
                }
                if !results.isEmpty {
                    CodeBlock(title: "Finished, in order", text: results.map(\.line).joined(separator: "\n"))
                }
            }
            .padding()
        }
        .navigationTitle("Parallel sandboxes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        results = []
        total = nil
        isRunning = true
        let started = ContinuousClock.now
        await withTaskGroup(of: WorkerResult.self) { group in
            for worker in 1...count {
                group.addTask { WorkerResult(worker: worker, outcome: await runScript(source: WorkerScript.source(worker: worker))) }
            }
            for await result in group {
                results.append(result)
            }
        }
        total = started.duration(to: .now)
        isRunning = false
    }
}
