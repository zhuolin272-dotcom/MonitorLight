import Foundation

/// User-observed channel direction for one display/mode, not colorimetric calibration.
public enum ColorResponseProfile: String, Codable, Sendable {
    case blueOnlyNormal

    public static func load(displayID: String, defaults: UserDefaults = .standard) -> ColorResponseProfile? {
        defaults.string(forKey: "colorResponse.\(displayID)").flatMap(Self.init(rawValue:))
    }
}
