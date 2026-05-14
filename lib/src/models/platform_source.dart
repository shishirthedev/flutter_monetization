/// Indicates which platform fulfilled the purchase.
enum PlatformSource {
  googlePlay,
  appStore,
  unknown,
}

extension PlatformSourceX on PlatformSource {
  String get displayName {
    switch (this) {
      case PlatformSource.googlePlay:
        return 'Google Play';
      case PlatformSource.appStore:
        return 'App Store';
      case PlatformSource.unknown:
        return 'Unknown';
    }
  }
}
