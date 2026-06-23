import Foundation

enum APNSEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    static var current: APNSEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}
