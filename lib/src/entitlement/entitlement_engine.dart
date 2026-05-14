import 'dart:async' show unawaited;

import '../core/monetization_config.dart';
import '../iap/purchase_handler.dart';
import '../models/purchase_result.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import '../storage/entitlement_storage.dart';
import '../subscription/subscription_manager.dart';
import '../utils/monetization_logger.dart';

/// The central coordinator of the monetization SDK.
///
/// [EntitlementEngine] owns the [SubscriptionManager] and [PurchaseHandler],
/// wires them together, and exposes the high-level API consumed by [Monetization].
///
/// Lifecycle:
/// 1. [initialize] — loads cache, starts IAP, restores purchases.
/// 2. [purchase] / [restorePurchases] — initiates store interactions.
/// 3. [dispose] — cleans up all subscriptions and streams.
class EntitlementEngine {
  EntitlementEngine({
    required MonetizationConfig config,
    required EntitlementStorage storage,
    PurchaseHandler? purchaseHandler,
    SubscriptionManager? subscriptionManager,
  }) : _config = config {
    _subscriptionManager = subscriptionManager ??
        SubscriptionManager(
          config: config,
          storage: storage,
        );

    _purchaseHandler = purchaseHandler ??
        PurchaseHandler(
          config: config,
          subscriptionManager: _subscriptionManager,
        );
  }

  final MonetizationConfig _config;
  late final SubscriptionManager _subscriptionManager;
  late final PurchaseHandler _purchaseHandler;

  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Public reactive API
  // ---------------------------------------------------------------------------

  /// Reactive stream of the current [SubscriptionStatus].
  Stream<SubscriptionStatus> get statusStream =>
      _subscriptionManager.statusStream;

  /// One-shot stream of purchase outcomes (success, failure, cancel).
  Stream<PurchaseResult> get purchaseResultStream =>
      _subscriptionManager.purchaseResultStream;

  /// Synchronous snapshot of the latest [SubscriptionStatus].
  SubscriptionStatus get currentStatus => _subscriptionManager.currentStatus;

  /// Convenience: true when premium access is granted.
  bool get isPremium => currentStatus.isPremium;

  /// Convenience: true when still loading from store.
  bool get isLoading => currentStatus.isLoading;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Must be called once before any other method. Safe to await on app startup.
  ///
  /// Steps:
  /// 1. Load cached entitlement as a startup hint.
  /// 2. Initialize IAP layer and purchase stream.
  /// 3. Optionally query remote delegate.
  /// 4. Optionally restore purchases.
  Future<void> initialize() async {
    if (_initialized) {
      logger.warning('EntitlementEngine already initialized — skipping.');
      return;
    }

    logger.info('EntitlementEngine initializing...');

    // Step 1: Cache (fast path for UI)
    await _subscriptionManager.loadCachedStatus();

    // Step 2: IAP
    try {
      await _purchaseHandler.initialize();
    } catch (e, st) {
      logger.error('IAP unavailable during init', e, st);
      // Don't crash — degrade gracefully. Status stays unknown.
    }

    // Step 3: Remote hint (optional)
    await _fetchRemoteHint();

    // Step 4: Restore
    if (_config.autoRestoreOnInit) {
      await restorePurchases();
    }

    _initialized = true;
    logger.info('EntitlementEngine initialized. Status: ${currentStatus.entitlementStatus.name}');
  }

  Future<void> _fetchRemoteHint() async {
    final delegate = _config.syncDelegate;
    if (delegate == null) return;

    try {
      final remote = await delegate.fetchRemoteEntitlement();
      if (remote != null) {
        _subscriptionManager.updateFromRemote(remote);
      }
    } catch (e, st) {
      logger.error('Remote hint fetch failed', e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Purchase
  // ---------------------------------------------------------------------------

  /// Initiates a purchase for [plan]. Returns a [PurchaseResult].
  ///
  /// The [PurchasePending] result means the store UI was shown and the real
  /// result will arrive on [purchaseResultStream]. Listen to that stream
  /// for final success/failure.
  Future<PurchaseResult> purchase(SubscriptionPlan plan) async {
    _assertInitialized();
    logger.info('purchase() called for plan: ${plan.name}');

    unawaited(_config.analyticsDelegate?.onPurchaseStarted(plan) ?? Future<void>.value());

    final result = await _purchaseHandler.purchase(plan);

    unawaited(_config.analyticsDelegate?.onPurchaseCompleted(result) ?? Future<void>.value());

    return result;
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Restores previous purchases. Always returns a [RestoreResult].
  Future<RestoreResult> restorePurchases() async {
    logger.info('restorePurchases() called.');
    unawaited(_config.analyticsDelegate?.onRestoreStarted() ?? Future<void>.value());

    final result = await _purchaseHandler.restorePurchases();

    unawaited(_config.analyticsDelegate?.onRestoreCompleted(result.restoredCount) ?? Future<void>.value());
    unawaited(
      _config.syncDelegate
          ?.onRestoreCompleted(currentStatus)
          .catchError((Object e) {
        logger.error('SyncDelegate.onRestoreCompleted failed', e);
      }) ??
          Future<void>.value(),
    );

    logger.info('restorePurchases() complete. Restored: ${result.restoredCount}');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Product details (for your pricing UI)
  // ---------------------------------------------------------------------------

  /// Returns cached product details keyed by product ID.
  /// Use to display localized prices in your paywall UI.
  Map<String, dynamic> get productDetails =>
      _purchaseHandler.productDetailsCache
          .map((key, pd) => MapEntry(key, {
                'id': pd.id,
                'title': pd.title,
                'description': pd.description,
                'price': pd.price,
                'currencyCode': pd.currencyCode,
                'rawPrice': pd.rawPrice,
              }));

  // ---------------------------------------------------------------------------
  // Guards
  // ---------------------------------------------------------------------------

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'EntitlementEngine not initialized. Call initialize() first.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _purchaseHandler.dispose();
    await _subscriptionManager.dispose();
    _initialized = false;
    logger.debug('EntitlementEngine disposed.');
  }
}
