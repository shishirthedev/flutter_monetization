/// A production-grade, reusable Flutter package for In-App Purchases and
/// entitlement management. Supports Android (Google Play) and iOS (StoreKit),
/// monthly/yearly subscriptions, lifetime purchases, restore purchases,
/// local caching, optional Firestore sync hooks, and AdMob integration hooks.
///
/// ## Usage
/// ```dart
/// import 'package:flutter_monetization/flutter_monetization.dart';
///
/// await Monetization.init(
///   MonetizationConfig(
///     android: AndroidProducts(
///       monthly:  'com.myapp.sub_monthly',
///       yearly:   'com.myapp.sub_yearly',
///       lifetime: 'com.myapp.lifetime',
///     ),
///     ios: IOSProducts(
///       monthly:  'com.myapp.sub_monthly',
///       yearly:   'com.myapp.sub_yearly',
///       lifetime: 'com.myapp.lifetime',
///     ),
///   ),
/// );
/// ```
library flutter_monetization;

// Exports sorted alphabetically within each layer group.
export 'src/core/monetization.dart';
export 'src/core/monetization_config.dart';
export 'src/delegates/analytics_delegate.dart';
export 'src/delegates/entitlement_observer.dart';
export 'src/delegates/sync_delegate.dart';
export 'src/models/entitlement_status.dart';
export 'src/models/monetization_exception.dart';
export 'src/models/platform_source.dart';
export 'src/models/purchase_result.dart';
export 'src/models/subscription_plan.dart';
export 'src/models/subscription_status.dart';
export 'src/storage/entitlement_storage.dart';
export 'src/utils/date_utils.dart';
export 'src/utils/monetization_logger.dart'
    show MonetizationLogLevel, MonetizationLogger;
