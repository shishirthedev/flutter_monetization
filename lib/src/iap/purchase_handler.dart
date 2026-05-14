import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/monetization_config.dart';
import '../models/entitlement_status.dart';
import '../models/monetization_exception.dart';
import '../models/platform_source.dart';
import '../models/purchase_result.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import '../platform/platform_product_resolver.dart';
import '../subscription/subscription_manager.dart';
import '../utils/monetization_logger.dart';

/// Manages all interactions with the [InAppPurchase] plugin.
///
/// This class is intentionally kept thin — it translates raw plugin events
/// into domain objects and delegates entitlement logic to [SubscriptionManager].
class PurchaseHandler {
  PurchaseHandler({
    required MonetizationConfig config,
    required SubscriptionManager subscriptionManager,
    InAppPurchase? iap,
  })  : _subscriptionManager = subscriptionManager,
        _iap = iap ?? InAppPurchase.instance,
        _resolver = PlatformProductResolver(config);

  final SubscriptionManager _subscriptionManager;
  final InAppPurchase _iap;
  final PlatformProductResolver _resolver;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  /// Cached product details fetched from the store.
  final Map<String, ProductDetails> _productDetailsCache = {};

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initializes the purchase stream listener. Call once during SDK init.
  Future<void> initialize() async {
    final isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      logger.warning('IAP is not available on this device.');
      throw const IAPUnavailableException();
    }

    // Pre-load product details
    await _loadProductDetails();

