import '../models/purchase_result.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';

/// Abstract interface for emitting monetization analytics events.
///
/// Implement this to forward events to Firebase Analytics, Mixpanel,
/// Amplitude, or any other analytics provider.
///
/// ## Firebase Analytics Example
/// ```dart
/// class FirebaseAnalyticsDelegate implements MonetizationAnalyticsDelegate {
///   final FirebaseAnalytics _analytics;
///
///   FirebaseAnalyticsDelegate(this._analytics);
///
///   @override
///   Future<void> onPurchaseStarted(SubscriptionPlan plan) async {
///     await _analytics.logEvent(
///       name: 'purchase_started',
///       parameters: {'plan': plan.name},
///     );
///   }
///
///   @override
///   Future<void> onPurchaseCompleted(PurchaseResult result) async {
///     if (result is PurchaseSuccess) {
///       await _analytics.logPurchase(
///         currency: 'USD',
///         value: 0,
///       );
///     }
///   }
/// }
/// ```
abstract interface class MonetizationAnalyticsDelegate {
  /// Called just before a purchase flow is initiated.
  Future<void> onPurchaseStarted(SubscriptionPlan plan);

  /// Called after a purchase attempt resolves (success, failure, cancel).
  Future<void> onPurchaseCompleted(PurchaseResult result);

  /// Called when a restore purchases flow is triggered.
  Future<void> onRestoreStarted();

  /// Called after a restore flow completes.
  Future<void> onRestoreCompleted(int restoredCount);

  /// Called when the entitlement status changes.
  Future<void> onEntitlementChanged(SubscriptionStatus status);
}
