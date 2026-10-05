import SwiftUI

struct SampleListView: View {
    let samples: [Sample]

    var body: some View {
        NavigationStack {
            List(samples) { sample in
                NavigationLink(sample.title, value: sample)
            }
            .navigationTitle("QuickJS sandbox")
            .navigationDestination(for: Sample.self) { SampleView(sample: $0) }
        }
    }
}

struct SampleView: View {
    let sample: Sample
    @State private var outcome: ScriptOutcome?
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CodeBlock(title: "Script", text: sample.source)
                Button(isRunning ? "Running…" : "Run") { Task { await run() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                if let outcome {
                    if let value = outcome.value {
                        CodeBlock(title: "Result", text: value, tint: .green)
                    }
                    if let error = outcome.error {
                        CodeBlock(title: "Error", text: error, tint: .red)
                    }
                    if !outcome.console.isEmpty {
                        CodeBlock(title: "Console", text: outcome.console.joined(separator: "\n"))
                    }
                    Text(verbatim: "\(outcome.durationMs) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(sample.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        outcome = nil
        isRunning = true
        outcome = await runScript(source: sample.source)
        isRunning = false
    }
}

struct CodeBlock: View {
    let title: String
    let text: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
