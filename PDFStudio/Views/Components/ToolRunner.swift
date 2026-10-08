import Observation
import SwiftUI

/// Runs a tool's work off the main thread, saves the outputs to My Files and drives the result UI.
@MainActor
@Observable
final class ToolRunner {
    var isRunning = false
    var progressText: String?
    var errorMessage: String?
    var results: [URL] = []
    var notes: [URL: String] = [:]
    var showResults = false

    func run(store: FileStore, _ work: @escaping ToolWork) {
        guard !isRunning else { return }
        isRunning = true
        progressText = nil
        Task {
            do {
                let outputs = try await Task.detached(priority: .userInitiated) { try await work() }.value
                var urls: [URL] = []
                var notes: [URL: String] = [:]
                for output in outputs {
                    let url = try store.save(output.data, baseName: output.name, ext: output.ext)
                    urls.append(url)
                    if let note = output.note { notes[url] = note }
                }
                self.results = urls
                self.notes = notes
                self.showResults = !urls.isEmpty
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
        }
    }

    func fail(_ error: Error) { errorMessage = error.localizedDescription }

    /// A thread-safe progress callback for long running work.
    var progressReporter: @Sendable (Int, Int) -> Void {
        { [weak self] current, total in
            Task { @MainActor in self?.progressText = "Page \(current) of \(total)" }
        }
    }
}

struct ToolRunnerModifier: ViewModifier {
    @Bindable var runner: ToolRunner

    func body(content: Content) -> some View {
        content
            .disabled(runner.isRunning)
            .overlay {
                if runner.isRunning {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large)
                            Text("Working…").font(.headline)
                            if let text = runner.progressText {
                                Text(text).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .padding(28)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .sheet(isPresented: $runner.showResults, onDismiss: { AdsManager.shared.taskCompleted() }) {
                ResultView(urls: runner.results, notes: runner.notes)
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { runner.errorMessage != nil },
                                        set: { if !$0 { runner.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(runner.errorMessage ?? "")
            }
    }
}

extension View {
    func toolRunner(_ runner: ToolRunner) -> some View { modifier(ToolRunnerModifier(runner: runner)) }
}
