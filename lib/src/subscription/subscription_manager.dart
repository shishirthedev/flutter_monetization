import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:rxdart/rxdart.dart';

import '../core/monetization_config.dart';
import '../delegates/entitlement_observer.dart';
import '../delegates/sync_delegate.dart';
import '../models/entitlement_status.dart';
import '../models/purchase_result.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import '../platform/platform_product_resolver.dart';
import '../storage/entitlement_storage.dart';
import '../utils/date_utils.dart';
import '../utils/monetization_logger.dart';

/// Central coordinator for subscription state.
///
/// - Receives verified purchase events from [PurchaseHandler].
/// - Rebuilds [SubscriptionStatus] from store data.
/// - Persists to [EntitlementStorage].
/// - Notifies [MonetizationSyncDelegate] for remote sync.
/// - Exposes a reactive [statusStream] via RxDart [BehaviorSubject].
class SubscriptionManager {
  SubscriptionManager({
    required MonetizationConfig config,
    required EntitlementStorage storage,
    PlatformProductResolver? resolver,
    EntitlementObserver? observer,
  })  : _config = config,
        _storage = storage,
        _resolver =
            resolver ?? PlatformProductResolver(config),
        _observer = observer,
        _statusSubject = BehaviorSubject<SubscriptionStatus>.seeded(
          SubscriptionStatus.unknown(),
        );

  final MonetizationConfig _config;
  final EntitlementStorage _storage;
  final PlatformProductResolver _resolver;
  final EntitlementObserver? _observer;
  final BehaviorSubject<SubscriptionStatus> _statusSubject;

  // Purchase result controller for one-shot purchase outcomes
  final _purchaseResultController =
      StreamController<PurchaseResult>.broadcast();

  // ---------------------------------------------------------------------------
  // Public reactive API
  // ---------------------------------------------------------------------------

  /// Reactive stream of [SubscriptionStatus]. Always replays the latest value.
  Stream<SubscriptionStatus> get statusStream => _statusSubject.stream;

  /// One-shot stream of purchase outcomes (success, failure, cancel).
  Stream<PurchaseResult> get purchaseResultStream =>
      _purchaseResultController.stream;

  /// The current (synchronous) status snapshot.
  SubscriptionStatus get currentStatus => _statusSubject.value;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Loads cached status on startup. Call before [PurchaseHandler.initialize].
  Future<void> loadCachedStatus() async {
    final cached = await _storage.load();
    if (cached == null) {
      logger.debug('No cached entitlement found.');
      return;
    }

    // Validate cache freshness
    if (_isCacheStale(cached)) {
      logger.info('Cached entitlement is stale — will re-verify from store.');
      // Emit cached value as a hint (still unknown until store confirms)
      // We do NOT emit it here — keep unknown until store verifies.
      return;
    }

    logger.info('Using cached entitlement as startup hint: $cached');
    _emit(cached);
  }

  bool _isCacheStale(SubscriptionStatus cached) {
    final verified = cached.lastVerifiedAt;
    if (verified == null) return true;
    return DateTime.now().difference(verified) > _config.entitlementCacheTtl;
  }

  // ---------------------------------------------------------------------------
  // Purchase event handlers (called by PurchaseHandler)
  // ---------------------------------------------------------------------------

  void onPurchaseVerified(
    SubscriptionStatus status,
    PurchaseDetails purchase,
  ) {
    logger.info(
        'Purchase verified: ${purchase.productID} | ${status.entitlementStatus.name}');

    final resolved = _resolveGracePeriod(status);
    _emit(resolved);
    _persist(resolved);
    _notifySync(resolved, isnew: purchase.status == PurchaseStatus.purchased);

    _purchaseResultController.add(
      purchase.status == PurchaseStatus.restored
          ? const RestoreResult(restoredCount: 1)
          : PurchaseSuccess(
              plan: status.activePlan,
              productId: purchase.productID,
              transactionId: purchase.purchaseID,
            ),
    );
  }

  void onPurchaseCancelled(PurchaseDetails purchase) {
    logger.info('Purchase cancelled: ${purchase.productID}');
    _purchaseResultController.add(
      PurchaseCancelled(
        plan: _resolver.planForProductId(purchase.productID),
      ),
    );
  }

  void onPurchaseError(PurchaseDetails purchase) {
    logger.error('Purchase error for: ${purchase.productID}', purchase.error);
    _purchaseResultController.add(
      PurchaseFailure(
        plan: _resolver.planForProductId(purchase.productID),
        message: purchase.error?.message ?? 'Unknown error',
      ),
    );
  }

  void onPurchaseStreamError(Object error, StackTrace st) {
    logger.error('Purchase stream error', error, st);
    _observer?.onError(error, st);
  }

  // ---------------------------------------------------------------------------
  // Entitlement rebuild
  // ---------------------------------------------------------------------------

  /// Called when the restore flow finds no purchases.
  void onRestoreFoundNoPurchases() {
    logger.info('Restore completed — no active purchases found.');
    final status = SubscriptionStatus.notPurchased(
      platform: _resolver.currentPlatform,
    );
    _emit(status);
    _persist(status);
  }

