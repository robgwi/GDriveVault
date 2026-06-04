import Foundation

@MainActor
final class RcloneConfigSession: ObservableObject {
    @Published var output = ""
    @Published var input = ""
    @Published var isRunning = false
    @Published var exitCode: Int32?

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var onFinish: (() -> Void)?

    func start(onFinish: @escaping () -> Void) {
        stop()
        self.onFinish = onFinish
        output = ""
        input = ""
        exitCode = nil
        isRunning = true

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = rcloneURL()
        process.arguments = ["config"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.append(chunk)
            }
        }

        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                self?.finish(status)
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
        } catch {
            output = "Could not launch rclone. Install it with Homebrew or set it at /opt/homebrew/bin/rclone.\n"
            isRunning = false
        }
    }

    func sendInput() {
        guard isRunning, let data = "\(input)\n".data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
        append("> \(input)\n")
        input = ""
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
        isRunning = false
    }

    private func append(_ chunk: String) {
        output.append(chunk)
        if output.count > 60_000 {
            output.removeFirst(output.count - 60_000)
        }
    }

    private func finish(_ status: Int32) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        exitCode = status
        isRunning = false
        process = nil
        inputPipe = nil
        outputPipe = nil
        append("\n[rclone config exited \(status)]\n")
        onFinish?()
    }

    private func rcloneURL() -> URL {
        let candidates = [
            "/opt/homebrew/bin/rclone",
            "/usr/local/bin/rclone",
            "/usr/bin/rclone"
        ]

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: "/opt/homebrew/bin/rclone")
    }
}
