import 'dart:io';

import '../core/monetization_config.dart';
import '../models/monetization_exception.dart';
import '../models/platform_source.dart';
import '../models/subscription_plan.dart';

/// Resolves product IDs and platform identity at runtime.
class PlatformProductResolver {
  const PlatformProductResolver(this._config);

  final MonetizationConfig _config;

  PlatformSource get currentPlatform {
    if (Platform.isAndroid) return PlatformSource.googlePlay;
    if (Platform.isIOS) return PlatformSource.appStore;
    return PlatformSource.unknown;
  }

  bool get isAndroid => Platform.isAndroid;
  bool get isIOS => Platform.isIOS;

  /// Returns the platform-appropriate product ID for [plan].
  String productIdFor(SubscriptionPlan plan) {
    final planKey = _planKey(plan);
    if (Platform.isAndroid) return _config.androidProductId(planKey);
    if (Platform.isIOS) return _config.iosProductId(planKey);
    throw ProductNotFoundException(planKey, 'unsupported_platform');
  }

  /// All product IDs the IAP layer should load from the store.
  Set<String> get allProductIds => _config.allProductIds;

  /// Attempts to match a raw store [productId] back to a [SubscriptionPlan].
  /// Returns [SubscriptionPlan.none] if not recognized.
  SubscriptionPlan planForProductId(String productId) {
    final android = _config.android;
    final ios = _config.ios;
    if (productId == android.monthly || productId == ios.monthly) {
      return SubscriptionPlan.monthly;
    }
    if (productId == android.yearly || productId == ios.yearly) {
      return SubscriptionPlan.yearly;
    }
    if (productId == android.lifetime || productId == ios.lifetime) {
      return SubscriptionPlan.lifetime;
    }
    return SubscriptionPlan.none;
  }

  String _planKey(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.monthly:
        return 'monthly';
      case SubscriptionPlan.yearly:
        return 'yearly';
      case SubscriptionPlan.lifetime:
        return 'lifetime';
      case SubscriptionPlan.none:
        throw ProductNotFoundException('none', currentPlatform.name);
    }
  }
}
