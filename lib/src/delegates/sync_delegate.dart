import '../models/subscription_status.dart';

/// Abstract interface for syncing entitlement data to a remote backend.
///
/// Implement this in your app to push entitlement changes to Firestore,
/// a custom REST API, or any other backend. The package will call the
/// appropriate hooks at the right lifecycle moments.
///
/// ## Firestore Example
/// ```dart
/// class FirestoreSyncDelegate implements MonetizationSyncDelegate {
///   final FirebaseFirestore _db;
///   final String _userId;
///
///   FirestoreSyncDelegate(this._db, this._userId);
///
///   @override
///   Future<void> onEntitlementUpdated(SubscriptionStatus status) async {
///     await _db.collection('users').doc(_userId).set({
///       'isPremium': status.isPremium,
///       'plan': status.activePlan.name,
///       'expiryDate': status.expiryDate,
///       'updatedAt': FieldValue.serverTimestamp(),
///     }, SetOptions(merge: true));
///   }
///
///   @override
///   Future<SubscriptionStatus?> fetchRemoteEntitlement() async {
///     final doc = await _db.collection('users').doc(_userId).get();
///     if (!doc.exists) return null;
///     // Map your Firestore schema to SubscriptionStatus here
///     return null;
///   }
///
///   @override
///   Future<void> onRestoreCompleted(SubscriptionStatus status) async {
///     await onEntitlementUpdated(status);
///   }
/// }
/// ```
abstract interface class MonetizationSyncDelegate {
  /// Called whenever the local entitlement state changes.
  ///
  /// Implementations should be non-blocking and handle their own errors.
  Future<void> onEntitlementUpdated(SubscriptionStatus status);

  /// Called after a restore purchases flow completes.
  Future<void> onRestoreCompleted(SubscriptionStatus status);

  /// Called when a new purchase is confirmed by the store.
  Future<void> onPurchaseConfirmed(SubscriptionStatus status);

  /// Optional: Fetch entitlement from the remote backend.
  ///
  /// If this returns a non-null value, it is merged with the local state
  /// as a hint (the store is still the final source of truth).
  /// Return null to skip remote fetch.
  Future<SubscriptionStatus?> fetchRemoteEntitlement();
}
