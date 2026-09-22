import Foundation

enum DeviceModel {
    /// The hardware identifier, e.g. `iPhone14,3`. The simulator reports the host
    /// architecture from `uname`, so it answers with the model it is simulating.
    static var identifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
