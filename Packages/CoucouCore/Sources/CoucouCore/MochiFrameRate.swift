import SwiftUI

private struct MochiFrameIntervalKey: EnvironmentKey {
  static let defaultValue: Double? = nil
}

extension EnvironmentValues {
  /// The longest a Mochi canvas waits between frames; nil draws at the display's rate.
  /// Mochi's speed does not depend on the frame rate (`MochiFrameClock`), so the
  /// small Mochis in the closed notch's ears can draw far less often.
  var mochiFrameInterval: Double? {
    get { self[MochiFrameIntervalKey.self] }
    set { self[MochiFrameIntervalKey.self] = newValue }
  }
}
