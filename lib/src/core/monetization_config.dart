import '../delegates/analytics_delegate.dart';
import '../delegates/sync_delegate.dart';
import '../utils/monetization_logger.dart';

/// Product IDs for the Android (Google Play) store.
class AndroidProducts {
  const AndroidProducts({
    required this.monthly,
    required this.yearly,
    required this.lifetime,
  });

  /// Google Play product ID for the monthly subscription.
  final String monthly;

  /// Google Play product ID for the yearly subscription.
  final String yearly;

  /// Google Play product ID for the lifetime non-consumable.
  final String lifetime;
}

/// Product IDs for the iOS (App Store) store.
class IOSProducts {
  const IOSProducts({
    required this.monthly,
    required this.yearly,
    required this.lifetime,
  });

  /// App Store product ID for the monthly subscription.
  final String monthly;

  /// App Store product ID for the yearly subscription.
  final String yearly;

  /// App Store product ID for the lifetime non-consumable.
  final String lifetime;
}

/// Top-level configuration object passed to [Monetization.init].
///
/// ## Example
/// ```dart
/// final config = MonetizationConfig(
///   android: AndroidProducts(
///     monthly: 'com.myapp.premium_monthly',
///     yearly:  'com.myapp.premium_yearly',
///     lifetime:'com.myapp.premium_lifetime',
///   ),
///   ios: IOSProducts(
///     monthly: 'com.myapp.premium_monthly',
///     yearly:  'com.myapp.premium_yearly',
///     lifetime:'com.myapp.premium_lifetime',
///   ),
/// );
/// ```
class MonetizationConfig {
  const MonetizationConfig({
    required this.android,
    required this.ios,
    this.syncDelegate,
    this.analyticsDelegate,
    this.logLevel = MonetizationLogLevel.info,
    this.entitlementCacheTtl = const Duration(hours: 24),
    this.autoRestoreOnInit = true,
    this.gracePeriodDuration = const Duration(days: 16),
  });

  /// Android-specific product IDs.
  final AndroidProducts android;

  /// iOS-specific product IDs.
  final IOSProducts ios;

  /// Optional delegate for syncing entitlement to a remote backend
  /// (e.g. Firestore). If null, remote sync is disabled.
  final MonetizationSyncDelegate? syncDelegate;

  /// Optional delegate for emitting analytics events.
  final MonetizationAnalyticsDelegate? analyticsDelegate;

  /// Controls verbosity of the internal logger.
  final MonetizationLogLevel logLevel;

  /// How long a cached entitlement is considered fresh before the package
  /// forces a re-verify from the store. Defaults to 24 hours.
  final Duration entitlementCacheTtl;

  /// Whether to automatically call restorePurchases() during [Monetization.init].
  /// Set to false if you want to control the restore trigger yourself.
  final bool autoRestoreOnInit;

  /// Duration used to detect grace period state. When the expiry date is
  /// within this window and payment failed signals are received, the engine
  /// will set status to [EntitlementStatus.gracePeriod].
  final Duration gracePeriodDuration;

  /// Returns the product ID for [plan] on Android.
  String androidProductId(String plan) {
    switch (plan) {
      case 'monthly':
        return android.monthly;
      case 'yearly':
        return android.yearly;
      case 'lifetime':
        return android.lifetime;
      default:
        throw ArgumentError('Unknown plan: $plan');
    }
  }

  /// Returns the product ID for [plan] on iOS.
  String iosProductId(String plan) {
    switch (plan) {
      case 'monthly':
        return ios.monthly;
      case 'yearly':
        return ios.yearly;
      case 'lifetime':
        return ios.lifetime;
      default:
        throw ArgumentError('Unknown plan: $plan');
    }
  }

  /// All unique product IDs across both platforms (deduplicated).
  Set<String> get allProductIds => {
        android.monthly,
        android.yearly,
        android.lifetime,
        ios.monthly,
        ios.yearly,
        ios.lifetime,
      };
}
