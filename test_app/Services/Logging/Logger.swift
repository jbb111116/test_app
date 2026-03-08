import Foundation

protocol Logger {
    func log(_ message: String)
    func error(_ message: String)
}

final class ConsoleLogger: Logger {
    private let verbose: () -> Bool

    init(verbose: @escaping () -> Bool) {
        self.verbose = verbose
    }

    func log(_ message: String) {
        guard verbose() else { return }
        print("[INFO] \(message)")
    }

    func error(_ message: String) {
        print("[ERROR] \(message)")
    }
}