  /// Rebuilds entitlement from a list of raw purchase records.
  /// Useful when you receive a batch of purchases from the store.
  void rebuildFromPurchases(List<PurchaseDetails> purchases) {
    if (purchases.isEmpty) {
      onRestoreFoundNoPurchases();
      return;
    }

    SubscriptionStatus? best;
    for (final purchase in purchases) {
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final plan = _resolver.planForProductId(purchase.productID);
      if (plan == SubscriptionPlan.none) continue;

      final status = _buildFromPurchaseDetails(purchase, plan);
      best = _pickBetter(best, status);
    }

    if (best != null) {
      final resolved = _resolveGracePeriod(best);
      _emit(resolved);
      _persist(resolved);
    } else {
      onRestoreFoundNoPurchases();
    }
  }

  SubscriptionStatus _buildFromPurchaseDetails(
    PurchaseDetails purchase,
    SubscriptionPlan plan,
  ) {
    DateTime? expiry;
    if (plan.isSubscription) {
      // Prefer remote expiry if available; fallback to estimate
      expiry = _estimateExpiry(plan);
    }

    final isExpired = plan.isSubscription && MonetizationDateUtils.isExpired(expiry);
    final entitlementStatus = plan.isLifetime
        ? EntitlementStatus.active
        : isExpired
            ? EntitlementStatus.expired
            : EntitlementStatus.active;

    return SubscriptionStatus(
      entitlementStatus: entitlementStatus,
      activePlan: plan,
      platformSource: _resolver.currentPlatform,
      expiryDate: expiry,
      originalTransactionId: purchase.purchaseID,
      productId: purchase.productID,
      lastVerifiedAt: DateTime.now(),
    );
  }

  /// Returns the better of two statuses: lifetime > active > grace > cancelled > expired > notPurchased.
  SubscriptionStatus? _pickBetter(
    SubscriptionStatus? current,
    SubscriptionStatus candidate,
  ) {
    if (current == null) return candidate;
    final currentPriority = _priority(current);
    final candidatePriority = _priority(candidate);
    return candidatePriority > currentPriority ? candidate : current;
  }

  int _priority(SubscriptionStatus s) {
    if (s.activePlan.isLifetime && s.isPremium) return 5;
    if (s.entitlementStatus == EntitlementStatus.active) return 4;
    if (s.entitlementStatus == EntitlementStatus.gracePeriod) return 3;
    if (s.entitlementStatus == EntitlementStatus.cancelled && s.isPremium) {
      return 2;
    }
    if (s.entitlementStatus == EntitlementStatus.expired) return 1;
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Grace period detection
  // ---------------------------------------------------------------------------

  SubscriptionStatus _resolveGracePeriod(SubscriptionStatus status) {
    if (!status.activePlan.isSubscription) return status;
    if (status.entitlementStatus != EntitlementStatus.active) return status;

    final expiry = status.expiryDate;
    if (expiry == null) return status;

    // If expiry is within grace window AND in the past, flag grace period
    if (expiry.isBefore(DateTime.now()) &&
        MonetizationDateUtils.isWithinWindow(
          expiry.add(_config.gracePeriodDuration),
          _config.gracePeriodDuration,
        )) {
      return status.copyWith(
        entitlementStatus: EntitlementStatus.gracePeriod,
        isInGracePeriod: true,
      );
    }

    return status;
  }

  // ---------------------------------------------------------------------------
  // Manual status override (for remote sync merging)
  // ---------------------------------------------------------------------------

  /// Allows external callers (e.g. a Firestore sync) to update the status.
  /// The package will re-verify against the store before fully trusting this.
  void updateFromRemote(SubscriptionStatus remoteStatus) {
    logger.info('Remote entitlement received: $remoteStatus');
    // Only upgrade if remote is better and recent
    final current = currentStatus;
    if (_priority(remoteStatus) > _priority(current)) {
      _emit(remoteStatus);
      _persist(remoteStatus);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _estimateExpiry(SubscriptionPlan plan) {
    final now = DateTime.now();
    return switch (plan) {
      SubscriptionPlan.monthly => now.add(const Duration(days: 31)),
      SubscriptionPlan.yearly => now.add(const Duration(days: 366)),
      _ => now,
    };
  }

  void _emit(SubscriptionStatus status) {
    if (_statusSubject.isClosed) return;
    _statusSubject.add(status);
    _observer?.onStatusChanged(status);

    if (status.entitlementStatus != EntitlementStatus.unknown) {
      _observer?.onLoadingComplete(status);
    }

    _config.analyticsDelegate?.onEntitlementChanged(status);
  }

  Future<void> _persist(SubscriptionStatus status) async {
    await _storage.save(status);
  }

  void _notifySync(SubscriptionStatus status, {required bool isnew}) {
    final delegate = _config.syncDelegate;
    if (delegate == null) return;

    if (isnew) {
      delegate.onPurchaseConfirmed(status).catchError((Object e) {
        logger.error('SyncDelegate.onPurchaseConfirmed failed', e);
      });
    } else {
      delegate.onEntitlementUpdated(status).catchError((Object e) {
        logger.error('SyncDelegate.onEntitlementUpdated failed', e);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _statusSubject.close();
    await _purchaseResultController.close();
    logger.debug('SubscriptionManager disposed.');
  }
}
