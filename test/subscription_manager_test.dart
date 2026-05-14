import 'package:flutter_monetization/flutter_monetization.dart';
import 'package:flutter_monetization/src/subscription/subscription_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks & fakes
// ---------------------------------------------------------------------------

class MockEntitlementStorage extends Mock implements EntitlementStorage {}

/// Fake required by mocktail so it can construct a placeholder value for
/// any `SubscriptionStatus` argument matched with `any()`.
class FakeSubscriptionStatus extends Fake implements SubscriptionStatus {}

// ---------------------------------------------------------------------------
// Config helper
// ---------------------------------------------------------------------------

MonetizationConfig _config() => const MonetizationConfig(
      android: AndroidProducts(
        monthly: 'android_monthly',
        yearly: 'android_yearly',
        lifetime: 'android_lifetime',
      ),
      ios: IOSProducts(
        monthly: 'ios_monthly',
        yearly: 'ios_yearly',
        lifetime: 'ios_lifetime',
      ),
      autoRestoreOnInit: false,
      logLevel: MonetizationLogLevel.none,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Register fallback value once for the entire test suite.
  // Required by mocktail whenever any() is used with a custom type.
  setUpAll(() {
    registerFallbackValue(FakeSubscriptionStatus());
  });

  late MockEntitlementStorage storage;
  late SubscriptionManager manager;

  setUp(() {
    storage = MockEntitlementStorage();
    when(() => storage.save(any())).thenAnswer((_) async {});
    when(() => storage.load()).thenAnswer((_) async => null);
    when(() => storage.clear()).thenAnswer((_) async {});

    manager = SubscriptionManager(
      config: _config(),
      storage: storage,
    );
  });

  tearDown(() async {
    await manager.dispose();
  });

  // -------------------------------------------------------------------------

  group('SubscriptionManager initial state', () {
    test('starts with unknown status', () {
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);
      expect(manager.currentStatus.isPremium, isFalse);
    });

    test('statusStream emits unknown on first listen', () async {
      final status = await manager.statusStream.first;
      expect(status.entitlementStatus, EntitlementStatus.unknown);
    });
  });

  // -------------------------------------------------------------------------

  group('SubscriptionManager loadCachedStatus', () {
    test('does nothing when cache is null', () async {
      when(() => storage.load()).thenAnswer((_) async => null);
      await manager.loadCachedStatus();
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);
    });

    test('emits cached status when fresh', () async {
      final cached = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 20)),
        lastVerifiedAt: DateTime.now(),
      );
      when(() => storage.load()).thenAnswer((_) async => cached);

      await manager.loadCachedStatus();

      expect(
        manager.currentStatus.entitlementStatus,
        EntitlementStatus.active,
      );
    });

    test('does not emit stale cache', () async {
      final stale = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 10)),
        lastVerifiedAt: DateTime.now().subtract(const Duration(hours: 25)),
      );
      when(() => storage.load()).thenAnswer((_) async => stale);

      await manager.loadCachedStatus();

      // Stale cache must not be applied — status stays unknown.
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);
    });
  });

  // -------------------------------------------------------------------------

  group('SubscriptionManager onRestoreFoundNoPurchases', () {
    test('emits notPurchased status', () {
      manager.onRestoreFoundNoPurchases();

      final status = manager.currentStatus;
      expect(status.entitlementStatus, EntitlementStatus.notPurchased);
      expect(status.isPremium, isFalse);
    });
  });

  // -------------------------------------------------------------------------

  group('SubscriptionManager updateFromRemote', () {
    test('upgrades when remote is better', () {
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);

      final remote = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.lifetime,
        platformSource: PlatformSource.appStore,
        lastVerifiedAt: DateTime.now(),
      );

      manager.updateFromRemote(remote);
      expect(manager.currentStatus.activePlan, SubscriptionPlan.lifetime);
      expect(manager.currentStatus.isPremium, isTrue);
    });

    test('does not downgrade active to notPurchased', () {
      // Push an active status in first.
      final active = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.yearly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 100)),
        lastVerifiedAt: DateTime.now(),
      );
      manager.updateFromRemote(active);
      expect(manager.currentStatus.isPremium, isTrue);

      // Attempt to downgrade — must be rejected.
      final notPurchased = SubscriptionStatus.notPurchased(
        platform: PlatformSource.googlePlay,
      );
      manager.updateFromRemote(notPurchased);

      expect(manager.currentStatus.isPremium, isTrue);
    });
  });
}