    // Subscribe to the purchase update stream
    _purchaseSubscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object error, StackTrace st) {
        logger.error('Purchase stream error', error, st);
        _subscriptionManager.onPurchaseStreamError(error, st);
      },
    );

    logger.info('PurchaseHandler initialized.');
  }

  /// Loads (or refreshes) product details from the store.
  Future<void> _loadProductDetails() async {
    final ids = _resolver.allProductIds;
    try {
      final response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        logger.warning(
            'Product details query error: ${response.error!.message}');
      }

      for (final pd in response.productDetails) {
        _productDetailsCache[pd.id] = pd;
        logger.debug('Loaded product: ${pd.id} | ${pd.price}');
      }

      if (response.notFoundIDs.isNotEmpty) {
        logger.warning(
            'Products not found in store: ${response.notFoundIDs.join(', ')}');
      }
    } catch (e, st) {
      logger.error('Failed to load product details', e, st);
      // Non-fatal: purchase can still be attempted if products were cached.
    }
  }

  // ---------------------------------------------------------------------------
  // Purchase
  // ---------------------------------------------------------------------------

  /// Initiates a purchase for [plan]. Returns a [PurchaseResult] sealed class.
  Future<PurchaseResult> purchase(SubscriptionPlan plan) async {
    logger.info('Initiating purchase for plan: ${plan.name}');

    final productId = _resolver.productIdFor(plan);
    final productDetails = _productDetailsCache[productId];

    if (productDetails == null) {
      // Attempt a fresh load before giving up
      await _loadProductDetails();
      final retried = _productDetailsCache[productId];
      if (retried == null) {
        logger.error('Product not found: $productId');
        return PurchaseFailure(
          plan: plan,
          message: 'Product "$productId" could not be loaded from the store.',
        );
      }
    }

    final details = _productDetailsCache[productId]!;

    try {
      final PurchaseParam param;

      // For Android, subscriptions may need upgrading from previous plan
      if (_resolver.isAndroid) {
        param = PurchaseParam(productDetails: details);
      } else {
        param = PurchaseParam(productDetails: details);
      }

      // Both subscriptions and lifetime purchases are non-consumable
      // from the in_app_purchase plugin's perspective. Consumables are
      // one-time items like coins/credits that are "used up" after purchase.
      final bool purchaseInitiated = await _iap.buyNonConsumable(
        purchaseParam: param,
      );

      if (!purchaseInitiated) {
        return PurchaseFailure(
          plan: plan,
          message: 'Purchase could not be initiated.',
        );
      }

      // The actual result arrives via purchaseStream → _onPurchaseUpdate
      // We return a pending state and the stream handles the final update
      return PurchasePending(plan: plan);
    } catch (e, st) {
      logger.error('Purchase exception', e, st);
      return PurchaseFailure(
        plan: plan,
        message: e.toString(),
        underlyingError: e,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Triggers a restore of previous purchases. The stream will emit results.
  Future<RestoreResult> restorePurchases() async {
    logger.info('Restoring purchases...');
    try {
      await _iap.restorePurchases();
      // Stream handles the rest. We give store a moment to emit.
      await Future<void>.delayed(const Duration(seconds: 2));
      final status = _subscriptionManager.currentStatus;
      return RestoreResult(
        restoredCount: status.isPremium ? 1 : 0,
      );
    } catch (e, st) {
      logger.error('Restore failed', e, st);
      return RestoreResult(
        restoredCount: 0,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Stream handler
  // ---------------------------------------------------------------------------

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _processPurchase(purchase);
    }
  }

  void _processPurchase(PurchaseDetails purchase) {
    logger.debug(
        'Purchase update: ${purchase.productID} | ${purchase.status}');

    switch (purchase.status) {
      case PurchaseStatus.pending:
        logger.info('Purchase pending: ${purchase.productID}');
        break;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _handleVerifiedPurchase(purchase);
        break;

      case PurchaseStatus.error:
        logger.error(
          'Purchase error: ${purchase.productID}',
          purchase.error,
        );
        _subscriptionManager.onPurchaseError(purchase);
        break;

      case PurchaseStatus.canceled:
        logger.info('Purchase cancelled: ${purchase.productID}');
        _subscriptionManager.onPurchaseCancelled(purchase);
        break;
    }

    // Always complete pending transactions to avoid being charged again.
    if (purchase.pendingCompletePurchase) {
      _iap.completePurchase(purchase);
    }
  }

  void _handleVerifiedPurchase(PurchaseDetails purchase) {
    final plan = _resolver.planForProductId(purchase.productID);
    final platform = _resolver.currentPlatform;

    final status = _buildStatusFromPurchase(
      purchase: purchase,
      plan: plan,
      platform: platform,
    );

    _subscriptionManager.onPurchaseVerified(status, purchase);
  }

  SubscriptionStatus _buildStatusFromPurchase({
    required PurchaseDetails purchase,
    required SubscriptionPlan plan,
    required PlatformSource platform,
  }) {
    DateTime? expiryDate;

    // Try to extract expiry from verification data (Android/iOS specific)
    if (purchase.verificationData.serverVerificationData.isNotEmpty) {
      // Consumers can implement a server-side receipt validation and inject
      // expiry via the SyncDelegate.fetchRemoteEntitlement hook.
      // Here we set a safe default for subscriptions.
      if (plan.isSubscription) {
        expiryDate = _estimateExpiry(plan);
      }
    }

    return SubscriptionStatus(
      entitlementStatus: _resolveEntitlementStatus(
        plan: plan,
        expiryDate: expiryDate,
        purchaseStatus: purchase.status,
      ),
      activePlan: plan,
      platformSource: platform,
      expiryDate: expiryDate,
      originalTransactionId: purchase.purchaseID,
      productId: purchase.productID,
      lastVerifiedAt: DateTime.now(),
    );
  }

  /// Estimates subscription expiry client-side. For production, replace with
  /// server-side receipt validation for accuracy.
  DateTime _estimateExpiry(SubscriptionPlan plan) {
    final now = DateTime.now();
    switch (plan) {
      case SubscriptionPlan.monthly:
        return now.add(const Duration(days: 31));
      case SubscriptionPlan.yearly:
        return now.add(const Duration(days: 366));
      default:
        return now;
    }
  }

  EntitlementStatus _resolveEntitlementStatus({
    required SubscriptionPlan plan,
    required DateTime? expiryDate,
    required PurchaseStatus purchaseStatus,
  }) {
    if (purchaseStatus == PurchaseStatus.error) {
      return EntitlementStatus.expired;
    }
    if (plan.isLifetime) return EntitlementStatus.active;
    if (expiryDate == null) return EntitlementStatus.active;
    if (expiryDate.isAfter(DateTime.now())) return EntitlementStatus.active;
    return EntitlementStatus.expired;
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _productDetailsCache.clear();
    logger.debug('PurchaseHandler disposed.');
  }

  /// Returns cached [ProductDetails] for display in your UI (price, title).
  Map<String, ProductDetails> get productDetailsCache =>
      Map.unmodifiable(_productDetailsCache);
}
