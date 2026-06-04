import Foundation

enum TransferStatsParser {
    static func progress(in text: String) -> TransferProgress? {
        guard let transfer = transferLine(in: text) else { return nil }
        let files = filesLine(in: text)

        return TransferProgress(
            transferredBytes: transfer.transferredBytes,
            totalBytes: transfer.totalBytes,
            percent: transfer.percent,
            speedBytesPerSecond: transfer.speedBytesPerSecond,
            eta: transfer.eta,
            filesDone: files?.done,
            filesTotal: files?.total,
            filesPercent: files?.percent,
            activeFiles: activeFiles(in: text)
        )
    }

    static func transferredBytes(in text: String) -> Int64? {
        progress(in: text)?.transferredBytes ?? transferLine(in: text)?.transferredBytes
    }

    static func formatSpeed(_ bytesPerSecond: Int64?) -> String {
        guard let bytesPerSecond else { return "Waiting" }
        return "\(formatBytes(bytesPerSecond))/s"
    }

    static func formatPercent(_ percent: Int?) -> String {
        guard let percent else { return "-" }
        return "\(percent)%"
    }

    static func containsQuotaSignal(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("max transfer")
            || lowercased.contains("transfer limit")
            || lowercased.contains("quota")
            || lowercased.contains("daily limit")
            || lowercased.contains("user rate limit exceeded")
            || lowercased.contains("rate limit exceeded")
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
    }

    private static func transferLine(in text: String) -> (transferredBytes: Int64, totalBytes: Int64?, percent: Int?, speedBytesPerSecond: Int64?, eta: String?)? {
        let pattern = #"Transferred:\s+([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B|[KMGTPE]?B|[KMGTPE])(?:\s*/\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B|[KMGTPE]?B|[KMGTPE]))?(?:,\s*([0-9]+)%)?(?:,\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B|[KMGTPE]?B|[KMGTPE])/?s)?(?:,\s*ETA\s*([^\n\r]+))?"#
        guard let match = lastMatch(pattern: pattern, in: text), match.numberOfRanges >= 3 else { return nil }
        guard let value = double(at: 1, match: match, in: text),
              let unit = string(at: 2, match: match, in: text)
        else { return nil }

        let transferredBytes = Int64(value * multiplier(for: unit))
        let totalBytes: Int64?
        if let totalValue = double(at: 3, match: match, in: text),
           let totalUnit = string(at: 4, match: match, in: text) {
            totalBytes = Int64(totalValue * multiplier(for: totalUnit))
        } else {
            totalBytes = nil
        }

        let speedBytesPerSecond: Int64?
        if let speedValue = double(at: 6, match: match, in: text),
           let speedUnit = string(at: 7, match: match, in: text) {
            speedBytesPerSecond = Int64(speedValue * multiplier(for: speedUnit))
        } else {
            speedBytesPerSecond = nil
        }

        return (
            transferredBytes,
            totalBytes,
            int(at: 5, match: match, in: text),
            speedBytesPerSecond,
            string(at: 8, match: match, in: text)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func filesLine(in text: String) -> (done: Int, total: Int, percent: Int?)? {
        let pattern = #"Transferred:\s+([0-9]+)\s*/\s*([0-9]+),\s*([0-9]+)%"#
        guard let match = lastMatch(pattern: pattern, in: text),
              let done = int(at: 1, match: match, in: text),
              let total = int(at: 2, match: match, in: text)
        else {
            return nil
        }

        return (done, total, int(at: 3, match: match, in: text))
    }

    private static func activeFiles(in text: String) -> [ActiveFileTransfer] {
        let pattern = #"(?m)^\s*\*?\s*(.+?):\s+([0-9]+)%\s*/\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B|[KMGTPE]?B|[KMGTPE]),\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B|[KMGTPE]?B|[KMGTPE])(?:/s|/)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))

        return matches.suffix(6).compactMap { match -> ActiveFileTransfer? in
            guard let name = string(at: 1, match: match, in: text)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            let sizeBytes: Int64?
            if let sizeValue = double(at: 3, match: match, in: text),
               let sizeUnit = string(at: 4, match: match, in: text) {
                sizeBytes = Int64(sizeValue * multiplier(for: sizeUnit))
            } else {
                sizeBytes = nil
            }

            let speedBytes: Int64?
            if let speedValue = double(at: 5, match: match, in: text),
               let speedUnit = string(at: 6, match: match, in: text) {
                speedBytes = Int64(speedValue * multiplier(for: speedUnit))
            } else {
                speedBytes = nil
            }

            return ActiveFileTransfer(
                name: name,
                percent: int(at: 2, match: match, in: text),
                sizeBytes: sizeBytes,
                speedBytesPerSecond: speedBytes
            )
        }
    }

    private static func lastMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).last
    }

    private static func string(at index: Int, match: NSTextCheckingResult, in text: String) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private static func double(at index: Int, match: NSTextCheckingResult, in text: String) -> Double? {
        string(at: index, match: match, in: text).flatMap(Double.init)
    }

    private static func int(at index: Int, match: NSTextCheckingResult, in text: String) -> Int? {
        string(at: index, match: match, in: text).flatMap(Int.init)
    }

    private static func multiplier(for unit: String) -> Double {
        switch unit.lowercased() {
        case "b": 1
        case "k", "kb": 1_000
        case "m", "mb": 1_000_000
        case "g", "gb": 1_000_000_000
        case "t", "tb": 1_000_000_000_000
        case "p", "pb": 1_000_000_000_000_000
        case "e", "eb": 1_000_000_000_000_000_000
        case "kib": 1_024
        case "mib": 1_048_576
        case "gib": 1_073_741_824
        case "tib": 1_099_511_627_776
        case "pib": 1_125_899_906_842_624
        case "eib": 1_152_921_504_606_846_976
        default: 1
        }
    }
}
