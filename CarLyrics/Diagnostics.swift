import Foundation
import OSLog

/// A small rolling log in Documents/diagnostics.log, for figuring out what the app was
/// doing in the background (pull it off the phone with `xcrun devicectl device copy from`).
enum Diagnostics {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "carlyrics", category: "diag")
    private static let queue = DispatchQueue(label: "diagnostics")
    private static let url = URL.documentsDirectory.appending(path: "diagnostics.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 300_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
