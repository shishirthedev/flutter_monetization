import '../entitlement/entitlement_engine.dart';
import '../models/monetization_exception.dart';
import '../models/purchase_result.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import '../storage/entitlement_storage.dart';
import '../utils/monetization_logger.dart';
import 'monetization_config.dart';

/// The primary entry point for the flutter_monetization package.
///
/// ## Quick-start
/// ```dart
/// // 1. Configure once at app start
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
///
/// // 2. Purchase
/// final result = await Monetization.instance.purchase(
///   plan: SubscriptionPlan.monthly,
/// );
///
/// // 3. Check premium status
/// if (Monetization.instance.isPremium) {
///   // Disable ads, unlock features
/// }
///
/// // 4. React to changes
/// Monetization.instance.statusStream.listen((status) {
///   setState(() { _isPremium = status.isPremium; });
/// });
/// ```
class Monetization {
  Monetization._({
    required EntitlementEngine engine,
  }) : _engine = engine;

  static Monetization? _instance;

  final EntitlementEngine _engine;

  // ---------------------------------------------------------------------------
  // Static init / instance access
  // ---------------------------------------------------------------------------

  /// Initializes the SDK. Must be called once, early in your app lifecycle
  /// (e.g., in `main()` before `runApp`). Safe to await.
  ///
  /// Calling this a second time is a no-op and returns the existing instance.
  static Future<Monetization> init(
    MonetizationConfig config, {
    EntitlementStorage? storage,
  }) async {
    if (_instance != null) {
      logger.warning(
          'Monetization.init() called more than once. Returning existing instance.');
      return _instance!;
    }

    logger.setLevel(config.logLevel);
    logger.info('Monetization SDK initializing...');

    final resolvedStorage =
        storage ?? SharedPreferencesEntitlementStorage();

    final engine = EntitlementEngine(
      config: config,
      storage: resolvedStorage,
    );

    final sdk = Monetization._(engine: engine);
    _instance = sdk;

    await engine.initialize();

    logger.info('Monetization SDK ready.');
    return sdk;
  }

  /// Accesses the initialized [Monetization] instance.
  ///
  /// Throws [MonetizationNotInitializedException] if [init] has not been called.
  static Monetization get instance {
    if (_instance == null) {
      throw const MonetizationNotInitializedException();
    }
    return _instance!;
  }

  /// Returns true if [init] has been called successfully.
  static bool get isInitialized => _instance != null;

  /// Tears down the SDK. Call this only if you need to re-initialize
  /// (e.g., on user sign-out in a multi-account app).
  static Future<void> reset() async {
    await _instance?._engine.dispose();
    _instance = null;
    logger.info('Monetization SDK reset.');
  }

  // ---------------------------------------------------------------------------
  // Reactive API
  // ---------------------------------------------------------------------------

  /// Stream of [SubscriptionStatus] changes. Replays the latest value
  /// immediately on subscription (backed by [BehaviorSubject]).
  ///
  /// Use this to reactively update your UI or premium gating.
  Stream<SubscriptionStatus> get statusStream => _engine.statusStream;

  /// One-shot stream of [PurchaseResult] events.
  ///
  /// Listen to this to handle purchase outcomes after calling [purchase].
  Stream<PurchaseResult> get purchaseResultStream =>
      _engine.purchaseResultStream;

  // ---------------------------------------------------------------------------
  // Synchronous snapshot
  // ---------------------------------------------------------------------------

  /// The current [SubscriptionStatus] snapshot.
  ///
  /// This is always safe to read synchronously after [init] returns.
  SubscriptionStatus get status => _engine.currentStatus;

  /// True when premium access is currently granted.
  ///
  /// Safe for AdMob integration:
  /// ```dart
  /// if (Monetization.instance.isPremium) {
  ///   // Do not load ads
  /// }
  /// ```
  bool get isPremium => _engine.isPremium;

  /// True when the SDK is still determining entitlement (e.g., restoring).
  /// Show a loading indicator while this is true.
  bool get isLoading => _engine.isLoading;

  // ---------------------------------------------------------------------------
  // Purchase
  // ---------------------------------------------------------------------------

  /// Initiates a purchase for [plan].
  ///
  /// Returns immediately with a [PurchaseResult]:
  /// - [PurchasePending] — store UI shown; await [purchaseResultStream].
  /// - [PurchaseSuccess] — purchase complete (rare for IAP flows).
  /// - [PurchaseFailure] — something went wrong.
  /// - [PurchaseCancelled] — user cancelled.
  ///
  /// Always listen to [purchaseResultStream] for the definitive outcome.
  Future<PurchaseResult> purchase({required SubscriptionPlan plan}) =>
      _engine.purchase(plan);

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Restores previously purchased products.
  ///
  /// Required on iOS whenever the user reinstalls the app or changes devices.
  /// On Android, purchases are typically restored automatically, but calling
  /// this is still good practice.
  ///
  /// Returns [RestoreResult] indicating how many items were restored.
  Future<RestoreResult> restorePurchases() => _engine.restorePurchases();

  // ---------------------------------------------------------------------------
  // Product details (for paywall UI)
  // ---------------------------------------------------------------------------

  /// Returns a map of product metadata (price, title, description) keyed by
  /// product ID. Use this to build your paywall pricing UI.
  ///
  /// Returns an empty map if products haven't loaded yet.
  Map<String, dynamic> get productDetails => _engine.productDetails;
}
