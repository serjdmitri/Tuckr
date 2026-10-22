import Foundation

/// The host-facing door into Coucou. Everything else in this module is
/// Coucou's own code, copied unchanged from the upstream commit recorded in
/// UPSTREAM.md; this file is the only addition.
public enum CoucouHost {
  /// True once the module is linked into the app. Step 4a only proves the
  /// package builds and loads; nothing of Coucou runs yet.
  public static let isLinked = true
}
