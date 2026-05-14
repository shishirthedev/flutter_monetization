import '../models/subscription_status.dart';

/// Observer interface for reacting to entitlement lifecycle events.
///
/// Register a concrete implementation via [MonetizationConfig] to respond
/// to changes without subscribing to the reactive stream. Useful for
/// side-effects like updating UI state managers.
abstract interface class EntitlementObserver {
  /// Called on the UI thread whenever [SubscriptionStatus] changes.
  void onStatusChanged(SubscriptionStatus status);

  /// Called when the entitlement engine finishes loading (leaves [unknown]).
  void onLoadingComplete(SubscriptionStatus status);

  /// Called when any error occurs during purchase or restore.
  void onError(Object error, StackTrace stackTrace);
}
